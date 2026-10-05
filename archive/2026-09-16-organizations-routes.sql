-- FleetOps configuration layer
-- Run in Supabase SQL Editor after reviewing with the project owner.

create table if not exists public.organizations (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    owner_id uuid not null references auth.users(id) on delete cascade,
    active boolean not null default true,
    created_at timestamptz not null default now()
);

create table if not exists public.organization_members (
    organization_id uuid not null references public.organizations(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    role text not null default 'operator' check (role in ('owner', 'operator')),
    created_at timestamptz not null default now(),
    primary key (organization_id, user_id)
);

create table if not exists public.routes (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id) on delete cascade,
    name text not null,
    origin text,
    destination text,
    client text,
    active boolean not null default true,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    unique (organization_id, name)
);

alter table public.viajes
    add column if not exists route_id uuid references public.routes(id);

create index if not exists idx_routes_organization_active
    on public.routes(organization_id, active);

create index if not exists idx_viajes_route_id
    on public.viajes(route_id);

alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.routes enable row level security;

create policy "members_read_organizations"
on public.organizations for select to authenticated
using (
    owner_id = auth.uid()
    or exists (
        select 1 from public.organization_members m
        where m.organization_id = organizations.id
          and m.user_id = auth.uid()
    )
);

create policy "users_create_organizations"
on public.organizations for insert to authenticated
with check (owner_id = auth.uid());

create policy "owners_manage_organizations"
on public.organizations for all to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

create policy "members_read_memberships"
on public.organization_members for select to authenticated
using (user_id = auth.uid());

create policy "owners_manage_memberships"
on public.organization_members for all to authenticated
using (
    exists (
        select 1 from public.organizations o
        where o.id = organization_members.organization_id
          and o.owner_id = auth.uid()
    )
)
with check (
    exists (
        select 1 from public.organizations o
        where o.id = organization_members.organization_id
          and o.owner_id = auth.uid()
    )
);

create policy "members_read_routes"
on public.routes for select to authenticated
using (
    exists (
        select 1 from public.organization_members m
        where m.organization_id = routes.organization_id
          and m.user_id = auth.uid()
    )
    or exists (
        select 1 from public.organizations o
        where o.id = routes.organization_id
          and o.owner_id = auth.uid()
    )
);

create policy "members_manage_routes"
on public.routes for all to authenticated
using (
    exists (
        select 1 from public.organization_members m
        where m.organization_id = routes.organization_id
          and m.user_id = auth.uid()
          and m.role in ('owner', 'operator')
    )
    or exists (
        select 1 from public.organizations o
        where o.id = routes.organization_id
          and o.owner_id = auth.uid()
    )
)
with check (
    exists (
        select 1 from public.organization_members m
        where m.organization_id = routes.organization_id
          and m.user_id = auth.uid()
          and m.role in ('owner', 'operator')
    )
    or exists (
        select 1 from public.organizations o
        where o.id = routes.organization_id
          and o.owner_id = auth.uid()
    )
);

create policy "authenticated_update_viajes_route"
on public.viajes for update to authenticated
using (true)
with check (true);
