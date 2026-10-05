-- Corrige la ambigüedad entre parámetros OUT y columnas en la RPC de onboarding.
create or replace function public.consume_organization_driver_invite(
    p_token text,
    p_nombre text,
    p_rut text,
    p_telefono text,
    p_ciudad text default null,
    p_tipo_licencia text default null,
    p_patente_habitual text default null
)
returns table (
    conductor_id uuid,
    organization_id uuid,
    status text,
    driver_id text
)
language plpgsql
security definer
set search_path = public, extensions, pg_catalog
as $$
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
$$;

revoke all on function public.consume_organization_driver_invite(
    text, text, text, text, text, text, text
) from public;
grant execute on function public.consume_organization_driver_invite(
    text, text, text, text, text, text, text
) to anon, authenticated;
