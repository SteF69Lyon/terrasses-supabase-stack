-- ============================================================================
-- rls_smoke.sql — Tests d'intégration RLS
--
-- Usage local (depuis ta machine, avec un tunnel SSH ouvert sur 5434) :
--   PGPASSWORD=$POSTGRES_PASSWORD psql -h 127.0.0.1 -p 5434 -U postgres \
--     -f db/tests/rls_smoke.sql
--
-- Si tous les tests passent, le script affiche "✓ ALL RLS TESTS PASSED" à la fin.
-- En cas de fail, le script s'arrête avec un message explicite.
-- ============================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- Setup : créer un user de test et son profil
-- ---------------------------------------------------------------------------
do $$
declare
  test_uid uuid := gen_random_uuid();
begin
  -- Insert direct dans auth.users (bypass GoTrue, ok pour test SQL pur)
  insert into auth.users (id, email, encrypted_password, email_confirmed_at, role, aud)
  values (test_uid, 'test-rls@example.com', 'fake', now(), 'authenticated', 'authenticated')
  on conflict (id) do nothing;

  insert into public.profiles (id, name, email)
  values (test_uid, 'Test User', 'test-rls@example.com')
  on conflict (id) do nothing;

  perform set_config('test.uid', test_uid::text, false);
end $$;

-- ---------------------------------------------------------------------------
-- Test 1 : anon ne peut PAS lire profiles
-- ---------------------------------------------------------------------------
set role anon;
do $$
declare
  visible_count integer;
begin
  select count(*) into visible_count from public.profiles;
  if visible_count > 0 then
    raise exception '❌ FAIL: anon can see % profile(s) — should be 0', visible_count;
  end if;
  raise notice '✓ Test 1: anon cannot read profiles';
end $$;
reset role;

-- ---------------------------------------------------------------------------
-- Test 2 : anon ne peut PAS écrire dans ads
-- ---------------------------------------------------------------------------
set role anon;
do $$
begin
  begin
    insert into public.ads (text) values ('hack');
    raise exception '❌ FAIL: anon could insert into ads';
  exception when insufficient_privilege or check_violation then
    raise notice '✓ Test 2: anon cannot insert into ads';
  end;
end $$;
reset role;

-- ---------------------------------------------------------------------------
-- Test 3 : anon PEUT lire ads
-- ---------------------------------------------------------------------------
set role anon;
do $$
declare
  ok boolean;
begin
  -- on attend juste que la requête réussisse, pas qu'il y ait du contenu
  perform * from public.ads limit 1;
  raise notice '✓ Test 3: anon can read ads';
end $$;
reset role;

-- ---------------------------------------------------------------------------
-- Test 4 : anon ne peut PAS lire osm_cache
-- ---------------------------------------------------------------------------
set role anon;
do $$
declare
  visible_count integer;
begin
  select count(*) into visible_count from public.osm_cache;
  if visible_count > 0 then
    raise exception '❌ FAIL: anon can see % osm_cache row(s)', visible_count;
  end if;
  raise notice '✓ Test 4: anon cannot read osm_cache';
end $$;
reset role;

-- ---------------------------------------------------------------------------
-- Cleanup
-- ---------------------------------------------------------------------------
delete from public.profiles where email = 'test-rls@example.com';
delete from auth.users where email = 'test-rls@example.com';

\echo '✓ ALL RLS TESTS PASSED'
