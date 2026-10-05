-- Invitaciones seguras para colaboradores. Los conductores permanecen en organization_drivers.

create extension if not exists pgcrypto;

create table if not exists public.organization_member_invites (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id) on delete cascade,
    email text not null,
    role text not null check (role in ('admin', 'operator', 'viewer')),
    token_hash text not null unique,
    expires_at timestamptz not null,
    consumed_at timestamptz null,
    created_by uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now()
);

create index if not exists organization_member_invites_lookup_idx
    on public.organization_member_invites (token_hash);

alter table public.organization_member_invites enable row level security;

drop policy if exists "organization_admins_read_member_invites"
    on public.organization_member_invites;
create policy "organization_admins_read_member_invites"
on public.organization_member_invites for select to authenticated
using (public.can_read_membership(organization_id, auth.uid()));

create or replace function public.create_member_invite(
    p_email text,
    p_role text
)
returns table (
    invite_id uuid,
    organization_id uuid,
    organization_name text,
    role text,
    invite_token text,
    invite_url text
)
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
    v_user_id uuid := auth.uid();
    v_email text := lower(btrim(coalesce(p_email, '')));
    v_role text := lower(btrim(coalesce(p_role, '')));
    v_organization_id uuid;
    v_organization_name text;
    v_invite_id uuid;
    v_token text;
    v_expires_at timestamptz := now() + interval '7 days';
begin
    if v_user_id is null then
        raise exception 'Debes iniciar sesión para invitar colaboradores.';
    end if;

    if v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
        raise exception 'Ingresa un email válido.';
    end if;

    if v_role not in ('admin', 'operator', 'viewer') then
        raise exception 'El rol debe ser admin, operator o viewer.';
    end if;

    select o.id, o.name
      into v_organization_id, v_organization_name
      from public.organizations o
     where o.owner_id = v_user_id
        or exists (
            select 1
              from public.organization_members om
             where om.organization_id = o.id
               and om.user_id = v_user_id
               and om.role = 'admin'
        )
     order by (o.owner_id = v_user_id) desc, o.created_at
     limit 1;

    if v_organization_id is null then
        raise exception 'No tienes permisos para invitar colaboradores.';
    end if;

    v_token := translate(encode(gen_random_bytes(32), 'base64'), E'+/=', '-_');
    v_token := replace(v_token, E'\n', '');

    insert into public.organization_member_invites (
        organization_id, email, role, token_hash, expires_at, created_by
    )
    values (
        v_organization_id,
        v_email,
        v_role,
        encode(digest(v_token, 'sha256'), 'hex'),
        v_expires_at,
        v_user_id
    )
    returning id into v_invite_id;

    return query
    select
        v_invite_id,
        v_organization_id,
        v_organization_name,
        v_role,
        v_token,
        'login.html?invite=' || v_token;
end;
$$;

revoke all on function public.create_member_invite(text, text) from public;
grant execute on function public.create_member_invite(text, text) to authenticated;

create or replace function public.get_member_invite_context(
    p_token text
)
returns table (
    organization_name text,
    role text,
    invite_status text
)
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
    v_invite public.organization_member_invites;
begin
    select *
      into v_invite
      from public.organization_member_invites
     where token_hash = encode(digest(btrim(coalesce(p_token, '')), 'sha256'), 'hex')
     limit 1;

    if not found then
        raise exception 'La invitación no existe.';
    end if;

    return query
    select
        o.name,
        v_invite.role,
        case
            when v_invite.consumed_at is not null then 'used'
            when v_invite.expires_at <= now() then 'expired'
            else 'pending'
        end
    from public.organizations o
    where o.id = v_invite.organization_id;
end;
$$;

revoke all on function public.get_member_invite_context(text) from public;
grant execute on function public.get_member_invite_context(text) to anon, authenticated;

create or replace function public.accept_member_invite(
    p_token text
)
returns table (
    organization_id uuid,
    role text
)
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
    v_user_id uuid := auth.uid();
    v_email text := lower(btrim(coalesce(auth.email(), '')));
    v_invite public.organization_member_invites;
begin
    if v_user_id is null then
        raise exception 'Debes iniciar sesión para aceptar la invitación.';
    end if;

    select *
      into v_invite
      from public.organization_member_invites
     where token_hash = encode(digest(btrim(coalesce(p_token, '')), 'sha256'), 'hex')
     for update;

    if not found then
        raise exception 'La invitación no existe.';
    end if;

    if v_invite.consumed_at is not null then
        raise exception 'Esta invitación ya fue utilizada.';
    end if;

    if v_invite.expires_at <= now() then
        raise exception 'Esta invitación expiró.';
    end if;

    if v_email = '' or lower(v_invite.email) <> v_email then
        raise exception 'El email autenticado no coincide con el email invitado.';
    end if;

    if exists (
        select 1
          from public.organization_members om
         where om.organization_id = v_invite.organization_id
           and om.user_id = v_user_id
    ) then
        raise exception 'Tu usuario ya pertenece a esta organización.';
    end if;

    insert into public.organization_members (organization_id, user_id, role)
    values (v_invite.organization_id, v_user_id, v_invite.role);

    update public.organization_member_invites
       set consumed_at = now()
     where id = v_invite.id;

    return query
    select v_invite.organization_id, v_invite.role;
end;
$$;

revoke all on function public.accept_member_invite(text) from public;
grant execute on function public.accept_member_invite(text) to authenticated;

-- La lectura se resuelve en backend para poder mostrar email/nombre sin exponer auth.users.
create or replace function public.list_current_user_organization_team()
returns table (
    organization_id uuid,
    organization_name text,
    member_id uuid,
    email text,
    display_name text,
    role text,
    status text,
    created_at timestamptz
)
language sql
security definer
set search_path = public, pg_catalog
as $$
    select
        o.id,
        o.name,
        u.id,
        lower(u.email),
        coalesce(
            nullif(u.raw_user_meta_data ->> 'full_name', ''),
            nullif(u.raw_user_meta_data ->> 'name', ''),
            lower(u.email)
        ),
        om.role,
        'active',
        om.created_at
    from public.organizations o
    join public.organization_members om on om.organization_id = o.id
    join auth.users u on u.id = om.user_id
    where o.owner_id = auth.uid()
       or exists (
           select 1
           from public.organization_members viewer
           where viewer.organization_id = o.id
             and viewer.user_id = auth.uid()
             and viewer.role in ('owner', 'admin')
       )
    union all
    select
        o.id,
        o.name,
        null,
        i.email,
        i.email,
        i.role,
        case
            when i.consumed_at is not null then 'active'
            when i.expires_at <= now() then 'expired'
            else 'pending'
        end,
        i.created_at
    from public.organization_member_invites i
    join public.organizations o on o.id = i.organization_id
    where i.consumed_at is null
      and i.expires_at > now()
      and (o.owner_id = auth.uid()
        or exists (
            select 1
            from public.organization_members viewer
            where viewer.organization_id = o.id
              and viewer.user_id = auth.uid()
              and viewer.role in ('owner', 'admin')
        ));
$$;

revoke all on function public.list_current_user_organization_team() from public;
grant execute on function public.list_current_user_organization_team() to authenticated;
