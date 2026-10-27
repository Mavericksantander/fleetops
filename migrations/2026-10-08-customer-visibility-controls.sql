-- Customer visibility controls and customer-specific invitations.

-- Remove the optional-argument overload added by the first customer migration;
-- the original two-argument collaborator invitation RPC remains unchanged.
drop function if exists public.create_member_invite(text, text, uuid);

-- Supabase commonly installs pgcrypto into `extensions`, not `public`.
-- Keep existing collaborator invite functions able to resolve digest/encode.
alter function public.create_member_invite(text, text)
    set search_path = public, extensions, pg_catalog;
alter function public.get_member_invite_context(text)
    set search_path = public, extensions, pg_catalog;
alter function public.accept_member_invite(text)
    set search_path = public, extensions, pg_catalog;

alter table public.customer_operation_access
    add column if not exists is_excluded boolean not null default false;

alter table public.customer_operation_access
    drop constraint if exists customer_access_exclusion_scope,
    add constraint customer_access_exclusion_scope
        check (not is_excluded or trip_id is not null) not valid;

create unique index if not exists customer_access_active_route_unique_idx
    on public.customer_operation_access (customer_id, route_id)
    where active and route_id is not null;

create unique index if not exists customer_access_active_trip_rule_unique_idx
    on public.customer_operation_access (customer_id, trip_id, is_excluded)
    where active and trip_id is not null;

create table if not exists public.customer_visibility_audit (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id) on delete cascade,
    customer_id uuid references public.customers(id) on delete set null,
    actor_user_id uuid references auth.users(id) on delete set null,
    action text not null,
    entity_id uuid,
    details jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

create index if not exists customer_visibility_audit_org_created_idx
    on public.customer_visibility_audit (organization_id, created_at desc);

alter table public.customer_visibility_audit enable row level security;

drop policy if exists "customer_visibility_audit_internal_read"
    on public.customer_visibility_audit;
create policy "customer_visibility_audit_internal_read"
on public.customer_visibility_audit for select to authenticated
using (
    public.user_has_org_role(organization_id, array['owner', 'admin'])
);

revoke all on table public.customer_visibility_audit from anon, authenticated;
grant select on table public.customer_visibility_audit to authenticated;

create or replace function public.audit_customer_visibility_change()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
    v_org_id uuid;
    v_customer_id uuid;
    v_action text;
    v_entity_id uuid;
    v_details jsonb := '{}'::jsonb;
begin
    if tg_table_name = 'customers' then
        v_org_id := coalesce(new.organization_id, old.organization_id);
        v_customer_id := coalesce(new.id, old.id);
        v_entity_id := v_customer_id;
        if tg_op = 'INSERT' then
            v_action := 'customer_created';
        elsif new.is_active is distinct from old.is_active then
            v_action := case when new.is_active then 'customer_activated' else 'customer_deactivated' end;
        else
            return new;
        end if;
    elsif tg_table_name = 'customer_operation_access' then
        v_org_id := coalesce(new.organization_id, old.organization_id);
        v_customer_id := coalesce(new.customer_id, old.customer_id);
        v_entity_id := coalesce(new.id, old.id);
        if tg_op = 'INSERT' and new.active then
            v_action := case when new.is_excluded then 'operation_access_excluded' else 'operation_access_granted' end;
        elsif old.active and not new.active then
            v_action := 'operation_access_revoked';
        else
            return new;
        end if;
        v_details := jsonb_build_object(
            'route_id', new.route_id,
            'trip_id', new.trip_id,
            'is_excluded', new.is_excluded
        );
    elsif tg_table_name = 'organization_member_invites' then
        if new.role <> 'customer' then
            return new;
        end if;
        v_org_id := new.organization_id;
        v_customer_id := new.customer_id;
        v_entity_id := new.id;
        v_action := 'customer_invitation_created';
    elsif tg_table_name = 'customer_users' then
        v_org_id := new.organization_id;
        v_customer_id := new.customer_id;
        v_entity_id := new.user_id;
        v_action := 'customer_user_accepted';
    else
        raise exception 'Tabla no soportada para auditoría de visibilidad.';
    end if;

    insert into public.customer_visibility_audit (
        organization_id, customer_id, actor_user_id, action, entity_id, details
    )
    values (
        v_org_id,
        v_customer_id,
        auth.uid(),
        v_action,
        v_entity_id,
        v_details
    );

    return null;
