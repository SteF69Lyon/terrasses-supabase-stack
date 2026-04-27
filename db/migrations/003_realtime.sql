-- ============================================================================
-- 003_realtime.sql — Activer Realtime sur ads pour le dashboard admin
-- ============================================================================

-- La publication `supabase_realtime` est créée par Supabase au boot.
-- On ajoute uniquement la table `ads` (pas les autres — pas besoin).
alter publication supabase_realtime add table public.ads;
