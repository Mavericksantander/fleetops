-- Customer Visibility / Visibilidad para clientes
-- Reutiliza el sistema de invitaciones, mantiene la separación de organizaciones y
-- restringe la visibilidad a trips autorizados mediante RLS + acceso explícito.

create extension if not exists pgcrypto;

alter table public.organization_members
    drop constraint if exists organization_members_role_check,
    add constraint organization_members_role_check
        check (role in ('owner', 'admin', 'operator', 'viewer', 'customer')) not valid;

create table if not exists public.customers (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id) on delete cascade,
    name text not null,
    contact_name text,
    email text,
    phone text,
    is_active boolean not null default true,
    created_by uuid references auth.users(id) on delete set null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint customers_name_not_blank check (length(btrim(name)) > 0)
);

alter table public.organization_member_invites
    add column if not exists customer_id uuid references public.customers(id) on delete set null;

alter table public.organization_member_invites
    drop constraint if exists organization_member_invites_role_check,
    add constraint organization_member_invites_role_check
        check (role in ('admin', 'operator', 'viewer', 'customer')) not valid;

create table if not exists public.customer_users (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id) on delete cascade,
    customer_id uuid not null references public.customers(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    role text not null default 'customer' check (role = 'customer'),
    created_at timestamptz not null default now(),
    unique (customer_id, user_id),
    unique (organization_id, user_id)
);

create table if not exists public.customer_operation_access (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id) on delete cascade,
    customer_id uuid not null references public.customers(id) on delete cascade,
    route_id uuid references public.routes(id) on delete cascade,
    trip_id uuid references public.viajes(id) on delete cascade,
    active boolean not null default true,
    created_by uuid references auth.users(id) on delete set null,
    created_at timestamptz not null default now(),
    constraint customer_access_scope check (
        (route_id is not null and trip_id is null)
        or (route_id is null and trip_id is not null)
    )
);

-- CHECK constraints cannot query other tables; validate organization ownership
-- with a trigger so route/trip grants cannot cross organization boundaries.
alter table public.customer_operation_access
    drop constraint if exists customer_access_org_matches,
    drop constraint if exists customer_access_trip_matches;

create or replace function public.validate_customer_operation_access()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
    v_customer_organization_id uuid;
    v_route_organization_id uuid;
    v_trip_organization_id uuid;
begin
    select c.organization_id
      into v_customer_organization_id
      from public.customers c
     where c.id = new.customer_id;

    if v_customer_organization_id is null
       or v_customer_organization_id <> new.organization_id then
        raise exception 'El cliente debe pertenecer a la organización indicada.';
    end if;

    if new.route_id is not null then
        select r.organization_id
          into v_route_organization_id
          from public.routes r
         where r.id = new.route_id;

        if v_route_organization_id is null
           or v_route_organization_id <> new.organization_id then
            raise exception 'La ruta debe pertenecer a la organización indicada.';
        end if;
    end if;

    if new.trip_id is not null then
        select coalesce(v.empresa_id, r.organization_id)
          into v_trip_organization_id
          from public.viajes v
          left join public.routes r on r.id = v.route_id
         where v.id = new.trip_id;

        if v_trip_organization_id is null
           or v_trip_organization_id <> new.organization_id then
            raise exception 'El viaje debe pertenecer a la organización indicada.';
        end if;
    end if;

    return new;
end;
$$;

revoke all on function public.validate_customer_operation_access() from public;

drop trigger if exists validate_customer_operation_access
    on public.customer_operation_access;
create trigger validate_customer_operation_access
before insert or update on public.customer_operation_access
for each row
execute function public.validate_customer_operation_access();

create index if not exists customers_organization_active_idx
    on public.customers (organization_id, is_active, created_at desc);

create index if not exists customer_users_lookup_idx
    on public.customer_users (organization_id, user_id, customer_id);

create index if not exists customer_operation_access_customer_idx
    on public.customer_operation_access (customer_id, active, created_at desc);

create index if not exists customer_operation_access_route_idx
    on public.customer_operation_access (route_id, active);

create index if not exists customer_operation_access_trip_idx
    on public.customer_operation_access (trip_id, active);

alter table public.customers enable row level security;
alter table public.customer_users enable row level security;
alter table public.customer_operation_access enable row level security;

