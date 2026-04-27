#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# scripts/ops/backup-postgres.sh — Tier 1 backup
#
# pg_dump → GPG encrypt → rclone upload to remote backup storage
# (Scaleway Object Storage par défaut, mais BACKUP_REMOTE peut pointer
#  sur n'importe quel remote rclone : B2, S3, GCS, etc.)
# Streaming (zéro fichier intermédiaire sur disque, donc :
#   - pas de fuite si le VPS est compromis pendant le backup
#   - pas de besoin d'espace temporaire pour les gros dumps).
#
# Usage :
#   bash scripts/ops/backup-postgres.sh                # mode standard
#   DRY_RUN=1 bash scripts/ops/backup-postgres.sh      # simu sans upload
#
# Cron typique : `0 3 * * * /path/to/backup-postgres.sh >> /var/log/terrasses-backup/cron.log 2>&1`
#
# Pré-requis :
#   - rclone configuré avec un remote (default `scaleway` — voir BACKUP_REMOTE)
#   - GPG public key importée (recipient = $GPG_RECIPIENT)
#   - Container Postgres `supabase-db` en cours d'exécution
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────
DB_CONTAINER="${DB_CONTAINER:-terrasses-supabase-db}"
GPG_RECIPIENT="${GPG_RECIPIENT:-backup@terrasse-au-soleil.fr}"
BACKUP_REMOTE="${BACKUP_REMOTE:-scaleway}"
BACKUP_BUCKET="${BACKUP_BUCKET:-iremia-supabase-backups}"
BACKUP_PATH="${BACKUP_PATH:-postgres/terrasses}"
LOG_DIR="${LOG_DIR:-/var/log/terrasses-backup}"
DRY_RUN="${DRY_RUN:-}"

TIMESTAMP=$(date -u +%Y-%m-%dT%H-%M-%SZ)
HOSTNAME=$(hostname -s)
BACKUP_KEY="$BACKUP_PATH/$HOSTNAME-$TIMESTAMP.dump.gpg"
LOG_FILE="$LOG_DIR/backup-$TIMESTAMP.log"

# ─── Logging helpers ─────────────────────────────────────────
mkdir -p "$LOG_DIR"
log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG_FILE"; }
fail() { log "❌ $*"; exit 1; }

log "═══ Terrasses Supabase backup ═══"
log "Host:        $HOSTNAME"
log "Container:   $DB_CONTAINER"
log "GPG key:     $GPG_RECIPIENT"
log "Destination: $BACKUP_REMOTE:$BACKUP_BUCKET/$BACKUP_KEY"
log "Dry-run:     ${DRY_RUN:-no}"

# ─── Pré-flight checks ───────────────────────────────────────
command -v docker  >/dev/null || fail "docker not in PATH"
command -v gpg     >/dev/null || fail "gpg not in PATH (apt-get install gnupg)"
command -v rclone  >/dev/null || fail "rclone not in PATH (apt-get install rclone)"

docker inspect "$DB_CONTAINER" >/dev/null 2>&1 || fail "container '$DB_CONTAINER' not running"
gpg --list-keys "$GPG_RECIPIENT" >/dev/null 2>&1 \
  || fail "GPG public key for '$GPG_RECIPIENT' not imported"
rclone listremotes | grep -q "^${BACKUP_REMOTE}:$" \
  || fail "rclone remote '$BACKUP_REMOTE' not configured (run: rclone config)"

