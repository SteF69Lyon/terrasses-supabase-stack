#!/usr/bin/env bash
# scripts/backup-now.sh
# Lance un backup à la demande (utile avant une opération risquée).
# Doit être exécuté sur le VPS, sous root.

set -euo pipefail
exec bash "$(dirname "$0")/ops/backup-postgres.sh" "$@"
