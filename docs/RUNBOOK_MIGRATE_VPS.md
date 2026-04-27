# Runbook — Migrer Terrasses vers un VPS dédié

Si la mutualisation devient problématique (perfs, isolation, panne du VPS partagé), bascule vers un nouveau VPS dédié. Opération typique ~2 h.

## Pré-requis

- Nouveau VPS Hostinger commandé, accès SSH root configuré
- DNS sous ton contrôle (Hostinger panel)
- Backup récent disponible (`scripts/backup-now.sh` lancé < 1h avant)

## Procédure

### 1. Préparer le nouveau VPS

```bash
ssh root@<NEW_IP>
# Installer Docker + rclone + gpg + git (cf. setup-vps-hardening.sh d'iremia si besoin)
mkdir -p /opt/terrasses-supabase
cd /opt/terrasses-supabase
git clone https://github.com/SteF69Lyon/terrasses-supabase-stack.git .
git clone --depth 1 https://github.com/supabase/supabase.git
cp docker/supabase/docker-compose.override.yml supabase/docker/
cp docker/supabase/.env.example supabase/docker/.env
```

### 2. Restaurer les secrets exacts de l'ancien VPS

**CRITIQUE :** garder le **MÊME `JWT_SECRET`** sinon tous les tokens utilisateurs actifs deviennent invalides (logout forcé). Idem `POSTGRES_PASSWORD` (sinon il faut tout reconfigurer).

```bash
# Sur l'ancien VPS, copier le .env vers le nouveau (via scp local, pas via internet en clair)
scp /opt/terrasses-supabase/supabase/docker/.env new-vps:/opt/terrasses-supabase/supabase/docker/.env
```

### 3. Backup → restore

```bash
# Sur l'ancien VPS
sudo bash /opt/terrasses-supabase/scripts/backup-now.sh

# Sur le nouveau VPS — restore le dernier dump
LATEST=$(rclone ls scaleway:iremia-supabase-backups/postgres/terrasses/ | tail -1 | awk '{print $2}')
cd /opt/terrasses-supabase/supabase/docker
docker compose --project-name terrasses up -d db
sleep 10
rclone cat "scaleway:iremia-supabase-backups/postgres/terrasses/$LATEST" \
  | gpg --decrypt \
  | docker exec -i terrasses-supabase-db pg_restore -U supabase_admin -d postgres --clean --if-exists
docker compose --project-name terrasses up -d
```

### 4. Bascule DNS

Hostinger panel → DNS terrasse-au-soleil.fr → A record `api` → `<NEW_IP>`. TTL avait été mis à 300 → propagation < 10 min.

### 5. Vérifier

```bash
# Depuis ta machine locale
curl -s https://api.terrasse-au-soleil.fr/rest/v1/ -H "apikey: $ANON_KEY" | jq
# Doit retourner le swagger OpenAPI Supabase
```

### 6. Décommissionner l'ancien

Après 24h d'observation sans incident :
```bash
ssh old-vps
cd /opt/terrasses-supabase/supabase/docker
docker compose --project-name terrasses down
docker volume rm terrasses_db_data
```
