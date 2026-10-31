-- is_fleetops_platform_owner() del baseline compara auth.email() (claim del
-- JWT) con fleetops_platform_owners y no mira si el email está confirmado.
-- Cuerpo de migrations/2026-10-08-platform-owner-dashboard.sql: auth.users
-- del uid, con email_confirmed_at. Sin INSERT de emails.
--
-- 20261027210000 ya quitó EXECUTE de PUBLIC en los default privileges de
-- postgres. En public, anon lo seguía recibiendo. Los RPC que el JS llama
-- sin sesión tienen GRANT explícito a anon en 20261027180547, y el
-- CREATE OR REPLACE de 20261028002755 lo conserva:
--   resolve_viaje_public(uuid)
--   submit_driver_report(uuid, text, text, text, text, text, text, text,
--     double precision, double precision, double precision, text, text)
--   resolve_organization_driver_invite(text)
--   complete_organization_driver_onboarding(text, text, text, text, text,
--     text, text, date, text, jsonb, jsonb)
--   get_member_invite_context(text)
--   get_customer_member_invite_context(text)
begin;

create or replace function public.is_fleetops_platform_owner()
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
    select exists (
        select 1
        from auth.users account
        join public.fleetops_platform_owners owner
          on owner.email = lower(btrim(coalesce(account.email, '')))
        where account.id = auth.uid()
          and account.email_confirmed_at is not null
    );
$$;

revoke all on function public.is_fleetops_platform_owner() from public;
grant execute on function public.is_fleetops_platform_owner() to authenticated;

alter default privileges for role postgres in schema public
    revoke execute on functions from anon;

commit;
