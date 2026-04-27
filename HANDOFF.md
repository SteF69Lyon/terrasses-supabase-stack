# terrasses-supabase-stack — HANDOFF

État du repo et de la migration. Mis à jour à chaque session.

---

## État au 2026-04-27 fin de journée

**Stack en prod sur le VPS, 13 services Up, search-terraces opérationnel mais bug `sunExposure: null` en cours de debug.**

### Ce qui marche

- Stack Supabase déployée sur VPS Hostinger 195.35.29.52, project Docker `terrasses`, accessible sur https://api.terrasse-au-soleil.fr
- 13 services Up : Postgres + GoTrue + PostgREST + Realtime + Storage + Edge Runtime + Studio + Kong + Vector + Analytics + Meta + ImgProxy + Pooler
- TLS Let's Encrypt automatique via Traefik (déjà déployé sur le VPS pour Iremia/Poolscore)
- 3 tables (`profiles`, `ads`, `osm_cache`) + RLS policies + tests RLS verts
- 2 Edge Functions :
  - `search-terraces` : OSM Overpass + AI router multi-provider (Claude → OpenAI → Gemini avec fallback) — répond en ~30-40s, ~25-30 résultats par requête sur Lyon
  - `live-token` : auth-gated, mint la clé Gemini Live API
- Cron backup quotidien 03:00 UTC vers Scaleway via rclone+GPG (pattern repris d'iremia, bucket partagé `iremia-supabase-backups` avec path `postgres/terrasses/`)
- Repo public sur https://github.com/SteF69Lyon/terrasses-supabase-stack

### Phases terminées

- ✅ Phase 0-4 — Repo bootstrap + Docker + DDL + Edge Functions + ops scripts (Tasks 1-15)
- ✅ Phase 5 — Push GitHub + bootstrap VPS (Tasks 16-19), avec corrections en cours de route :
  - Fix : retiré l'auto-mount des migrations DDL (conflictait avec les fichiers init upstream Supabase)
  - Fix : ajouté `container_name` override pour les 13 services (cohabitation avec Iremia/Poolscore)
  - Fix : retiré le port mapping de Kong (Traefik route via le réseau Docker, évite conflit `:8000`)
  - Fix : ajouté le `main` dispatcher (entrypoint requis par edge-runtime, copié d'upstream Supabase)
  - Fix : ajouté User-Agent OSM-compliant sur Overpass + Nominatim (UA Deno par défaut blacklisté → 406/429)
  - Fix : `.env` complété avec les ~30 vars manquantes via merge depuis upstream `.env.example`

### Phases en cours / à venir

- 🔄 Phase 6 — Refactor `terrasses-au-soleil/services/*` ✅ TERMINÉ (Tasks 20-25, branche `feat/supabase-migration` poussée)
- 🔄 Phase 7 — Cutover prod (Tasks 26-28) — **EN COURS**
  - Smoke test local : `npm run dev` lancé avec succès
  - **BUG en cours** : `sunExposure: null` sur tous les résultats search-terraces. Le slider de filtre soleil > 0 cache donc tout
  - Patch debug poussé (commit `fc7c1cf`) : log la réponse LLM brute + tolère id en number/string. À tester sur le VPS et lire les logs container
  - **Issue secondaire non bloquante** : WebSocket Realtime échoue (Traefik n'upgrade pas vers WS). N'affecte que le refresh ads admin
- ⏳ Phase 8 — Décommissionner Firebase (Tasks 29-30) à J+7 après stabilisation prod
- ⏳ Phase 9 — Cleanup final (Task 31) à J+30

### Pour reprendre la session sur le bug `sunExposure: null`

Sur le VPS :
```bash
ssh root@195.35.29.52
cd /opt/terrasses-supabase && git pull --ff-only
docker restart terrasses-supabase-functions
sleep 3

ANON=$(grep ^ANON_KEY= /opt/terrasses-supabase/upstream-supabase/docker/.env | cut -d= -f2-)
curl -s -X POST "https://api.terrasse-au-soleil.fr/functions/v1/search-terraces" \
  -H "apikey: $ANON" -H "Authorization: Bearer $ANON" \
  -H "Content-Type: application/json" \
  -d '{"location":"Lyon","type":"bar","date":"2026-04-30","time":"18:00"}' \
  | python3 -c "import sys, json; d=json.load(sys.stdin); print(f'{len(d[\"results\"])} results'); print(json.dumps([{k: r[k] for k in (\"name\",\"sunExposure\",\"description\")} for r in d['results'][:3]], indent=2, ensure_ascii=False))"

echo "=== Logs ==="
docker logs --tail=30 terrasses-supabase-functions 2>&1 | grep -i "search-terraces"
```

Coller les sorties à Claude. Selon ce qu'on voit dans les logs (LLM raw response + count des IDs matchés), 2 cas probables :

1. **Le tolérant string/number a marché** → `sunExposure` est maintenant un nombre → tester côté front, slider doit fonctionner
2. **Le LLM hedge encore avec `null`** → patcher le prompt pour forcer une estimation chiffrée même approximative (ex: ajouter "Tu DOIS toujours fournir un nombre, même si c'est une estimation grossière. Ne renvoie jamais null sauf si la donnée OSM est vraiment trop pauvre.")
3. **Le LLM ne renvoie pas tous les IDs** (truncation à `maxTokens: 2000`) → augmenter `maxTokens`, ou découper le batch en plusieurs requêtes plus petites

### URLs et accès

- Repo GitHub : https://github.com/SteF69Lyon/terrasses-supabase-stack
- Repo applicatif (en migration) : https://github.com/SteF69Lyon/Terrasses-au-soleil/tree/feat/supabase-migration
- VPS : `ssh root@195.35.29.52`
- API publique : https://api.terrasse-au-soleil.fr
- Studio (via tunnel SSH) : `ssh -L 3010:127.0.0.1:3010 root@195.35.29.52` puis `http://127.0.0.1:3010`
- Stack VPS path : `/opt/terrasses-supabase/` (notre repo) + `/opt/terrasses-supabase/upstream-supabase/docker/` (compose + `.env`)
