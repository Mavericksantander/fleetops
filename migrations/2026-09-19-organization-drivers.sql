-- FleetOps: relación segura organización-conductor.
-- No añade organization_id a public.conductores.

create extension if not exists pgcrypto;

create table if not exists public.organization_driver_invites (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id) on delete cascade,
    token_hash text not null unique,
    expires_at timestamptz not null,
    consumed_at timestamptz,
    consumed_conductor_id uuid references public.conductores(id) on delete set null,
    created_by uuid not null references auth.users(id),
    created_at timestamptz not null default now()
);

create table if not exists public.organization_drivers (
    organization_id uuid not null references public.organizations(id) on delete cascade,
    conductor_id uuid not null references public.conductores(id) on delete cascade,
    status text not null default 'PENDING'
        check (status in ('PENDING', 'ACTIVE')),
    invited_at timestamptz not null default now(),
    approved_at timestamptz,
    approved_by uuid references auth.users(id),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (organization_id, conductor_id)
);

create index if not exists organization_driver_invites_org_idx
    on public.organization_driver_invites (organization_id, created_at desc);

create index if not exists organization_driver_invites_expiry_idx
    on public.organization_driver_invites (expires_at)
    where consumed_at is null;

create index if not exists organization_drivers_conductor_idx
    on public.organization_drivers (conductor_id);

alter table public.organization_driver_invites enable row level security;
alter table public.organization_drivers enable row level security;

revoke all on table public.organization_driver_invites from anon, authenticated;
revoke all on table public.organization_drivers from anon, authenticated;
grant select on table public.organization_driver_invites to authenticated;
grant select on table public.organization_drivers to authenticated;

drop policy if exists "organization_admins_read_driver_invites"
    on public.organization_driver_invites;
create policy "organization_admins_read_driver_invites"
on public.organization_driver_invites
for select to authenticated
using (
    public.can_manage_membership(organization_driver_invites.organization_id, auth.uid())
);

drop policy if exists "organization_members_read_drivers"
    on public.organization_drivers;
create policy "organization_members_read_drivers"
on public.organization_drivers
for select to authenticated
using (
    public.user_has_org_role(
        organization_drivers.organization_id,
        array['owner', 'admin', 'operator', 'viewer']
    )
);

create or replace function public.create_organization_driver_invite(
    p_organization_id uuid
)
returns table (
    invite_id uuid,
    invite_token text,
    expires_at timestamptz
)
language plpgsql
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
    v_token text;
    v_invite_id uuid;
    v_expires_at timestamptz;
begin
    if auth.uid() is null
       or not public.can_manage_membership(p_organization_id, auth.uid()) then
        raise exception 'No tienes permisos para invitar conductores.';
    end if;

    v_token := encode(gen_random_bytes(32), 'hex');
    v_expires_at := now() + interval '24 hours';

    insert into public.organization_driver_invites (
        organization_id,
        token_hash,
        expires_at,
        created_by
    )
    values (
        p_organization_id,
        encode(digest(v_token, 'sha256'), 'hex'),
        v_expires_at,
        auth.uid()
    )
    returning id into v_invite_id;

    return query
    select v_invite_id, v_token, v_expires_at;
end;
$$;

revoke all on function public.create_organization_driver_invite(uuid) from public;
grant execute on function public.create_organization_driver_invite(uuid) to authenticated;

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
    select od.conductor_id, od.organization_id, od.status, v_conductor.driver_id
      from public.organization_drivers od
     where od.organization_id = v_invite.organization_id
       and od.conductor_id = v_conductor.id;
end;
$$;

revoke all on function public.consume_organization_driver_invite(
    text, text, text, text, text, text, text
) from public;
grant execute on function public.consume_organization_driver_invite(
    text, text, text, text, text, text, text
) to anon, authenticated;

create or replace function public.approve_organization_driver(
    p_organization_id uuid,
    p_conductor_id uuid
)
returns public.organization_drivers
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
    v_driver public.organization_drivers;
begin
    if auth.uid() is null
       or not public.can_manage_membership(p_organization_id, auth.uid()) then
        raise exception 'Solo owner/admin puede aprobar conductores.';
    end if;

    update public.organization_drivers
       set status = 'ACTIVE',
           approved_at = now(),
           approved_by = auth.uid(),
           updated_at = now()
     where organization_id = p_organization_id
       and conductor_id = p_conductor_id
       and status = 'PENDING'
     returning * into v_driver;

    if not found then
        raise exception 'No existe una relación PENDING para aprobar.';
    end if;

    return v_driver;
end;
$$;

revoke all on function public.approve_organization_driver(uuid, uuid) from public;
grant execute on function public.approve_organization_driver(uuid, uuid) to authenticated;

-- Backfill seguro: los viajes son la única inferencia inequívoca disponible.
insert into public.organization_drivers (
    organization_id,
    conductor_id,
    status,
    invited_at,
    approved_at,
    approved_by,
    created_at,
    updated_at
)
select distinct
    v.empresa_id,
    v.conductor_id,
    'ACTIVE',
    coalesce(v.created_at, now()),
    coalesce(v.created_at, now()),
    o.owner_id,
    coalesce(v.created_at, now()),
    now()
from public.viajes v
join public.organizations o on o.id = v.empresa_id
join public.conductores c on c.id = v.conductor_id
where v.empresa_id is not null
  and v.conductor_id is not null
on conflict (organization_id, conductor_id) do nothing;
