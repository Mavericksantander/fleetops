-- submit_driver_report exige patente normalizada y un conductor resuelto.
-- Un cambio de tracto_id exige que el tracto destino tenga organization_id de la org del usuario.
-- consume_organization_driver_invite queda sin EXECUTE para el API.
-- finalizar_viaje(text) se elimina.
begin;

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

    if public.normalize_plate(p_patente) = ''
       or public.normalize_plate(p_patente) <> public.normalize_plate(v_trip.patente) then
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

    if v_driver.id is null then
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

create or replace function private.conductores_tracto_org()
returns trigger
language plpgsql
-- SECURITY INVOKER a propósito: current_user es el rol que ejecuta la
-- sentencia (anon/authenticated desde el API, bajo RLS; o el dueño de una
-- función SECURITY DEFINER como complete_organization_driver_onboarding).
set search_path = public, pg_catalog
as $$
declare
    v_api boolean := current_user in ('anon', 'authenticated');
    v_org uuid;
begin
    if new.tracto_id is null then
        return new;
    end if;

    select t.organization_id into v_org from public.tractos t where t.id = new.tracto_id;
    if not found then
        raise exception 'El tracto no pertenece a la organización.' using errcode = '42501';
    end if;

    -- 1) Usuario con rol en la org del tracto.
    if v_org is not null
       and public.user_has_org_role(v_org, array['owner','admin','operator']) then
        return new;
    end if;

    -- 2) Ruta interna SECURITY DEFINER (alta por invitación), nunca desde el API:
    --    el tracto es de una org del propio conductor, o no tiene org y no está
    --    asignado a un conductor vinculado a una org ajena a este conductor.
    if not v_api and (
        (v_org is not null and exists (
            select 1 from public.organization_drivers od
             where od.conductor_id = new.id
               and od.organization_id = v_org
               and od.status in ('PENDING','ACTIVE')))
        or
        (v_org is null and not exists (
            select 1 from public.conductores c2
              join public.organization_drivers od2 on od2.conductor_id = c2.id
             where c2.tracto_id = new.tracto_id
               and c2.id <> new.id
               and od2.organization_id not in (
                   select od3.organization_id from public.organization_drivers od3
                    where od3.conductor_id = new.id)))
    ) then
        return new;
    end if;

    raise exception 'El tracto no pertenece a la organización.' using errcode = '42501';
end;
$$;

revoke all on function private.conductores_tracto_org() from public, anon, authenticated;

drop trigger if exists conductores_tracto_org on public.conductores;
create trigger conductores_tracto_org
    before update on public.conductores
    for each row
    when (old.tracto_id is distinct from new.tracto_id)
    execute function private.conductores_tracto_org();

revoke execute on function public.consume_organization_driver_invite(text, text, text, text, text, text, text)
    from public, anon, authenticated;

drop function public.finalizar_viaje(text);

commit;
