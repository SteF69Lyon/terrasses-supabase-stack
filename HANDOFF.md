# terrasses-supabase-stack — HANDOFF

État du repo et de la migration. Mis à jour à chaque session.

---

## État au commit initial

Repo créé conformément au plan d'implémentation [`docs/superpowers/plans/2026-04-27-migration-firebase-supabase.md`](docs/superpowers/plans/2026-04-27-migration-firebase-supabase.md).

Phases terminées dans ce repo :
- Phase 0 — Bootstrap repo
- Phase 1 — Docker overlay + .env.example + scripts/generate-secrets.sh + scripts/deploy-functions.sh
- Phase 2 — Migrations DDL 001..003 + tests RLS
- Phase 3 — Edge Functions (ai-router, search-terraces, live-token)
- Phase 4 — Scripts ops (backup) + runbooks + README

À faire :
- Phase 5 — Push GitHub + bootstrap VPS (Tasks 16-19) — **manuel SSH**
- Phase 6 — Refactor `terrasses-au-soleil/services/*` (Tasks 20-25) — **dans l'autre repo**
- Phase 7 — Cutover prod (Tasks 26-28)
- Phase 8 — Décommissionner Firebase (Tasks 29-30) à J+7
- Phase 9 — Cleanup final (Task 31) à J+30