# ─── Pre-backup manifest (counts) ─────────────────────────────
# On enregistre le COUNT(*) par table dans une note de provenance.
# Sert à valider l'intégrité du restore (vs le dump tout chaud).
log "→ Generating row count manifest"
MANIFEST=$(docker exec -i "$DB_CONTAINER" psql -U supabase_admin -d postgres -At -F"|" -c "
  SELECT n.nspname || '.' || c.relname || '|' || c.reltuples::bigint
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind = 'r'
    AND n.nspname NOT IN ('pg_catalog','information_schema','pg_toast','extensions','vault')
  ORDER BY n.nspname, c.relname;
")
log "  $(echo "$MANIFEST" | wc -l) tables tracked"

# ─── pg_dump → GPG → rclone (streaming) ──────────────────────
START=$(date +%s)
log "→ pg_dump → GPG → B2 (streaming)"

if [[ -n "$DRY_RUN" ]]; then
  log "[DRY-RUN] Would run :"
  log "  docker exec $DB_CONTAINER pg_dump -U supabase_admin -d postgres -Fc -Z9 \\"
  log "    | gpg --encrypt --recipient $GPG_RECIPIENT --trust-model always --batch \\"
  log "    | rclone rcat $BACKUP_REMOTE:$BACKUP_BUCKET/$BACKUP_KEY"
  exit 0
fi

# Pipe complet, set -o pipefail détecte tout échec dans la chaîne
docker exec -i "$DB_CONTAINER" \
    pg_dump -U supabase_admin -d postgres --format=custom --compress=9 \
  | gpg --encrypt --recipient "$GPG_RECIPIENT" --trust-model always --batch --quiet \
  | rclone rcat "$BACKUP_REMOTE:$BACKUP_BUCKET/$BACKUP_KEY"

DURATION=$(($(date +%s) - START))

# ─── Récupérer la taille uploadée ─────────────────────────────
SIZE_BYTES=$(rclone size "$BACKUP_REMOTE:$BACKUP_BUCKET/$BACKUP_KEY" --json 2>/dev/null \
  | grep -oE '"bytes":[0-9]+' | grep -oE '[0-9]+' || echo "0")

# Affichage humain-readable : KB pour <1MB, MB pour <1GB, sinon GB.
if [[ "$SIZE_BYTES" -lt 1048576 ]]; then
  SIZE_HUMAN="$(( SIZE_BYTES / 1024 )) KB"
elif [[ "$SIZE_BYTES" -lt 1073741824 ]]; then
  SIZE_HUMAN="$(( SIZE_BYTES / 1048576 )) MB"
else
  SIZE_HUMAN="$(awk "BEGIN { printf \"%.2f GB\", $SIZE_BYTES / 1073741824 }")"
fi

# Anomalie : un dump < 10 KB est suspect.
# - Un dump pg_dump --format=custom même sur DB vide fait ~10-50 KB (definitions du schéma)
# - Un dump vide / quasi-vide = pipe cassé silencieusement (gpg/rclone OK mais pg_dump KO)
if [[ "$SIZE_BYTES" -lt 10240 ]]; then
  log "❌ ERREUR: backup size $SIZE_BYTES bytes — anormalement petit"
  log "   Possible cause : pg_dump pipe broken silently, ou container down"
  log "   Le fichier uploadé est probablement corrompu/vide. Investiguer avant de fier."
  log "   Diagnostic : docker exec $DB_CONTAINER pg_dump -U supabase_admin -d postgres --schema-only | head"
  exit 2
fi

log "✓ Backup completed in ${DURATION}s — $SIZE_HUMAN encrypted ($SIZE_BYTES bytes)"

# ─── Écrire le manifest à côté du dump ───────────────────────
log "→ Uploading row count manifest"
echo "$MANIFEST" | rclone rcat "$BACKUP_REMOTE:$BACKUP_BUCKET/$BACKUP_KEY.manifest"

# ─── Sanity : vérifier qu'il existe bien côté remote ──────────
if rclone lsf "$BACKUP_REMOTE:$BACKUP_BUCKET/$BACKUP_KEY" >/dev/null 2>&1; then
  log "✅ Backup verified on remote"
else
  fail "Backup not found on B2 after upload — investigate"
fi

log "═══ ✅ Backup OK ═══"
log "Key: $BACKUP_KEY"
log "Log: $LOG_FILE"
