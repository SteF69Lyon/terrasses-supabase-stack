-- ============================================================================
-- 002_rls.sql — Row-Level Security pour terrasses-supabase-stack
--
-- Modèle d'accès :
--   profiles  : SELECT/UPDATE/INSERT par soi-même, DELETE par admin uniquement
--   ads       : SELECT public, écritures admin uniquement
--   osm_cache : service_role only (jamais exposé au client)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;

drop policy if exists profiles_select_self on public.profiles;
create policy profiles_select_self
  on public.profiles for select
  using ( auth.uid() = id );

drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self
  on public.profiles for insert
  with check ( auth.uid() = id );

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self
  on public.profiles for update
  using ( auth.uid() = id )
  with check ( auth.uid() = id );

drop policy if exists profiles_delete_admin on public.profiles;
create policy profiles_delete_admin
  on public.profiles for delete
  using ( public.is_admin() );

-- ---------------------------------------------------------------------------
-- ads
-- ---------------------------------------------------------------------------
alter table public.ads enable row level security;

drop policy if exists ads_select_public on public.ads;
create policy ads_select_public
  on public.ads for select
  using ( true );  -- lecture publique (anon + auth)

drop policy if exists ads_insert_admin on public.ads;
create policy ads_insert_admin
  on public.ads for insert
  with check ( public.is_admin() );

drop policy if exists ads_update_admin on public.ads;
create policy ads_update_admin
  on public.ads for update
  using ( public.is_admin() );

drop policy if exists ads_delete_admin on public.ads;
create policy ads_delete_admin
  on public.ads for delete
  using ( public.is_admin() );

-- ---------------------------------------------------------------------------
-- osm_cache : RLS activée mais aucune policy pour anon/authenticated
-- → seul service_role (qui bypass RLS par défaut) peut accéder
-- ---------------------------------------------------------------------------
alter table public.osm_cache enable row level security;
-- (aucune policy : verrouillé)
