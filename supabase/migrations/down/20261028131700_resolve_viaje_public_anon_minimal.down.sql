-- Reversión de 20261028131700_resolve_viaje_public_anon_minimal.sql: restaura la definición de main.
begin;

CREATE OR REPLACE FUNCTION public.resolve_viaje_public(p_viaje_id uuid)
 RETURNS TABLE(id uuid, patente text, conductor text, conductor_id uuid, empresa text, empresa_id uuid, ruta text, route_id uuid, estado text, fecha_inicio timestamp with time zone, fecha_finalizacion timestamp with time zone, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
    select
        v.id,
        v.patente,
        v.conductor,
        v.conductor_id,
        v.empresa,
        coalesce(v.empresa_id, r.organization_id),
        v.ruta,
        v.route_id,
        v.estado,
        v.fecha_inicio,
        v.fecha_finalizacion,
        v.created_at
    from public.viajes v
    left join public.routes r on r.id = v.route_id
    where v.id = p_viaje_id
      and (
          auth.uid() is null
          or public.user_has_org_role(
              coalesce(v.empresa_id, r.organization_id),
              array['owner', 'admin', 'operator', 'viewer']
          )
          or public.customer_has_trip_access(v.id, auth.uid())
      )
    limit 1;
$function$;

revoke all on function public.resolve_viaje_public(uuid) from public;
grant execute on function public.resolve_viaje_public(uuid) to anon, authenticated, service_role;

commit;
