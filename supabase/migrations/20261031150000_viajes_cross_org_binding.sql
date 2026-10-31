-- V1 · Un viaje solo puede referenciar empresa, ruta y conductor de una misma
-- organización, la del usuario. Antes bastaba con que empresa_id O route_id
-- fuera propio, así que la org A podía crear un viaje con el conductor o la
-- ruta de B. Ese viaje, a su vez, le daba acceso al conductor de B a través de
-- can_access_conductor.
begin;

create or replace function private.viaje_fields_in_user_org(
    p_empresa_id uuid, p_route_id uuid, p_conductor_id uuid, p_roles text[])
returns boolean language sql stable security definer
set search_path = public, pg_catalog as $$
    with o as (
        select coalesce(p_empresa_id,
                        (select r.organization_id from public.routes r where r.id = p_route_id)) as org
    )
    select coalesce(o.org is not null
        and public.user_has_org_role(o.org, p_roles)
        and (p_empresa_id is null or p_empresa_id = o.org)
        and (p_route_id is null or exists (select 1 from public.routes r
                                            where r.id = p_route_id and r.organization_id = o.org))
        and (p_conductor_id is null or exists (select 1 from public.organization_drivers od
                                                where od.conductor_id = p_conductor_id
                                                  and od.organization_id = o.org)), false)
      from o
$$;
revoke all on function private.viaje_fields_in_user_org(uuid, uuid, uuid, text[]) from public, anon;
grant execute on function private.viaje_fields_in_user_org(uuid, uuid, uuid, text[]) to authenticated, service_role;

drop policy if exists viajes_insert_org_roles on public.viajes;
create policy viajes_insert_org_roles on public.viajes as permissive for insert to authenticated
    with check (private.viaje_fields_in_user_org(empresa_id, route_id, conductor_id,
                                                 array['owner','admin','operator']));

drop policy if exists viajes_update_org_roles on public.viajes;
create policy viajes_update_org_roles on public.viajes as permissive for update to authenticated
    using ((user_has_org_role(empresa_id, array['owner','admin','operator'])
            or exists (select 1 from public.routes r
                        where r.id = viajes.route_id
                          and user_has_org_role(r.organization_id, array['owner','admin','operator']))))
    with check (private.viaje_fields_in_user_org(empresa_id, route_id, conductor_id,
                                                 array['owner','admin','operator']));

-- Se elimina la rama "tiene viajes de esa organización": un viaje ya no
-- prueba la pertenencia. Exigir que la org del viaje tenga al conductor en
-- organization_drivers equivale exactamente a la primera rama.
create or replace function private.can_access_conductor(p_conductor_id uuid, p_roles text[])
returns boolean language sql stable security definer
set search_path = public, pg_catalog as $$
    select p_conductor_id is not null and exists (
        select 1 from public.organization_drivers od
         where od.conductor_id = p_conductor_id
           and public.user_has_org_role(od.organization_id, p_roles))
$$;

commit;
