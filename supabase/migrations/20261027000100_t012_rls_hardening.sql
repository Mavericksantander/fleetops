-- =====================================================================
-- T-012 · Endurecimiento RLS / RPC (S8, S9, S10, S11, 0.0c)
-- NO aplicar en producción sin aprobación explícita del fundador.
-- Todo el archivo es transaccional: si una sentencia falla, no se aplica nada.
-- =====================================================================
begin;

-- ---------------------------------------------------------------------
-- 0. Helpers de autorización en un schema NO expuesto por PostgREST
--    (no se pueden invocar como RPC desde /rest/v1).
-- ---------------------------------------------------------------------
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

-- Organización dueña de un viaje (empresa_id o la de su ruta).
create or replace function private.viaje_organization_id(p_viaje_id uuid)
returns uuid language sql stable security definer
set search_path = public, pg_catalog as $$
    select coalesce(v.empresa_id, r.organization_id)
      from public.viajes v
      left join public.routes r on r.id = v.route_id
     where v.id = p_viaje_id
$$;

create or replace function private.can_access_viaje(p_viaje_id uuid, p_roles text[])
returns boolean language sql stable security definer
set search_path = public, pg_catalog as $$
    select coalesce(public.user_has_org_role(private.viaje_organization_id(p_viaje_id), p_roles), false)
$$;

-- Un conductor es visible para una organización si está vinculado vía
-- organization_drivers (cualquier estado: PENDING se revisa en la consola)
-- o si tiene viajes de esa organización.
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

-- Un tracto es visible si su organization_id es de la org del usuario o si
-- pertenece (conductores.tracto_id) a un conductor visible. Lo segundo cubre
-- los tractos creados por complete_organization_driver_onboarding, que hoy
-- se insertan sin organization_id.
create or replace function private.can_access_tracto(p_tracto_id uuid, p_roles text[])
returns boolean language sql stable security definer
set search_path = public, pg_catalog as $$
    select p_tracto_id is not null and (
        exists (select 1 from public.tractos t
                 where t.id = p_tracto_id
                   and public.user_has_org_role(t.organization_id, p_roles))
        or exists (select 1 from public.conductores c
                    where c.tracto_id = p_tracto_id
                      and private.can_access_conductor(c.id, p_roles))
    )
$$;

revoke all on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated, service_role;

-- ---------------------------------------------------------------------
-- S8 · conductores: sin lectura anónima; lectura/edición por organización
-- ---------------------------------------------------------------------
drop policy if exists public_read_conductores on public.conductores;
create policy conductores_select_org on public.conductores
    for select to authenticated
    using (private.can_access_conductor(id, array['owner','admin','operator','viewer']));
create policy conductores_update_org on public.conductores
    for update to authenticated
    using (private.can_access_conductor(id, array['owner','admin','operator']))
    with check (private.can_access_conductor(id, array['owner','admin','operator']));
-- INSERT/DELETE de conductores: solo vía RPC SECURITY DEFINER (onboarding).

-- ---------------------------------------------------------------------
-- S9 · reportes: fuera las 3 políticas anónimas
-- S10 · reportes: fuera lectura/insert "true" de authenticated
-- (reportes_customer_visible, ya existente, cubre org + clientes)
-- ---------------------------------------------------------------------
drop policy if exists "FleetOps permitir lectura" on public.reportes;
drop policy if exists "FleetOps permitir inserciones" on public.reportes;
drop policy if exists anon_insert_reportes on public.reportes;
drop policy if exists authenticated_read_reportes on public.reportes;
drop policy if exists authenticated_insert_reportes on public.reportes;
create policy reportes_insert_org_operators on public.reportes
    for insert to authenticated
    with check (viaje_id is not null
                and private.can_access_viaje(viaje_id, array['owner','admin','operator']));

-- ---------------------------------------------------------------------
-- S10 · tractos / tracto_documentos / conductor_documentos por organización
-- ---------------------------------------------------------------------
drop policy if exists authenticated_manage_tractos on public.tractos;
drop policy if exists authenticated_read_tractos on public.tractos;
create policy tractos_select_org on public.tractos
    for select to authenticated
    using (private.can_access_tracto(id, array['owner','admin','operator','viewer']));
create policy tractos_insert_org on public.tractos
    for insert to authenticated
    with check (organization_id is not null
                and public.user_has_org_role(organization_id, array['owner','admin','operator']));
