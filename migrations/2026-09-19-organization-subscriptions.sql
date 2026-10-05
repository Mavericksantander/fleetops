-- Modelo de producto: la suscripción pertenece a la organización.

create table if not exists public.organization_subscriptions (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid unique not null references public.organizations(id) on delete cascade,
    plan text not null check (plan in ('starter', 'pro', 'enterprise')),
    status text not null check (status in ('trialing', 'active', 'past_due', 'cancelled', 'expired')),
    trial_started_at timestamptz,
    trial_ends_at timestamptz,
    current_period_start timestamptz,
    current_period_end timestamptz,
    provider text null,
    provider_customer_id text null,
    provider_subscription_id text null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.organization_plan_limits (
    plan text primary key check (plan in ('starter', 'pro', 'enterprise')),
    driver_limit integer,
    operator_limit integer,
    route_limit integer,
    created_at timestamptz not null default now()
);

insert into public.organization_plan_limits (plan, driver_limit, operator_limit, route_limit)
values
    ('starter', 10, 3, 5),
    ('pro', null, null, null),
    ('enterprise', null, null, null)
on conflict (plan) do update
set driver_limit = excluded.driver_limit,
    operator_limit = excluded.operator_limit,
    route_limit = excluded.route_limit;

alter table public.organization_subscriptions enable row level security;

drop policy if exists "organization_members_read_subscription"
    on public.organization_subscriptions;
create policy "organization_members_read_subscription"
on public.organization_subscriptions for select to authenticated
using (public.user_has_org_role(organization_id, array['owner', 'admin', 'operator', 'viewer']));

revoke all on table public.organization_plan_limits from anon, authenticated;
grant select on table public.organization_plan_limits to authenticated;

create or replace function public.create_organization_for_current_user(
    p_name text
)
returns table (
    organization_id uuid,
    organization_name text
)
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
    v_user_id uuid := auth.uid();
    v_organization_id uuid;
    v_name text := btrim(coalesce(p_name, ''));
    v_now timestamptz := now();
begin
    if v_user_id is null then
        raise exception 'Debes iniciar sesión para crear una organización.';
    end if;

    perform pg_advisory_xact_lock(hashtextextended(v_user_id::text, 0));

    if v_name = '' then
        raise exception 'El nombre de la empresa es obligatorio.';
    end if;

    if length(v_name) > 120 then
        raise exception 'El nombre de la empresa no puede superar 120 caracteres.';
    end if;

    if exists (
        select 1 from public.organization_members om where om.user_id = v_user_id
    ) then
        raise exception 'Tu usuario ya pertenece a una organización.';
    end if;

    insert into public.organizations (name, owner_id)
    values (v_name, v_user_id)
    returning id into v_organization_id;

    insert into public.organization_members (organization_id, user_id, role)
    values (v_organization_id, v_user_id, 'owner');

    insert into public.organization_subscriptions (
        organization_id, plan, status, trial_started_at, trial_ends_at
    )
    values (
        v_organization_id, 'starter', 'trialing', v_now, v_now + interval '14 days'
    );

    return query select v_organization_id, v_name;
end;
$$;

revoke all on function public.create_organization_for_current_user(text) from public;
grant execute on function public.create_organization_for_current_user(text) to authenticated;
