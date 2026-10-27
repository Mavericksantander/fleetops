-- SOLO PARA PRUEBAS LOCALES (Postgres "pelado", sin Supabase).
-- Emula lo mínimo de Supabase que necesitan las migraciones:
-- roles anon/authenticated/service_role, schema auth con auth.users,
-- auth.uid()/auth.email() leyendo request.jwt.claims, pgcrypto en extensions
-- y los default privileges que Supabase aplica en public.
-- NO es una migración: no se aplica en ningún proyecto Supabase.
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin noinherit bypassrls; end if;
end $$;
create schema if not exists auth;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create table if not exists auth.users (id uuid primary key, email text);
create or replace function auth.uid() returns uuid language sql stable as
$$ select nullif(nullif(current_setting('request.jwt.claims', true),'')::json->>'sub','')::uuid $$;
create or replace function auth.email() returns text language sql stable as
$$ select nullif(current_setting('request.jwt.claims', true),'')::json->>'email' $$;
grant usage on schema auth, extensions, public to anon, authenticated, service_role;
grant execute on all functions in schema auth to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
