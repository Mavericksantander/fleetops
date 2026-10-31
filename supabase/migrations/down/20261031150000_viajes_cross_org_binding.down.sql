-- Reversión de 20261031150000_viajes_cross_org_binding (V1).
-- Restaura las policies de viajes y can_access_conductor del estado previo
-- (baseline + T-012) y elimina el helper. Ejecutar a mano solo si hay que revertir.
-- Advertencia: reabre el hueco V1 (empresa_id O route_id propio basta, y un viaje
-- prueba pertenencia del conductor).
begin;

drop policy if exists viajes_insert_org_roles on public.viajes;
create policy viajes_insert_org_roles on public.viajes as permissive for insert to authenticated
    with check (((empresa_id is not null) and user_has_org_role(empresa_id, array['owner','admin','operator']))
             or ((route_id is not null) and exists (select 1 from public.routes r
                   where r.id = viajes.route_id
                     and user_has_org_role(r.organization_id, array['owner','admin','operator']))));

drop policy if exists viajes_update_org_roles on public.viajes;
create policy viajes_update_org_roles on public.viajes as permissive for update to authenticated
    using ((user_has_org_role(empresa_id, array['owner','admin','operator'])
            or exists (select 1 from public.routes r
                        where r.id = viajes.route_id
                          and user_has_org_role(r.organization_id, array['owner','admin','operator']))))
    with check (((empresa_id is not null) and user_has_org_role(empresa_id, array['owner','admin','operator']))
             or ((route_id is not null) and exists (select 1 from public.routes r
                   where r.id = viajes.route_id
                     and user_has_org_role(r.organization_id, array['owner','admin','operator']))));

create or replace function private.can_access_conductor(p_conductor_id uuid, p_roles text[])
returns boolean language sql stable security definer
set search_path = public, pg_catalog as $$
    select p_conductor_id is not null and (
        exists (select 1 from public.organization_drivers od
                 where od.conductor_id = p_conductor_id
                   and public.user_has_org_role(od.organization_id, p_roles))
        or exists (select 1 from public.viajes v
                     left join public.routes r on r.id = v.route_id
                    where v.conductor_id = p_conductor_id
                      and public.user_has_org_role(coalesce(v.empresa_id, r.organization_id), p_roles))
    )
$$;

drop function if exists private.viaje_fields_in_user_org(uuid, uuid, uuid, text[]);

commit;
