-- Restricted FleetOps platform-owner access and first-user company onboarding.

create table if not exists public.fleetops_platform_owners (
    email text primary key,
    created_at timestamptz not null default now(),
    constraint fleetops_platform_owner_email_lowercase check (email = lower(btrim(email)))
);

insert into public.fleetops_platform_owners (email)
values ('joseto.maverick@gmail.com')
on conflict (email) do nothing;

alter table public.fleetops_platform_owners enable row level security;
revoke all on table public.fleetops_platform_owners from anon, authenticated;

create or replace function public.is_fleetops_platform_owner()
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
    select exists (
        select 1
        from auth.users account
        join public.fleetops_platform_owners owner
          on owner.email = lower(btrim(coalesce(account.email, '')))
        where account.id = auth.uid()
          and account.email_confirmed_at is not null
    );
$$;

revoke all on function public.is_fleetops_platform_owner() from public;
grant execute on function public.is_fleetops_platform_owner() to authenticated;

alter table public.organization_member_invites
    add column if not exists platform_bootstrap boolean not null default false;

alter table public.organization_member_invites
    drop constraint if exists organization_member_invites_role_check,
    add constraint organization_member_invites_role_check
        check (role in ('owner', 'admin', 'operator', 'viewer', 'customer')) not valid;

alter table public.organization_members
    drop constraint if exists organization_members_role_check,
    add constraint organization_members_role_check
        check (role in ('owner', 'admin', 'operator', 'viewer', 'customer')) not valid;

create or replace function public.create_platform_organization_invite(
    p_organization_name text,
    p_email text
)
returns table (
    organization_id uuid,
    organization_name text,
    invite_email text,
    invite_token text,
    invite_url text,
    expires_at timestamptz
)
language plpgsql
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
    v_name text := btrim(coalesce(p_organization_name, ''));
    v_email text := lower(btrim(coalesce(p_email, '')));
    v_organization_id uuid;
    v_token text;
    v_expires_at timestamptz := now() + interval '7 days';
begin
    if not public.is_fleetops_platform_owner() then
        raise exception 'No tienes permiso para administrar FleetOps.';
    end if;

    if v_name = '' or length(v_name) > 120 then
        raise exception 'Ingresa un nombre de empresa de hasta 120 caracteres.';
    end if;

    if v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
        raise exception 'Ingresa un email válido para el primer usuario.';
    end if;

    insert into public.organizations (name, owner_id)
    values (v_name, auth.uid())
    returning id into v_organization_id;

    v_token := translate(encode(gen_random_bytes(32), 'base64'), E'+/=', '-_');
    v_token := replace(v_token, E'\n', '');

    insert into public.organization_member_invites (
        organization_id,
        email,
        role,
        customer_id,
        platform_bootstrap,
        token_hash,
        expires_at,
        created_by
    )
    values (
        v_organization_id,
        v_email,
        'owner',
        null,
        true,
        encode(digest(v_token, 'sha256'), 'hex'),
        v_expires_at,
        auth.uid()
    );

    return query
    select
        v_organization_id,
        v_name,
        v_email,
        v_token,
        'login.html?invite=' || v_token,
        v_expires_at;
end;
$$;

revoke all on function public.create_platform_organization_invite(text, text) from public;
grant execute on function public.create_platform_organization_invite(text, text) to authenticated;

create or replace function public.list_fleetops_platform_organizations()
returns table (
    organization_id uuid,
    organization_name text,
    created_at timestamptz,
    first_user_email text,
    invite_status text
)
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
begin
    if not public.is_fleetops_platform_owner() then
        raise exception 'No tienes permiso para administrar FleetOps.';
    end if;

    return query
    select
        o.id,
        o.name,
        o.created_at,
        invite.email,
        case
            when invite.id is null then 'Sin invitación de plataforma'
            when invite.consumed_at is not null then 'Aceptada'
            when invite.expires_at <= now() then 'Expirada'
            else 'Pendiente'
        end
    from public.organizations o
    left join lateral (
        select i.id, i.email, i.consumed_at, i.expires_at
        from public.organization_member_invites i
        where i.organization_id = o.id
          and i.platform_bootstrap
        order by i.created_at desc
        limit 1
    ) invite on true
    order by o.created_at desc;
end;
$$;

revoke all on function public.list_fleetops_platform_organizations() from public;
grant execute on function public.list_fleetops_platform_organizations() to authenticated;

create or replace function public.accept_member_invite(p_token text)
returns table (
    organization_id uuid,
    role text
)
language plpgsql
security definer
set search_path = public, extensions, pg_catalog
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

    if v_invite.platform_bootstrap then
        if v_invite.role <> 'owner'
           or v_invite.customer_id is not null
           or not exists (
                select 1
                from public.organizations o
                where o.id = v_invite.organization_id
                  and o.owner_id = v_invite.created_by
           ) then
            raise exception 'La invitación de primer acceso no es válida.';
        end if;

        insert into public.organization_members (organization_id, user_id, role)
        values (v_invite.organization_id, v_user_id, 'owner');

        update public.organizations
           set owner_id = v_user_id
         where id = v_invite.organization_id
           and owner_id = v_invite.created_by;

        if not found then
            raise exception 'La propiedad de la organización ya fue transferida.';
        end if;
    elsif v_invite.role = 'customer' then
        if v_invite.customer_id is null then
            raise exception 'La invitación del cliente no está vinculada a un cliente válido.';
        end if;

        if not exists (
            select 1
            from public.customers c
            where c.id = v_invite.customer_id
              and c.organization_id = v_invite.organization_id
              and c.is_active
        ) then
            raise exception 'El cliente asociado a la invitación no está activo.';
        end if;

        insert into public.customer_users (organization_id, customer_id, user_id, role)
        values (v_invite.organization_id, v_invite.customer_id, v_user_id, 'customer')
        on conflict (customer_id, user_id) do nothing;

        insert into public.organization_members (organization_id, user_id, role)
        values (v_invite.organization_id, v_user_id, 'customer');
    else
        if v_invite.role not in ('admin', 'operator', 'viewer') then
            raise exception 'El rol de invitación no es válido.';
        end if;

        insert into public.organization_members (organization_id, user_id, role)
        values (v_invite.organization_id, v_user_id, v_invite.role);
    end if;

    update public.organization_member_invites
       set consumed_at = now()
     where id = v_invite.id;

    return query
    select v_invite.organization_id, v_invite.role;
end;
$$;

revoke all on function public.accept_member_invite(text) from public;
grant execute on function public.accept_member_invite(text) to authenticated;