create policy tractos_update_org on public.tractos
    for update to authenticated
    using (private.can_access_tracto(id, array['owner','admin','operator']))
    with check (organization_id is null
                or public.user_has_org_role(organization_id, array['owner','admin','operator']));
create policy tractos_delete_org on public.tractos
    for delete to authenticated
    using (private.can_access_tracto(id, array['owner','admin']));

drop policy if exists authenticated_manage_tracto_documentos on public.tracto_documentos;
drop policy if exists authenticated_read_tracto_documentos on public.tracto_documentos;
create policy tracto_documentos_select_org on public.tracto_documentos
    for select to authenticated
    using (private.can_access_tracto(tracto_id, array['owner','admin','operator','viewer']));
create policy tracto_documentos_write_org on public.tracto_documentos
    for all to authenticated
    using (private.can_access_tracto(tracto_id, array['owner','admin','operator']))
    with check (private.can_access_tracto(tracto_id, array['owner','admin','operator']));

drop policy if exists authenticated_manage_conductor_documentos on public.conductor_documentos;
drop policy if exists authenticated_read_conductor_documentos on public.conductor_documentos;
create policy conductor_documentos_select_org on public.conductor_documentos
    for select to authenticated
    using (private.can_access_conductor(conductor_id, array['owner','admin','operator','viewer']));
create policy conductor_documentos_write_org on public.conductor_documentos
    for all to authenticated
    using (private.can_access_conductor(conductor_id, array['owner','admin','operator']))
    with check (private.can_access_conductor(conductor_id, array['owner','admin','operator']));

-- ---------------------------------------------------------------------
-- S1 (defensa en profundidad) · anon sin privilegios de tabla en public;
-- nadie del API con TRUNCATE/TRIGGER/REFERENCES (TRUNCATE ignora RLS).
-- ---------------------------------------------------------------------
revoke all on all tables in schema public from anon;
revoke truncate, trigger, references on all tables in schema public from authenticated;

-- ---------------------------------------------------------------------
-- Nuevo flujo público del conductor: RPC con viaje (UUID del QR) validado.
-- Reemplaza: lectura anónima de conductores (por Driver ID/RUT/teléfono)
-- + INSERT anónimo directo en reportes.
-- ---------------------------------------------------------------------
create or replace function public.submit_driver_report(
    p_viaje_id uuid,
    p_estado text,
    p_patente text default null,
    p_driver_id text default null,
    p_rut text default null,
    p_telefono text default null,
    p_conductor text default null,
    p_incident_category text default null,
    p_latitud double precision default null,
    p_longitud double precision default null,
    p_precision_gps double precision default null,
    p_google_maps text default null,
    p_observacion text default null
)
returns table(report_id bigint, viaje_id uuid, conductor text, driver_id text)
language plpgsql security definer
set search_path = public, pg_catalog
as $$
declare
    v_trip public.viajes%rowtype;
    v_org uuid;
    v_driver record;
    v_name text;
    v_id bigint;