create or replace function public.customer_has_trip_access(
    p_trip_id uuid,
    p_user_id uuid default auth.uid()
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
    v_match_count integer;
begin
    if p_trip_id is null or p_user_id is null then
        return false;
    end if;

    select count(*)
      into v_match_count
    from public.customer_operation_access coa
    join public.customer_users cu
      on cu.customer_id = coa.customer_id
     and cu.user_id = p_user_id
    join public.viajes v
      on v.id = p_trip_id
    where coa.active = true
      and coa.organization_id = v.empresa_id
      and (
          coa.trip_id = p_trip_id
          or (coa.route_id is not null and coa.route_id = v.route_id)
      );

    return v_match_count > 0;
end;
$$;

revoke all on function public.customer_has_trip_access(uuid, uuid) from public;
grant execute on function public.customer_has_trip_access(uuid, uuid) to authenticated;

drop policy if exists "customers_read_internal_and_own" on public.customers;
create policy "customers_read_internal_and_own"
on public.customers for select to authenticated
using (
    exists (
        select 1
        from public.organization_members om
        where om.organization_id = customers.organization_id
          and om.user_id = auth.uid()
    )
    or exists (
        select 1
        from public.customer_users cu
        where cu.customer_id = customers.id
          and cu.user_id = auth.uid()
    )
);

drop policy if exists "customers_manage_internal_only" on public.customers;
create policy "customers_manage_internal_only"
on public.customers for all to authenticated
using (
    public.user_has_org_role(customers.organization_id, array['owner', 'admin', 'operator'])
)
with check (
    public.user_has_org_role(customers.organization_id, array['owner', 'admin', 'operator'])
    and customers.organization_id is not null
);

drop policy if exists "customer_users_read_internal_and_self" on public.customer_users;
create policy "customer_users_read_internal_and_self"
on public.customer_users for select to authenticated
using (
    exists (
        select 1
        from public.organization_members om
        where om.organization_id = customer_users.organization_id
          and om.user_id = auth.uid()
    )
    or customer_users.user_id = auth.uid()
);

drop policy if exists "customer_users_manage_internal_only" on public.customer_users;
create policy "customer_users_manage_internal_only"
on public.customer_users for all to authenticated
using (
    public.user_has_org_role(customer_users.organization_id, array['owner', 'admin', 'operator'])
)
with check (
    public.user_has_org_role(customer_users.organization_id, array['owner', 'admin', 'operator'])
    and customer_users.organization_id is not null
    and customer_users.role = 'customer'
);

drop policy if exists "customer_access_read_internal_and_self" on public.customer_operation_access;
create policy "customer_access_read_internal_and_self"
on public.customer_operation_access for select to authenticated
using (
    public.user_has_org_role(customer_operation_access.organization_id, array['owner', 'admin', 'operator', 'viewer'])
    or exists (
        select 1
        from public.customer_users cu
        where cu.customer_id = customer_operation_access.customer_id
          and cu.user_id = auth.uid()
    )
);

drop policy if exists "customer_access_manage_internal_only" on public.customer_operation_access;
create policy "customer_access_manage_internal_only"
on public.customer_operation_access for all to authenticated
using (
    public.user_has_org_role(customer_operation_access.organization_id, array['owner', 'admin', 'operator'])
)
with check (
    public.user_has_org_role(customer_operation_access.organization_id, array['owner', 'admin', 'operator'])
    and customer_operation_access.organization_id is not null
    and customer_operation_access.customer_id is not null
    and (customer_operation_access.route_id is not null or customer_operation_access.trip_id is not null)
);

create or replace function public.create_customer(
    p_name text,
    p_contact_name text default null,
    p_email text default null,
    p_phone text default null
)
returns table (
    customer_id uuid,
    organization_id uuid,
    customer_name text
)
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
    v_user_id uuid := auth.uid();
    v_name text := btrim(coalesce(p_name, ''));
    v_contact_name text := btrim(coalesce(p_contact_name, ''));
    v_email text := lower(btrim(coalesce(p_email, '')));
    v_phone text := btrim(coalesce(p_phone, ''));
    v_org_id uuid;
    v_customer_id uuid;
begin
    if v_user_id is null then
        raise exception 'Debes iniciar sesión para crear un cliente.';
    end if;

    if v_name = '' then
        raise exception 'El nombre del cliente es obligatorio.';
    end if;

    if length(v_name) > 150 then
        raise exception 'El nombre del cliente no puede superar 150 caracteres.';
    end if;

    select o.id
      into v_org_id
      from public.organizations o
     where o.owner_id = v_user_id
        or exists (
            select 1
            from public.organization_members om
            where om.organization_id = o.id
              and om.user_id = v_user_id
              and om.role in ('owner', 'admin')
        )
     order by (o.owner_id = v_user_id) desc, o.created_at
     limit 1;

    if v_org_id is null then
        raise exception 'No tienes permisos para crear clientes.';
    end if;

    insert into public.customers (
        organization_id,
        name,
        contact_name,
        email,
        phone,
        created_by
    )
    values (
        v_org_id,
        v_name,
        nullif(v_contact_name, ''),
        nullif(v_email, ''),
        nullif(v_phone, ''),
        v_user_id
    )
    returning id into v_customer_id;

    return query
    select v_customer_id, v_org_id, v_name;
end;
$$;

revoke all on function public.create_customer(text, text, text, text) from public;
grant execute on function public.create_customer(text, text, text, text) to authenticated;

create or replace function public.create_member_invite(
    p_email text,
    p_role text,
    p_customer_id uuid default null
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
    v_customer_id uuid := p_customer_id;
    v_organization_id uuid;
    v_organization_name text;
    v_invite_id uuid;
    v_token text;
    v_expires_at timestamptz := now() + interval '7 days';
begin
    if v_user_id is null then
        raise exception 'Debes iniciar sesión para invitar clientes o colaboradores.';
    end if;

    if v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
        raise exception 'Ingresa un email válido.';
    end if;

    if v_role not in ('admin', 'operator', 'viewer', 'customer') then
        raise exception 'El rol debe ser admin, operator, viewer o customer.';
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
        raise exception 'No tienes permisos para invitar usuarios.';
    end if;

    if v_role = 'customer' then
        if v_customer_id is null then
            raise exception 'Debes seleccionar un cliente para invitar un usuario customer.';
        end if;

        if not exists (
            select 1
            from public.customers c
            where c.id = v_customer_id
              and c.organization_id = v_organization_id
              and c.is_active = true
        ) then
            raise exception 'El cliente seleccionado no existe o no pertenece a la organización.';
        end if;
    end if;

    v_token := translate(encode(gen_random_bytes(32), 'base64'), E'+/=', '-_');
    v_token := replace(v_token, E'\n', '');

    insert into public.organization_member_invites (
        organization_id,
        email,
        role,
        customer_id,
        token_hash,
        expires_at,
        created_by
    )
    values (
        v_organization_id,
        v_email,
        v_role,
        v_customer_id,
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

revoke all on function public.create_member_invite(text, text, uuid) from public;
grant execute on function public.create_member_invite(text, text, uuid) to authenticated;

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

    if v_invite.role = 'customer' then
        if v_invite.customer_id is null then
            raise exception 'La invitación del cliente no está vinculada a un cliente válido.';
        end if;

        if not exists (
            select 1
            from public.customers c
            where c.id = v_invite.customer_id
              and c.organization_id = v_invite.organization_id
              and c.is_active = true
        ) then
            raise exception 'El cliente asociado a la invitación no está activo.';
        end if;

        insert into public.customer_users (organization_id, customer_id, user_id, role)
        values (v_invite.organization_id, v_invite.customer_id, v_user_id, 'customer')
        on conflict (customer_id, user_id) do nothing;
    end if;

    insert into public.organization_members (organization_id, user_id, role)
    values (v_invite.organization_id, v_user_id, v_invite.role)
    on conflict (organization_id, user_id) do nothing;

    update public.organization_member_invites
       set consumed_at = now()
     where id = v_invite.id;

    return query
    select v_invite.organization_id, v_invite.role;
end;
$$;

revoke all on function public.accept_member_invite(text) from public;
grant execute on function public.accept_member_invite(text) to authenticated;

create or replace function public.get_customer_visible_operations(
    p_user_id uuid default auth.uid()
)
returns table (
    trip_id uuid,
    customer_id uuid,
    customer_name text,
    route_id uuid,
    route_name text,
    trip_status text,
    route_label text,
    patente text,
    conductor text,
    fecha_inicio timestamptz,
    last_report_at timestamptz,
    last_report_state text,
    last_report_observacion text,
    incident_count bigint
)
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
    select distinct
        v.id as trip_id,
        c.id as customer_id,
        c.name as customer_name,
        coalesce(v.route_id, coa.route_id) as route_id,
        r.name as route_name,
        v.estado as trip_status,
        v.ruta as route_label,
        v.patente,
        v.conductor,
        v.fecha_inicio,
        last_report."timestamp" as last_report_at,
        last_report.estado as last_report_state,
        last_report.observacion as last_report_observacion,
        (
            select count(*)
            from public.reportes rp
            where rp.viaje_id = v.id
              and rp.estado = 'Incidente'
        ) as incident_count
    from public.customer_operation_access coa
    join public.customer_users cu
      on cu.customer_id = coa.customer_id
     and cu.user_id = p_user_id
    join public.customers c
      on c.id = cu.customer_id
     and c.organization_id = coa.organization_id
    left join public.viajes v
      on (
            coa.trip_id is not null and coa.trip_id = v.id
        )
      or (
            coa.route_id is not null and coa.route_id = v.route_id
        )
    left join public.routes r on r.id = coalesce(v.route_id, coa.route_id)
    left join lateral (
        select rep."timestamp", rep.estado, rep.observacion
        from public.reportes rep
        where rep.viaje_id = v.id
        order by rep."timestamp" desc
        limit 1
    ) last_report on true
    where coa.active = true
      and coalesce(v.empresa_id, r.organization_id) = coa.organization_id
      and (
          coa.trip_id is null
          or coa.trip_id = v.id
      );
$$;

revoke all on function public.get_customer_visible_operations(uuid) from public;
grant execute on function public.get_customer_visible_operations(uuid) to authenticated;

create or replace function public.get_customer_dashboard_summary(
    p_user_id uuid default auth.uid()
)
returns table (
    customer_id uuid,
    customer_name text,
    active_trips bigint,
    en_ruta bigint,
    esperando_carga bigint,
    cargando bigint,
    esperando_descarga bigint,
    descargando bigint,
    incidentes bigint
)
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
    select
        c.id as customer_id,
        c.name as customer_name,
        count(*) filter (where v.trip_status is not null and v.trip_status <> 'Finalizado') as active_trips,
        count(*) filter (where v.trip_status = 'En ruta') as en_ruta,
        count(*) filter (where v.trip_status = 'Esperando carga') as esperando_carga,
        count(*) filter (where v.trip_status = 'Cargando') as cargando,
        count(*) filter (where v.trip_status = 'Esperando descarga') as esperando_descarga,
        count(*) filter (where v.trip_status = 'Descargando') as descargando,
        count(*) filter (where v.trip_status = 'Incidente') as incidentes
    from public.customer_users cu
    join public.customers c on c.id = cu.customer_id and c.organization_id = cu.organization_id
    left join public.get_customer_visible_operations(cu.user_id) v on v.customer_id = c.id
    where cu.user_id = p_user_id
    group by c.id, c.name;
$$;

revoke all on function public.get_customer_dashboard_summary(uuid) from public;
grant execute on function public.get_customer_dashboard_summary(uuid) to authenticated;

-- Políticas de acceso a viajes y reportes para usuarios customer.
drop policy if exists "viajes_customer_visible" on public.viajes;
create policy "viajes_customer_visible"
on public.viajes for select to authenticated
using (
    public.user_has_org_role(viajes.empresa_id, array['owner', 'admin', 'operator', 'viewer'])
    or public.customer_has_trip_access(viajes.id, auth.uid())
    or exists (
        select 1
        from public.routes r
        where r.id = viajes.route_id
          and public.user_has_org_role(r.organization_id, array['owner', 'admin', 'operator', 'viewer'])
    )
);

drop policy if exists "reportes_customer_visible" on public.reportes;
create policy "reportes_customer_visible"
on public.reportes for select to authenticated
using (
    exists (
        select 1
        from public.viajes v
        where v.id = reportes.viaje_id
          and (
              public.user_has_org_role(v.empresa_id, array['owner', 'admin', 'operator', 'viewer'])
              or public.customer_has_trip_access(v.id, auth.uid())
          )
    )
);

revoke all on table public.customers from anon;
revoke all on table public.customer_users from anon;
revoke all on table public.customer_operation_access from anon;

create or replace function public.get_customer_context(
    p_user_id uuid default auth.uid()
)
returns table (
    organization_id uuid,
    customer_id uuid,
    customer_name text,
    role text
)
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
    select
        cu.organization_id,
        c.id as customer_id,
        c.name as customer_name,
        cu.role
    from public.customer_users cu
    join public.customers c on c.id = cu.customer_id and c.organization_id = cu.organization_id
    where cu.user_id = p_user_id;
$$;

revoke all on function public.get_customer_context(uuid) from public;
grant execute on function public.get_customer_context(uuid) to authenticated;
