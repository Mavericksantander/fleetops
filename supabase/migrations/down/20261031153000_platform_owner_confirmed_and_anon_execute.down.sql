-- Reversión de 20261031153000_platform_owner_confirmed_and_anon_execute.
-- Restaura el cuerpo del baseline de is_fleetops_platform_owner() (compara
-- auth.email(), sin exigir email confirmado) y el default de EXECUTE para anon
-- en public. CREATE OR REPLACE conserva los grants vigentes.
-- Ejecutar a mano solo si hay que revertir. No inserta emails.
begin;

create or replace function public.is_fleetops_platform_owner()
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
    select auth.uid() is not null
       and lower(btrim(coalesce(auth.email(), ''))) in (
            select owner.email
            from public.fleetops_platform_owners owner
       );
$$;

alter default privileges for role postgres in schema public
    grant execute on functions to anon;

commit;
