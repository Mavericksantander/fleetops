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
create or replace function auth.role() returns text language sql stable as
$$ select nullif(current_setting('request.jwt.claims', true),'')::json->>'role' $$;
grant usage on schema auth, extensions, public to anon, authenticated, service_role;
grant execute on all functions in schema auth to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;

-- Metadatos mínimos de Storage (en Supabase ya existen). El bucket imita prod:
-- existe, privado, sin límite de tamaño ni de MIME. Las políticas de la app
-- NO se crean aquí; las pone la migración.
create schema if not exists storage;
revoke all on schema storage from public;
grant usage on schema storage to anon, authenticated, service_role;
create table if not exists storage.buckets (
    id text primary key,
    name text not null,
    public boolean not null default false,
    file_size_limit bigint,
    allowed_mime_types text[]
);
create table if not exists storage.objects (
    id uuid primary key default gen_random_uuid(),
    bucket_id text references storage.buckets (id),
    name text,
    owner uuid,
    metadata jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (bucket_id, name)
);
alter table storage.buckets enable row level security;
alter table storage.objects enable row level security;
grant select on storage.buckets to anon, authenticated, service_role;
grant select, insert, update, delete on storage.objects to anon, authenticated, service_role;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fleetops-documents', 'fleetops-documents', false, null, null)
on conflict (id) do nothing;

-- Mismo contrato que el helper de Supabase: 'object.delete_many' y
-- 'storage.object.delete_many' coinciden; sin GUC o con texto vacío, false.
create or replace function storage.allow_only_operation(op text)
returns boolean
language sql
stable
as $$
  select coalesce(btrim(op), '') <> ''
     and coalesce(btrim(current_setting('storage.operation', true)), '') <> ''
     and regexp_replace(btrim(op), '^storage\.', '')
         = regexp_replace(btrim(current_setting('storage.operation', true)), '^storage\.', '')
$$;
grant execute on function storage.allow_only_operation(text) to anon, authenticated, service_role;