end;
$$;

revoke all on function public.audit_customer_visibility_change() from public;

drop trigger if exists audit_customer_visibility_customer
    on public.customers;
create trigger audit_customer_visibility_customer
after insert or update of is_active on public.customers
for each row
execute function public.audit_customer_visibility_change();

drop trigger if exists audit_customer_visibility_access
    on public.customer_operation_access;
create trigger audit_customer_visibility_access
after insert or update of active on public.customer_operation_access
for each row
execute function public.audit_customer_visibility_change();

drop trigger if exists audit_customer_visibility_invite
    on public.organization_member_invites;
create trigger audit_customer_visibility_invite
after insert on public.organization_member_invites
for each row
execute function public.audit_customer_visibility_change();

drop trigger if exists audit_customer_visibility_user
    on public.customer_users;
create trigger audit_customer_visibility_user
after insert on public.customer_users
for each row
execute function public.audit_customer_visibility_change();

drop policy if exists "customers_read_internal_and_own" on public.customers;
drop policy if exists "customers_read_internal_only" on public.customers;
create policy "customers_read_internal_only"
on public.customers for select to authenticated
using (
    public.user_has_org_role(customers.organization_id, array['owner', 'admin', 'operator', 'viewer'])
);

drop policy if exists "customer_users_read_internal_and_self" on public.customer_users;
drop policy if exists "customer_users_read_internal_only" on public.customer_users;
create policy "customer_users_read_internal_only"
on public.customer_users for select to authenticated
using (
    public.user_has_org_role(customer_users.organization_id, array['owner', 'admin', 'operator', 'viewer'])
);

drop policy if exists "customer_access_read_internal_and_self" on public.customer_operation_access;
drop policy if exists "customer_access_read_internal_only" on public.customer_operation_access;
create policy "customer_access_read_internal_only"
on public.customer_operation_access for select to authenticated
using (
    public.user_has_org_role(customer_operation_access.organization_id, array['owner', 'admin', 'operator', 'viewer'])
);

grant select, update on public.customers to authenticated;
grant select on public.customer_users to authenticated;
grant select, insert, update on public.customer_operation_access to authenticated;
grant select on public.organization_member_invites to authenticated;

