# db/tests

Tests SQL exécutés manuellement contre l'instance Postgres du VPS via tunnel SSH.

## rls_smoke.sql

Vérifie que les policies RLS bloquent bien l'accès anon aux tables sensibles.

### Lancer depuis ta machine

```bash
# 1. Tunnel SSH (laisse-le ouvert dans un terminal)
ssh -L 5434:127.0.0.1:5434 root@<IP_VPS>

# 2. Dans un autre terminal local
PGPASSWORD=<POSTGRES_PASSWORD> psql \
  -h 127.0.0.1 -p 5434 -U postgres -d postgres \
  -f db/tests/rls_smoke.sql
```

Sortie attendue : `✓ ALL RLS TESTS PASSED`. Si un test fail, le script s'arrête avec `❌ FAIL: ...`.
