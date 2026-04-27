-- ============================================================================
-- 001_initial_schema.sql — terrasses-supabase-stack
--
-- Crée :
--   - public.profiles (1 ligne par auth.users)
--   - public.ads (annonces internes affichées en complément d'AdSense)
--   - public.osm_cache (cache POI Overpass — TTL géré côté Edge Function)
--   - helpers : is_admin(), set_updated_at()
--   - trigger updated_at sur profiles
-- ============================================================================

set search_path = public;

-- ----------------------------------------------------------------------------
-- profiles
-- ----------------------------------------------------------------------------
create table if not exists public.profiles (
  id                   uuid primary key references auth.users(id) on delete cascade,
  name                 text not null,
  email                text not null,
  is_subscribed        boolean default false not null,
  email_notifications  boolean default false not null,
  preferred_type       text default 'all' check (preferred_type in ('bar','restaurant','cafe','hotel','all')),
  preferred_sun_level  integer default 20 check (preferred_sun_level between 0 and 100),
  favorites            text[] default '{}' not null,
  created_at           timestamptz default now() not null,
  updated_at           timestamptz default now() not null
);

create index if not exists profiles_email_idx on public.profiles(email);

-- ----------------------------------------------------------------------------
-- ads
-- ----------------------------------------------------------------------------
create table if not exists public.ads (
  id          uuid primary key default gen_random_uuid(),
  text        text not null,
  link        text,
  is_active   boolean default true not null,
  created_at  timestamptz default now() not null,
  created_by  uuid references auth.users(id) on delete set null
);

create index if not exists ads_active_created_idx on public.ads(is_active, created_at desc);

-- ----------------------------------------------------------------------------
-- osm_cache (jamais lu/écrit par anon ou authenticated → service_role only via RLS)
-- ----------------------------------------------------------------------------
create table if not exists public.osm_cache (
  location_key  text primary key,
  results       jsonb not null,
  fetched_at    timestamptz default now() not null
);

create index if not exists osm_cache_fetched_idx on public.osm_cache(fetched_at);

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------
-- is_admin() : true si l'email JWT correspond à l'allowlist
create or replace function public.is_admin() returns boolean
  language sql stable as $$
    select coalesce(auth.jwt() ->> 'email', '') = 'sflandrin@outlook.com';
  $$;

-- set_updated_at trigger fn
create or replace function public.set_updated_at() returns trigger
  language plpgsql as $$
  begin
    new.updated_at = now();
    return new;
  end;
  $$;

drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();