begin
    if p_viaje_id is null then
        raise exception 'Escanea el QR del viaje para reportar.' using errcode = '22023';
    end if;

    select * into v_trip from public.viajes v where v.id = p_viaje_id;
    v_org := private.viaje_organization_id(p_viaje_id);
    if not found or v_trip.id is null or v_org is null or v_trip.fecha_finalizacion is not null then
        raise exception 'El viaje no existe o ya fue finalizado.' using errcode = '22023';
    end if;

    if nullif(public.normalize_plate(p_patente), '') is not null
       and public.normalize_plate(p_patente) <> public.normalize_plate(v_trip.patente) then
        raise exception 'La patente no corresponde al viaje.' using errcode = '22023';
    end if;

    if length(coalesce(p_observacion, '')) > 2000 or length(coalesce(p_google_maps, '')) > 500
       or length(coalesce(p_conductor, '')) > 200 then
        raise exception 'Datos demasiado largos.' using errcode = '22001';
    end if;

    -- Identidad: solo entre conductores de la organización del viaje
    -- (vinculados ACTIVE) o el conductor asignado al viaje.
    select c.id, c.nombre, c.driver_id into v_driver
      from public.conductores c
     where (c.id = v_trip.conductor_id
            or exists (select 1 from public.organization_drivers od
                        where od.conductor_id = c.id
                          and od.organization_id = v_org
                          and od.status = 'ACTIVE'))
       and (
            (nullif(trim(p_driver_id), '') is not null and upper(c.driver_id) = upper(trim(p_driver_id)))
         or (nullif(trim(p_driver_id), '') is null and nullif(regexp_replace(coalesce(p_rut, ''), '[^0-9kK]', '', 'g'), '') is not null
             and upper(regexp_replace(coalesce(c.rut, ''), '[^0-9kK]', '', 'g')) = upper(regexp_replace(p_rut, '[^0-9kK]', '', 'g')))
         or (nullif(trim(p_driver_id), '') is null and nullif(regexp_replace(coalesce(p_telefono, ''), '[^0-9]', '', 'g'), '') is not null
             and regexp_replace(c.telefono, '[^0-9]', '', 'g') = regexp_replace(p_telefono, '[^0-9]', '', 'g'))
       )
     limit 1;

    if v_driver.id is null and nullif(trim(p_driver_id), '') is not null then
        raise exception 'El Driver ID no está registrado para esta operación.' using errcode = '22023';
    end if;

    if v_driver.id is not null and v_trip.conductor_id is not null and v_driver.id <> v_trip.conductor_id then
        raise exception 'La patente está asignada a otro conductor.' using errcode = '22023';
    end if;

    v_name := coalesce(v_driver.nombre, nullif(trim(p_conductor), ''), v_trip.conductor);
    if v_name is null then
        raise exception 'Ingresa tu Driver ID o tu nombre.' using errcode = '22023';
    end if;

    insert into public.reportes (conductor, conductor_id, patente, empresa, ruta, estado,
                                 incident_category, latitud, longitud, precision_gps,
                                 google_maps, observacion, viaje_id)
    values (v_name, coalesce(v_driver.id, v_trip.conductor_id), v_trip.patente,
            coalesce(v_trip.empresa, ''), coalesce(v_trip.ruta, ''), p_estado,
            case when p_estado = 'Incidente' then p_incident_category end,
            p_latitud, p_longitud, p_precision_gps, p_google_maps, p_observacion, p_viaje_id)
    returning id into v_id;

    return query select v_id, p_viaje_id, v_name, v_driver.driver_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 0.0c · EXECUTE: PUBLIC y anon fuera de todas las funciones de public;
-- se re-otorga a anon SOLO lo que usan las páginas públicas:
--   resolve_viaje_public            reportes.html (QR ?viaje=UUID)
--   submit_driver_report            reportes.html (nuevo, reemplaza INSERT anon)
--   resolve_organization_driver_invite, complete_organization_driver_onboarding
--                                   driver.html (?invite=token, validan hash+expiración)
--   get_member_invite_context, get_customer_member_invite_context
--                                   login.html (?invite=token, antes de iniciar sesión)
-- Nota: Postgres otorga EXECUTE a PUBLIC por defecto; revocar solo "anon"
-- no basta, por eso se revoca también PUBLIC.
-- ---------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated, service_role;

grant execute on function public.resolve_viaje_public(uuid) to anon;
grant execute on function public.submit_driver_report(uuid,text,text,text,text,text,text,text,double precision,double precision,double precision,text,text) to anon;
grant execute on function public.resolve_organization_driver_invite(text) to anon;
grant execute on function public.complete_organization_driver_onboarding(text,text,text,text,text,text,text,date,text,jsonb,jsonb) to anon;
grant execute on function public.get_member_invite_context(text) to anon;
grant execute on function public.get_customer_member_invite_context(text) to anon;

-- Funciones de trigger: nadie del API necesita invocarlas directamente.
revoke execute on function public.audit_customer_visibility_change() from authenticated;
revoke execute on function public.set_report_operational_metadata() from authenticated;
revoke execute on function public.validate_customer_operation_access() from authenticated;

-- ---------------------------------------------------------------------
-- S11 · search_path fijo + overload legacy sin autorización deshabilitado
-- finalizar_viaje(text) cerraba CUALQUIER viaje activo por patente sin
-- sesión (EXECUTE vía PUBLIC). El frontend usa finalizar_viaje(uuid).
-- Se deja sin EXECUTE para todos; su DROP queda para una migración posterior.
-- ---------------------------------------------------------------------
alter function public.normalize_plate(text) set search_path = pg_catalog;
alter function public.finalizar_viaje(text) set search_path = public, pg_catalog;
revoke execute on function public.finalizar_viaje(text) from public, anon, authenticated;

commit;
