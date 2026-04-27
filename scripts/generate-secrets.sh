#!/usr/bin/env bash
# scripts/generate-secrets.sh
#
# Génère les 8 secrets crypto Supabase et les imprime sur stdout au format
# .env (clé=valeur). Usage typique :
#   bash scripts/generate-secrets.sh > /tmp/secrets.env
#   # puis copier-coller manuellement les 8 lignes dans le .env du VPS.
#
# Note : ANON_KEY et SERVICE_ROLE_KEY sont des JWT signés avec JWT_SECRET.
# Ce script imprime les commandes Node pour les générer (à exécuter à la main
# car nécessite npx jsonwebtoken). Ne pas les calculer ici → on garde le
# script en pure shell, exécutable n'importe où.

set -euo pipefail

echo "POSTGRES_PASSWORD=$(openssl rand -base64 33 | tr -d '/+=\n' | cut -c1-40)"
echo "JWT_SECRET=$(openssl rand -hex 32)"
echo "DASHBOARD_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=\n' | cut -c1-32)"
echo "SECRET_KEY_BASE=$(openssl rand -hex 64)"
echo "VAULT_ENC_KEY=$(openssl rand -hex 16)"
echo "PG_META_CRYPTO_KEY=$(openssl rand -hex 16)"
echo "LOGFLARE_PUBLIC_ACCESS_TOKEN=$(openssl rand -hex 32)"
echo "LOGFLARE_PRIVATE_ACCESS_TOKEN=$(openssl rand -hex 32)"
echo "S3_PROTOCOL_ACCESS_KEY_ID=$(openssl rand -hex 16)"
echo "S3_PROTOCOL_ACCESS_KEY_SECRET=$(openssl rand -hex 32)"
echo
echo "# ANON_KEY et SERVICE_ROLE_KEY : générer manuellement à partir de JWT_SECRET ci-dessus."
echo "# Sur le VPS, après avoir mis JWT_SECRET en env :"
echo "#   docker run --rm -e JWT_SECRET node:20-alpine sh -c '"
echo "#     npm i -g jsonwebtoken-cli >/dev/null 2>&1;"
echo '#     for ROLE in anon service_role; do'
echo '#       echo "${ROLE^^}_KEY=$(jwt sign --secret \"$JWT_SECRET\" --algorithm HS256 \\'
echo '#         {\"role\":\"$ROLE\",\"iss\":\"supabase\",\"iat\":'$(date +%s)',\"exp\":'$(($(date +%s) + 315360000))'})"'
echo '#     done'
echo "#   '"