create or replace function public.create_customer_member_invite(
    p_email text,
    p_customer_id uuid
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
set search_path = public, extensions, pg_catalog
as $$
declare
    v_user_id uuid := auth.uid();
    v_email text := lower(btrim(coalesce(p_email, '')));
    v_organization_id uuid;
    v_organization_name text;
    v_invite_id uuid;
    v_token text;
begin
    if v_user_id is null then
        raise exception 'Debes iniciar sesión para invitar clientes.';
    end if;

    if v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
        raise exception 'Ingresa un email válido.';
    end if;

    select c.organization_id, o.name
      into v_organization_id, v_organization_name
      from public.customers c
      join public.organizations o on o.id = c.organization_id
     where c.id = p_customer_id
       and c.is_active
       and (
           o.owner_id = v_user_id
           or exists (
               select 1
               from public.organization_members om
               where om.organization_id = c.organization_id
                 and om.user_id = v_user_id
                 and om.role = 'admin'
           )
       );

    if v_organization_id is null then
        raise exception 'No tienes permisos para invitar usuarios a este cliente.';
    end if;

    v_token := translate(encode(gen_random_bytes(32), 'base64'), E'+/=', '-_');
    v_token := replace(v_token, E'\n', '');

    insert into public.organization_member_invites (
        organization_id, email, role, customer_id, token_hash, expires_at, created_by
    )
    values (
        v_organization_id,
        v_email,
        'customer',
        p_customer_id,
        encode(digest(v_token, 'sha256'), 'hex'),
        now() + interval '7 days',
        v_user_id
    )
    returning id into v_invite_id;

    return query
    select
        v_invite_id,
        v_organization_id,
        v_organization_name,
        'customer'::text,
        v_token,
        'login.html?invite=' || v_token;
end;
$$;

revoke all on function public.create_customer_member_invite(text, uuid) from public;
grant execute on function public.create_customer_member_invite(text, uuid) to authenticated;

create or replace function public.get_customer_member_invite_context(p_token text)
returns table (
    organization_name text,
    customer_name text,
    invite_status text
)
language sql
security definer
set search_path = public, extensions, pg_catalog
as $$
    select
        o.name,
        c.name,
        case
            when invite.consumed_at is not null then 'used'
            when invite.expires_at <= now() then 'expired'
            else 'pending'
        end
    from public.organization_member_invites invite
    join public.organizations o on o.id = invite.organization_id
    join public.customers c
      on c.id = invite.customer_id
     and c.organization_id = invite.organization_id
    where invite.token_hash = encode(digest(btrim(coalesce(p_token, '')), 'sha256'), 'hex')
      and invite.role = 'customer'
    limit 1;
$$;

revoke all on function public.get_customer_member_invite_context(text) from public;
grant execute on function public.get_customer_member_invite_context(text) to anon, authenticated;

create or replace function public.customer_has_trip_access(
    p_trip_id uuid,
    p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
    select
        p_user_id = auth.uid()
        and exists (
            select 1
            from public.viajes v
            left join public.routes r on r.id = v.route_id
            join public.customer_users cu
              on cu.user_id = auth.uid()
             and cu.organization_id = coalesce(v.empresa_id, r.organization_id)
            join public.customers c
              on c.id = cu.customer_id
             and c.organization_id = cu.organization_id
             and c.is_active
            where v.id = p_trip_id
              and not exists (
                  select 1
                  from public.customer_operation_access exclusion
                  where exclusion.customer_id = c.id
                    and exclusion.organization_id = cu.organization_id
                    and exclusion.trip_id = v.id
                    and exclusion.active
                    and exclusion.is_excluded
              )
              and (
                  exists (
                      select 1
                      from public.customer_operation_access direct_access
                      where direct_access.customer_id = c.id
                        and direct_access.organization_id = cu.organization_id
                        and direct_access.trip_id = v.id
                        and direct_access.active
                        and not direct_access.is_excluded
                  )
                  or (
                      exists (
                          select 1
                          from public.customer_operation_access route_access
                          where route_access.customer_id = c.id
                            and route_access.organization_id = cu.organization_id
                            and route_access.route_id = v.route_id
                            and route_access.active
                            and not route_access.is_excluded
                      )
                  )
              )
        );
$$;

revoke all on function public.customer_has_trip_access(uuid, uuid) from public;
grant execute on function public.customer_has_trip_access(uuid, uuid) to authenticated;

create or replace function public.resolve_viaje_public(p_viaje_id uuid)
returns table (
    id uuid,
    patente text,
    conductor text,
    conductor_id uuid,
    empresa text,
    empresa_id uuid,
    ruta text,
    route_id uuid,
    estado text,
    fecha_inicio timestamptz,
    fecha_finalizacion timestamptz,
    created_at timestamptz
)
language sql
security definer
set search_path = public, pg_catalog
as $$
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
$$;

revoke all on function public.resolve_viaje_public(uuid) from public;
grant execute on function public.resolve_viaje_public(uuid) to anon, authenticated;

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
        v.id,
        c.id,
        c.name,
        coalesce(v.route_id, coa.route_id),
        r.name,
        case
            when v.fecha_finalizacion is not null then 'Finalizado'
            else coalesce(last_report.estado, v.estado, 'En ruta')
        end,
        v.ruta,
        v.patente,
        v.conductor,
        v.fecha_inicio,
        last_report."timestamp",
        last_report.estado,
        last_report.observacion,
        (
            select count(*)
            from public.reportes rp
            where rp.viaje_id = v.id
              and rp.estado = 'Incidente'
        )
    from public.customer_operation_access coa
    join public.customer_users cu
      on cu.customer_id = coa.customer_id
     and cu.user_id = auth.uid()
     and cu.organization_id = coa.organization_id
    join public.customers c
      on c.id = cu.customer_id
     and c.organization_id = cu.organization_id
     and c.is_active
    join public.viajes v
      on (coa.trip_id = v.id or coa.route_id = v.route_id)
    left join public.routes r on r.id = coalesce(v.route_id, coa.route_id)
    left join lateral (
        select rep."timestamp", rep.estado, rep.observacion
        from public.reportes rep
        where rep.viaje_id = v.id
        order by rep."timestamp" desc
        limit 1
    ) last_report on true
    where p_user_id = auth.uid()
      and 1 = (
          select count(distinct customer_scope.organization_id)
          from public.customer_users customer_scope
          where customer_scope.user_id = auth.uid()
      )
      and coa.active
      and not coa.is_excluded
      and coalesce(v.empresa_id, r.organization_id) = coa.organization_id
      and not exists (
          select 1
          from public.customer_operation_access exclusion
          where exclusion.customer_id = c.id
            and exclusion.organization_id = coa.organization_id
            and exclusion.trip_id = v.id
            and exclusion.active
            and exclusion.is_excluded
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
        c.id,
        c.name,
        count(*) filter (where v.trip_status is not null and v.trip_status <> 'Finalizado'),
        count(*) filter (where v.trip_status = 'En ruta'),
        count(*) filter (where v.trip_status = 'Esperando carga'),
        count(*) filter (where v.trip_status = 'Cargando'),
        count(*) filter (where v.trip_status = 'Esperando descarga'),
        count(*) filter (where v.trip_status = 'Descargando'),
        count(*) filter (where v.trip_status = 'Incidente')
    from public.customer_users cu
    join public.customers c
      on c.id = cu.customer_id
     and c.organization_id = cu.organization_id
     and c.is_active
    left join public.get_customer_visible_operations(auth.uid()) v
      on v.customer_id = c.id
    where p_user_id = auth.uid()
      and cu.user_id = auth.uid()
      and 1 = (
          select count(distinct customer_scope.organization_id)
          from public.customer_users customer_scope
          where customer_scope.user_id = auth.uid()
      )
    group by c.id, c.name;
$$;

revoke all on function public.get_customer_dashboard_summary(uuid) from public;
grant execute on function public.get_customer_dashboard_summary(uuid) to authenticated;

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
    select cu.organization_id, c.id, c.name, cu.role
    from public.customer_users cu
    join public.customers c
      on c.id = cu.customer_id
     and c.organization_id = cu.organization_id
     and c.is_active
    where p_user_id = auth.uid()
      and cu.user_id = auth.uid()
      and 1 = (
          select count(distinct customer_scope.organization_id)
          from public.customer_users customer_scope
          where customer_scope.user_id = auth.uid()
      );
$$;

revoke all on function public.get_customer_context(uuid) from public;
grant execute on function public.get_customer_context(uuid) to authenticated;

create or replace function public.get_customer_context_for_org(p_organization_id uuid)
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
    select cu.organization_id, c.id, c.name, cu.role
    from public.customer_users cu
    join public.customers c
      on c.id = cu.customer_id
     and c.organization_id = cu.organization_id
     and c.is_active
    where cu.organization_id = p_organization_id
      and cu.user_id = auth.uid();
$$;

revoke all on function public.get_customer_context_for_org(uuid) from public;
grant execute on function public.get_customer_context_for_org(uuid) to authenticated;

create or replace function public.get_customer_visible_operations_for_org(p_organization_id uuid)
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
        v.id,
        c.id,
        c.name,
        coalesce(v.route_id, coa.route_id),
        r.name,
        case
            when v.fecha_finalizacion is not null then 'Finalizado'
            else coalesce(last_report.estado, v.estado, 'En ruta')
        end,
        v.ruta,
        v.patente,
        v.conductor,
        v.fecha_inicio,
        last_report."timestamp",
        last_report.estado,
        last_report.observacion,
        (
            select count(*)
            from public.reportes rp
            where rp.viaje_id = v.id
              and rp.estado = 'Incidente'
        )
    from public.customer_operation_access coa
    join public.customer_users cu
      on cu.customer_id = coa.customer_id
     and cu.user_id = auth.uid()
     and cu.organization_id = p_organization_id
     and cu.organization_id = coa.organization_id
    join public.customers c
      on c.id = cu.customer_id
     and c.organization_id = cu.organization_id
     and c.is_active
    join public.viajes v
      on (coa.trip_id = v.id or coa.route_id = v.route_id)
    left join public.routes r on r.id = coalesce(v.route_id, coa.route_id)
    left join lateral (
        select rep."timestamp", rep.estado, rep.observacion
        from public.reportes rep
        where rep.viaje_id = v.id
        order by rep."timestamp" desc
        limit 1
    ) last_report on true
    where coa.active
      and not coa.is_excluded
      and coalesce(v.empresa_id, r.organization_id) = p_organization_id
      and not exists (
          select 1
          from public.customer_operation_access exclusion
          where exclusion.customer_id = c.id
            and exclusion.organization_id = p_organization_id
            and exclusion.trip_id = v.id
            and exclusion.active
            and exclusion.is_excluded
      );
$$;

revoke all on function public.get_customer_visible_operations_for_org(uuid) from public;
grant execute on function public.get_customer_visible_operations_for_org(uuid) to authenticated;

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
              or exists (
                  select 1
                  from public.routes r
                  where r.id = v.route_id
                    and public.user_has_org_role(r.organization_id, array['owner', 'admin', 'operator', 'viewer'])
              )
              or public.customer_has_trip_access(v.id, auth.uid())
          )
    )
);

