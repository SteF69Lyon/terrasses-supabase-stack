# Runbook — Backups Postgres

## Backup automatique (cron)

Le job `scripts/ops/backup-postgres.sh` tourne tous les jours à 03:00 UTC sur le VPS via cron :

```cron
0 3 * * * /opt/terrasses-supabase/scripts/ops/backup-postgres.sh >> /var/log/terrasses-backup/cron.log 2>&1
```

Le backup chiffré GPG est uploadé sur le remote rclone par défaut (`scaleway:`), bucket `iremia-supabase-backups`, path `postgres/terrasses/<host>-<timestamp>.dump.gpg`.

## Backup manuel (avant opération risquée)

```bash
# Sur le VPS
sudo bash /opt/terrasses-supabase/scripts/backup-now.sh
```

## Restore

```bash
# 1. Lister les backups disponibles
rclone ls scaleway:iremia-supabase-backups/postgres/terrasses/ | tail -10

# 2. Télécharger + déchiffrer le dump souhaité
rclone cat scaleway:iremia-supabase-backups/postgres/terrasses/<host>-<timestamp>.dump.gpg \
  | gpg --decrypt > /tmp/terrasses-restore.dump

# 3. (Optionnel — DESTRUCTIF) Stopper la stack avant restore
cd /opt/terrasses-supabase/supabase/docker
docker compose --project-name terrasses stop

# 4. Restore
docker compose --project-name terrasses up -d db
docker exec -i terrasses-supabase-db pg_restore \
  -U supabase_admin -d postgres --clean --if-exists < /tmp/terrasses-restore.dump

# 5. Restart le reste
docker compose --project-name terrasses up -d
```

## Vérification d'intégrité

Comparer le manifest compté (uploadé à côté du dump) vs `SELECT count(*) FROM ...` post-restore :

```bash
rclone cat scaleway:iremia-supabase-backups/postgres/terrasses/<file>.dump.gpg.manifest
```

Format : `<schema>.<table>|<estimated_rows>` une ligne par table.
