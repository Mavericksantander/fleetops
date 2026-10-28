-- Un RUT o patente ya vinculado a otra organización no se reutiliza en una
-- invitación: antes la invitación de A tomaba el conductor de B, lo vinculaba
-- a A y A leía sus documentos (can_access_conductor no distingue la org de
-- origen). En complete_*, cada storage_path debe estar bajo
-- onboarding/<token_hash de esta invitación>/.
-- Cuerpos = pg_get_functiondef de prod + guardas.
begin;

CREATE OR REPLACE FUNCTION public.complete_organization_driver_onboarding(p_token text, p_nombre text, p_rut text, p_telefono text, p_ciudad text, p_tipo_licencia text, p_licencia text, p_licencia_vencimiento date, p_patente text, p_conductor_documents jsonb DEFAULT '[]'::jsonb, p_tracto_documents jsonb DEFAULT '[]'::jsonb)
 RETURNS TABLE(conductor_id uuid, driver_id text, organization_id uuid, status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_catalog'
AS $function$
declare
    v_invite public.organization_driver_invites%rowtype;
    v_conductor public.conductores%rowtype;
    v_tracto public.tractos%rowtype;
    v_token_hash text;
    v_document jsonb;
begin
    if coalesce(trim(p_token), '') = ''
       or coalesce(trim(p_nombre), '') = ''
       or coalesce(trim(p_rut), '') = ''
       or coalesce(trim(p_telefono), '') = ''
       or coalesce(trim(p_ciudad), '') = ''
       or coalesce(trim(p_tipo_licencia), '') = ''
       or coalesce(trim(p_licencia), '') = ''
       or p_licencia_vencimiento is null
       or coalesce(trim(p_patente), '') = '' then
        raise exception 'Todos los datos obligatorios del onboarding son requeridos.';
    end if;

    if jsonb_typeof(coalesce(p_conductor_documents, '[]'::jsonb)) <> 'array'
       or jsonb_typeof(coalesce(p_tracto_documents, '[]'::jsonb)) <> 'array' then
        raise exception 'El formato de documentos no es válido.';
    end if;

    v_token_hash := encode(digest(trim(p_token), 'sha256'), 'hex');

    select invite_row.*
      into v_invite
      from public.organization_driver_invites as invite_row
     where invite_row.token_hash = v_token_hash
     for update;

    if not found then
        raise exception 'La invitación no existe o no es válida.';
    end if;

    if v_invite.consumed_at is not null then
        raise exception 'La invitación ya fue utilizada.';
    end if;

    if v_invite.expires_at <= now() then
        raise exception 'La invitación ha expirado.';
    end if;

    select conductor_row.*
      into v_conductor
      from public.conductores as conductor_row
     where conductor_row.rut = trim(p_rut)
     limit 1
     for update;

    if found and exists (
        select 1 from public.organization_drivers od
         where od.conductor_id = v_conductor.id
           and od.organization_id <> v_invite.organization_id
    ) then
        raise exception 'El RUT ya está registrado con otra empresa.'
            using errcode = '42501';
    end if;

    if found then
        update public.conductores as conductor_target
           set nombre = trim(p_nombre),
               telefono = trim(p_telefono),
               ciudad = trim(p_ciudad),
               tipo_licencia = trim(p_tipo_licencia),
               licencia = trim(p_licencia),
               licencia_vencimiento = p_licencia_vencimiento,
               estado = 'Disponible'
         where conductor_target.id = v_conductor.id
         returning conductor_target.* into v_conductor;
    else
        insert into public.conductores (
            nombre, rut, telefono, ciudad, tipo_licencia,
            licencia, licencia_vencimiento, estado, patente_habitual
        )
        values (
            trim(p_nombre), trim(p_rut), trim(p_telefono), trim(p_ciudad),
            trim(p_tipo_licencia), trim(p_licencia), p_licencia_vencimiento,
            'Disponible', upper(trim(p_patente))
        )
        returning conductores.* into v_conductor;
    end if;

    select tracto_row.*
      into v_tracto
      from public.tractos as tracto_row
     where tracto_row.patente = upper(trim(p_patente))
     limit 1
     for update;

    if found and (
        v_tracto.organization_id is distinct from null
            and v_tracto.organization_id <> v_invite.organization_id
        or exists (
            select 1 from public.conductores c
              join public.organization_drivers od on od.conductor_id = c.id
             where c.tracto_id = v_tracto.id
               and od.organization_id <> v_invite.organization_id
        )
    ) then
        raise exception 'La patente ya está registrada con otra empresa.'
            using errcode = '42501';
    end if;

    if found then
        update public.tractos as tracto_target
           set estado = 'Disponible'
         where tracto_target.id = v_tracto.id
         returning tracto_target.* into v_tracto;
    else
        insert into public.tractos (patente, estado)
        values (upper(trim(p_patente)), 'Disponible')
        returning tractos.* into v_tracto;
    end if;

    update public.conductores as conductor_target
       set tracto_id = v_tracto.id,
           patente_habitual = upper(trim(p_patente))
     where conductor_target.id = v_conductor.id
     returning conductor_target.* into v_conductor;

    if not found then
        raise exception 'No fue posible asociar el equipo al conductor.';
    end if;

    for v_document in
        select value from jsonb_array_elements(p_conductor_documents)
    loop
        if coalesce(trim(v_document->>'tipo_documento'), '') = ''
           or coalesce(trim(v_document->>'storage_path'), '') = ''
           or split_part(v_document->>'storage_path', '/', 1) <> 'onboarding'
           or split_part(v_document->>'storage_path', '/', 2) <> v_token_hash then
            raise exception 'Metadata de documento de conductor incompleta.';
        end if;

        insert into public.conductor_documentos (
            conductor_id, tipo_documento, storage_path, nombre_archivo,
            mime_type, tamano_bytes, estado_revision
        )
        values (
            v_conductor.id,
            v_document->>'tipo_documento',
            v_document->>'storage_path',
            nullif(v_document->>'nombre_archivo', ''),
            nullif(v_document->>'mime_type', ''),
            nullif(v_document->>'tamano_bytes', '')::bigint,
            'Pendiente'
        );
    end loop;

    for v_document in
        select value from jsonb_array_elements(p_tracto_documents)
    loop
        if coalesce(trim(v_document->>'tipo_documento'), '') = ''
           or coalesce(trim(v_document->>'storage_path'), '') = ''
           or split_part(v_document->>'storage_path', '/', 1) <> 'onboarding'
           or split_part(v_document->>'storage_path', '/', 2) <> v_token_hash then
            raise exception 'Metadata de documento de equipo incompleta.';
        end if;

        insert into public.tracto_documentos (
            tracto_id, tipo_documento, storage_path, nombre_archivo,
            mime_type, tamano_bytes, estado_revision
        )
        values (
            v_tracto.id,
            v_document->>'tipo_documento',
            v_document->>'storage_path',
            nullif(v_document->>'nombre_archivo', ''),
            nullif(v_document->>'mime_type', ''),
            nullif(v_document->>'tamano_bytes', '')::bigint,
            'Pendiente'
        );
    end loop;

    insert into public.organization_drivers as driver_link (
        organization_id, conductor_id, status, invited_at, updated_at
    )
    values (
        v_invite.organization_id, v_conductor.id, 'PENDING',
        v_invite.created_at, now()
    )
    on conflict on constraint organization_drivers_pkey do update
        set updated_at = now();

    update public.organization_driver_invites as invite_target
       set consumed_at = now(),
           consumed_conductor_id = v_conductor.id
     where invite_target.id = v_invite.id
       and invite_target.consumed_at is null;

    if not found then
        raise exception 'La invitación ya fue utilizada.';
    end if;

    return query
    select v_conductor.id,
           v_conductor.driver_id,
           v_invite.organization_id,
           'PENDING'::text;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.consume_organization_driver_invite(p_token text, p_nombre text, p_rut text, p_telefono text, p_ciudad text DEFAULT NULL::text, p_tipo_licencia text DEFAULT NULL::text, p_patente_habitual text DEFAULT NULL::text)
 RETURNS TABLE(conductor_id uuid, organization_id uuid, status text, driver_id text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_catalog'
AS $function$
declare
    v_invite public.organization_driver_invites%rowtype;
    v_conductor public.conductores%rowtype;
    v_token_hash text;
begin
    if coalesce(trim(p_token), '') = ''
       or coalesce(trim(p_nombre), '') = ''
       or coalesce(trim(p_rut), '') = ''
       or coalesce(trim(p_telefono), '') = '' then
        raise exception 'Token y datos de identidad son obligatorios.';
    end if;

    v_token_hash := encode(digest(trim(p_token), 'sha256'), 'hex');

    select *
      into v_invite
      from public.organization_driver_invites as invite_row
     where invite_row.token_hash = v_token_hash
     for update;

    if not found then
        raise exception 'La invitación no existe o no es válida.';
    end if;

    if v_invite.consumed_at is not null then
        raise exception 'La invitación ya fue utilizada.';
    end if;

    if v_invite.expires_at <= now() then
        raise exception 'La invitación ha expirado.';
    end if;

    select *
      into v_conductor
      from public.conductores as conductor_row
     where conductor_row.rut = trim(p_rut)
     limit 1
     for update;

    if found and exists (
        select 1 from public.organization_drivers od
         where od.conductor_id = v_conductor.id
           and od.organization_id <> v_invite.organization_id
    ) then
        raise exception 'El RUT ya está registrado con otra empresa.'
            using errcode = '42501';
    end if;

    if found then
        update public.conductores as conductor_target
           set nombre = coalesce(nullif(trim(p_nombre), ''), conductor_target.nombre),
               telefono = coalesce(nullif(trim(p_telefono), ''), conductor_target.telefono),
               ciudad = coalesce(nullif(trim(p_ciudad), ''), conductor_target.ciudad),
               tipo_licencia = coalesce(nullif(trim(p_tipo_licencia), ''), conductor_target.tipo_licencia),
               patente_habitual = coalesce(nullif(trim(p_patente_habitual), ''), conductor_target.patente_habitual)
         where conductor_target.id = v_conductor.id
         returning * into v_conductor;
    else
        insert into public.conductores (
            nombre,
            rut,
            telefono,
            ciudad,
            tipo_licencia,
            patente_habitual
        )
        values (
            trim(p_nombre),
            trim(p_rut),
            trim(p_telefono),
            nullif(trim(p_ciudad), ''),
            nullif(trim(p_tipo_licencia), ''),
            nullif(trim(p_patente_habitual), '')
        )
        returning * into v_conductor;
    end if;

    insert into public.organization_drivers as driver_link (
        organization_id,
        conductor_id,
        status,
        invited_at,
        updated_at
    )
    values (
        v_invite.organization_id,
        v_conductor.id,
        'PENDING',
        v_invite.created_at,
        now()
    )
    on conflict on constraint organization_drivers_pkey do update
        set updated_at = now();

    update public.organization_driver_invites as invite_target
       set consumed_at = now(),
           consumed_conductor_id = v_conductor.id
     where invite_target.id = v_invite.id
       and invite_target.consumed_at is null;

    if not found then
        raise exception 'La invitación ya fue utilizada.';
    end if;

    return query
    select driver_link.conductor_id,
           driver_link.organization_id,
           driver_link.status,
           v_conductor.driver_id
      from public.organization_drivers as driver_link
     where driver_link.organization_id = v_invite.organization_id
       and driver_link.conductor_id = v_conductor.id;
end;
$function$
;

commit;