-- Use the organization selected in the application rather than silently
-- creating a customer under whichever organization happens to be found first.
create or replace function public.create_customer_for_organization(
    p_organization_id uuid,
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
    v_customer_id uuid;
begin
    if v_user_id is null then
        raise exception 'Debes iniciar sesión para crear un cliente.';
    end if;

    if p_organization_id is null
       or not public.user_has_org_role(p_organization_id, array['owner', 'admin']) then
        raise exception 'No tienes permisos para crear clientes en esta organización.';
    end if;

    if v_name = '' then
        raise exception 'El nombre del cliente es obligatorio.';
    end if;

    if length(v_name) > 150 then
        raise exception 'El nombre del cliente no puede superar 150 caracteres.';
    end if;

    if v_email <> '' and v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
        raise exception 'Ingresa un email válido.';
    end if;

    insert into public.customers (
        organization_id, name, contact_name, email, phone, created_by
    )
    values (
        p_organization_id,
        v_name,
        nullif(v_contact_name, ''),
        nullif(v_email, ''),
        nullif(v_phone, ''),
        v_user_id
    )
    returning id into v_customer_id;

    return query
    select v_customer_id, p_organization_id, v_name;
end;
$$;

revoke all on function public.create_customer_for_organization(uuid, text, text, text, text) from public;
grant execute on function public.create_customer_for_organization(uuid, text, text, text, text) to authenticated;
