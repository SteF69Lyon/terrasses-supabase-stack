#!/usr/bin/env bash
# scripts/deploy-functions.sh
#
# Pull dernière version des Edge Functions et restart le conteneur edge-runtime.
# À lancer sur le VPS dans /opt/terrasses-supabase/.
#
# Le code des functions est monté en volume (read-only) depuis ce repo,
# donc un git pull + restart suffit — pas de build, pas de push image.

set -euo pipefail
cd "$(dirname "$0")/.."

echo "→ git pull"
git pull --ff-only

echo "→ restart functions container"
cd supabase/docker
docker compose --project-name terrasses restart functions

echo "→ recent logs (last 20 lines)"
docker compose --project-name terrasses logs --tail=20 functions

echo "✅ Edge Functions redeployed"
