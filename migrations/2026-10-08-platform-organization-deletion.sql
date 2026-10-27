-- Permanently delete an organization and its organization-owned operational data.
create or replace function public.delete_fleetops_platform_organization(
    p_organization_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
    if not public.is_fleetops_platform_owner() then
        raise exception 'No tienes permiso para administrar FleetOps.';
    end if;

    if p_organization_id is null then
        raise exception 'Debes indicar la organización que deseas eliminar.';
    end if;

    perform 1
    from public.organizations
    where id = p_organization_id
    for update;

    if not found then
        raise exception 'La organización seleccionada ya no existe.';
    end if;

    delete from public.reportes report
    using public.viajes trip
    where report.viaje_id = trip.id
      and (
          trip.empresa_id = p_organization_id
          or trip.route_id in (
              select route.id
              from public.routes route
              where route.organization_id = p_organization_id
          )
      );

    delete from public.viajes trip
    where trip.empresa_id = p_organization_id
       or trip.route_id in (
           select route.id
           from public.routes route
           where route.organization_id = p_organization_id
       );

    delete from public.organizations
    where id = p_organization_id;
end;
$$;

revoke all on function public.delete_fleetops_platform_organization(uuid) from public;
grant execute on function public.delete_fleetops_platform_organization(uuid) to authenticated;
