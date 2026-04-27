# terrasses-supabase-stack

Infra et tooling de la migration Firebase → Supabase self-hosted pour
[Terrasses-au-soleil](https://github.com/SteF69Lyon/Terrasses-au-soleil).

Le code applicatif (SPA React) reste dans le repo `Terrasses-au-soleil`.
Ce repo contient l'overlay Docker Compose, le DDL Postgres, les Edge
Functions Deno, et les scripts d'ops (backups, runbooks).

Spec : voir `docs/superpowers/specs/`
Plan : voir `docs/superpowers/plans/`

## Quick links

- Production VPS : api.terrasse-au-soleil.fr
- Frontend : https://terrasse-au-soleil.fr (auto-deploy via Hostinger)
- Pattern de référence : [iremia-supabase-stack](https://github.com/SteF69Lyon/iremia-supabase-stack)
