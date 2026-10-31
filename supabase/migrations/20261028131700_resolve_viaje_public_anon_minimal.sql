-- resolve_viaje_public: sin sesión no expone conductor, patente ni IDs.
-- Antes: cualquiera con el UUID del viaje (QR) obtenía conductor, conductor_id,
-- patente, empresa, empresa_id, ruta y route_id, sin expiración.
-- Ahora, sin sesión (auth.uid() null):
--   * solo viajes activos (fecha_finalizacion is null): el UUID deja de
--     resolver al cerrar el viaje, igual que submit_driver_report, que ya
--     rechaza viajes finalizados;
--   * patente, conductor, conductor_id, empresa_id y route_id van en null.
--     Se mantienen id, empresa, ruta, estado y fechas: reportes.html (js/app.js
--     getTripById) usa empresa/ruta para rellenar el formulario e id para
--     submit_driver_report. La patente la escribe el conductor y el servidor
--     la valida.
-- Con sesión: sin cambios (miembro de la org o cliente con acceso al viaje;
-- un autenticado sin org sigue sin recibir filas).
-- Misma firma y tipo de retorno: create or replace, los grants se conservan.
-- No hay token de QR con expiración: requeriría tabla y RPC nuevas (fuera de alcance).
begin;

create or replace function public.resolve_viaje_public(p_viaje_id uuid)
returns table(id uuid, patente text, conductor text, conductor_id uuid, empresa text, empresa_id uuid, ruta text, route_id uuid, estado text, fecha_inicio timestamp with time zone, fecha_finalizacion timestamp with time zone, created_at timestamp with time zone)
language sql
stable
security definer
set search_path to ''
as $function$
    select
        v.id,
        case when s.uid is null then null else v.patente end,
        case when s.uid is null then null else v.conductor end,
        case when s.uid is null then null else v.conductor_id end,
        v.empresa,
        case when s.uid is null then null else coalesce(v.empresa_id, r.organization_id) end,
        v.ruta,
        case when s.uid is null then null else v.route_id end,
        v.estado,
        v.fecha_inicio,
        v.fecha_finalizacion,
        v.created_at
    from (select auth.uid() as uid) s
    cross join public.viajes v
    left join public.routes r on r.id = v.route_id
    where v.id = p_viaje_id
      and (
          (s.uid is null and v.fecha_finalizacion is null)
          or public.user_has_org_role(
              coalesce(v.empresa_id, r.organization_id),
              array['owner', 'admin', 'operator', 'viewer']
          )
          or public.customer_has_trip_access(v.id, s.uid)
      )
    limit 1;
$function$;

revoke all on function public.resolve_viaje_public(uuid) from public;
grant execute on function public.resolve_viaje_public(uuid) to anon, authenticated, service_role;

commit;
