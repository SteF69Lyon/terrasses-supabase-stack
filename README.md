# terrasses-supabase-stack

> Infrastructure et tooling de la migration Firebase → Supabase self-hosted pour [Terrasses-au-soleil](https://github.com/SteF69Lyon/Terrasses-au-soleil).

## Contexte

Le compte Google qui héberge Firebase pour Terrasses-au-soleil est susceptible d'être bloqué (cas déjà subi sur Iremia et Poolscore). On migre toute la couche données vers Supabase self-hosted sur le VPS Hostinger pour éliminer la dépendance à Google.

Spec : [`docs/superpowers/specs/2026-04-27-migration-firebase-supabase-design.md`](docs/superpowers/specs/2026-04-27-migration-firebase-supabase-design.md)
Plan : [`docs/superpowers/plans/2026-04-27-migration-firebase-supabase.md`](docs/superpowers/plans/2026-04-27-migration-firebase-supabase.md)

## Architecture

```text
Hostinger shared (terrasse-au-soleil.fr — SPA React)
      │ HTTPS @supabase/supabase-js
      ▼
VPS Hostinger (mutualisé Iremia + Poolscore + Terrasses)
      │ Traefik (cert TLS Let's Encrypt automatique)
      ▼
Docker Compose --project-name terrasses
  ├─ Postgres 15 (volume terrasses_db_data, port 127.0.0.1:5434)
  ├─ GoTrue (Auth)
  ├─ PostgREST (REST API)
  ├─ Realtime (WebSocket — table ads)
  ├─ Storage (provisionné, pas utilisé V1)
  ├─ Edge Runtime Deno (search-terraces, live-token)
  ├─ Studio (admin UI via tunnel SSH)
  └─ Kong (API gateway → exposé via Traefik sur api.terrasse-au-soleil.fr)
```

## Repo layout

```
docker/supabase/        Overlay Docker Compose (étend l'upstream Supabase)
db/migrations/          DDL Postgres versionné (001..003)
db/tests/               Tests RLS smoke
supabase/functions/     Edge Functions Deno (multi-provider AI router + use cases)
scripts/                generate-secrets, deploy-functions, backup-now
scripts/ops/            backup-postgres (cron) — adapté d'iremia-supabase-stack
docs/                   Runbooks + spec/plan
```

## Quick links

- Production : https://api.terrasse-au-soleil.fr
- Frontend : https://terrasse-au-soleil.fr
- Pattern de référence (infra) : [iremia-supabase-stack](https://github.com/SteF69Lyon/iremia-supabase-stack)
- Pattern de référence (code Edge Functions) : [Poolscore](https://github.com/SteF69Lyon/Poolscore)

## Sécurité

⚠️ **Ne jamais committer** :
- `.env` (utiliser `.env.example` comme template)
- Clés privées (`*.key`, `*.pem`)
- Volumes Docker (`docker/volumes/`)

Le `.gitignore` couvre ces patterns mais vérifier `git status` avant chaque commit.
