-- FleetOps multiempresa + RBAC
-- Requiere que las tablas base ya existan y que la estructura de organizaciones/rutas/viajes esté presente.
-- No se crean tablas nuevas ni columnas permanentes de organización en conductores/tractos.

create or replace function public.user_has_org_role(
    p_organization_id uuid,
    p_roles text[]
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $$
declare
    v_user_id uuid;
begin
    v_user_id := auth.uid();

    if v_user_id is null or p_organization_id is null then
        return false;
    end if;

    return exists (
        select 1
        from public.organization_members om
        where om.organization_id = p_organization_id
          and om.user_id = v_user_id
          and om.role = any(p_roles)
    )
    or exists (
        select 1
        from public.organizations o
        where o.id = p_organization_id
          and o.owner_id = v_user_id
          and 'owner' = any(p_roles)
    );
end;
$$;

revoke all on function public.user_has_org_role(uuid, text[]) from public;
grant execute on function public.user_has_org_role(uuid, text[]) to authenticated;

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
        v.empresa_id,
        v.ruta,
        v.route_id,
        v.estado,
        v.fecha_inicio,
        v.fecha_finalizacion,
        v.created_at
    from public.viajes v
    where v.id = p_viaje_id
    limit 1;
$$;

revoke all on function public.resolve_viaje_public(uuid) from public;
grant execute on function public.resolve_viaje_public(uuid) to anon;
grant execute on function public.resolve_viaje_public(uuid) to authenticated;

drop function if exists public.finalizar_viaje(uuid);

create or replace function public.finalizar_viaje(p_viaje_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
    v_organization_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Debe iniciar sesión para autorizar la finalización.';
    end if;

    select coalesce(v.empresa_id, r.organization_id)
      into v_organization_id
      from public.viajes v
      left join public.routes r on r.id = v.route_id
     where v.id = p_viaje_id
     limit 1;

    if v_organization_id is null then
        raise exception 'No existe un viaje válido para finalizar.';
    end if;

    if not public.user_has_org_role(v_organization_id, array['owner', 'admin', 'operator']) then
        raise exception 'No tienes permisos para autorizar la finalización de este viaje.';
    end if;

    update public.viajes
       set estado = 'Finalizado',
           fecha_finalizacion = now()
     where id = p_viaje_id
       and fecha_finalizacion is null;

    return true;
end;
$$;

revoke all on function public.finalizar_viaje(uuid) from public;
grant execute on function public.finalizar_viaje(uuid) to authenticated;

do $$
begin
    if to_regprocedure('public.finalizar_viaje(text)') is not null then
        execute 'revoke execute on function public.finalizar_viaje(text) from public, anon, authenticated';
    end if;
end;
$$;

alter table if exists public.organizations enable row level security;
alter table if exists public.organization_members enable row level security;
alter table if exists public.routes enable row level security;
alter table if exists public.viajes enable row level security;

-- Eliminar políticas legacy que podrían coexistir con las políticas RBAC nuevas.
drop policy if exists "members_read_viajes" on public.viajes;
drop policy if exists "members_manage_viajes" on public.viajes;
drop policy if exists "FleetOps permitir inserciones de viajes" on public.viajes;
drop policy if exists "FleetOps permitir lectura de viajes" on public.viajes;
drop policy if exists "members_read_routes" on public.routes;
drop policy if exists "members_manage_routes" on public.routes;
drop policy if exists "members_read_organizations" on public.organizations;
drop policy if exists "owners_manage_organizations" on public.organizations;
drop policy if exists "owners_manage_memberships" on public.organization_members;

create or replace function public.can_manage_membership(
    p_organization_id uuid,
    p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
    select exists (
        select 1
        from public.organizations o
        where o.id = p_organization_id
          and o.owner_id = p_user_id
    )
    or exists (
        select 1
        from public.organization_members om
        where om.organization_id = p_organization_id
          and om.user_id = p_user_id
          and om.role = 'admin'
    );
$$;

revoke all on function public.can_manage_membership(uuid, uuid) from public;
grant execute on function public.can_manage_membership(uuid, uuid) to authenticated;

create or replace function public.can_read_membership(
    p_organization_id uuid,
    p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
    select exists (
        select 1
        from public.organizations o
        where o.id = p_organization_id
          and o.owner_id = p_user_id
    )
    or exists (
        select 1
        from public.organization_members om
        where om.organization_id = p_organization_id
          and om.user_id = p_user_id
          and om.role in ('owner', 'admin')
    );
$$;

revoke all on function public.can_read_membership(uuid, uuid) from public;
grant execute on function public.can_read_membership(uuid, uuid) to authenticated;

-- Políticas de organizaciones
drop policy if exists "org_members_read_organizations" on public.organizations;
create policy "org_members_read_organizations"
on public.organizations for select to authenticated
using (
    owner_id = auth.uid()
    or exists (
        select 1
        from public.organization_members om
        where om.organization_id = organizations.id
          and om.user_id = auth.uid()
    )
);

drop policy if exists "org_owner_manage_organizations" on public.organizations;
create policy "org_owner_manage_organizations"
on public.organizations for all to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

-- Política de memberships segura: no consulta organization_members desde la misma tabla.
-- Regla: usuario puede ver su propia membership; owner/admin de la org pueden leer memberships; solo owner/admin pueden modificar.
drop policy if exists "members_read_memberships" on public.organization_members;
create policy "members_read_memberships"
on public.organization_members for select to authenticated
using (
    user_id = auth.uid()
    or public.can_read_membership(organization_members.organization_id, auth.uid())
);

drop policy if exists "organization_admins_manage_memberships" on public.organization_members;
create policy "organization_admins_manage_memberships"
on public.organization_members for all to authenticated
using (
    public.can_manage_membership(organization_members.organization_id, auth.uid())
)
with check (
    (
        public.can_manage_membership(organization_members.organization_id, auth.uid())
        and (
            organization_members.role is distinct from 'owner'
            or exists (
                select 1
                from public.organizations o
                where o.id = organization_members.organization_id
                  and o.owner_id = auth.uid()
            )
        )
    )
);

-- Políticas de rutas
drop policy if exists "routes_select_by_org" on public.routes;
create policy "routes_select_by_org"
on public.routes for select to authenticated
using (
    public.user_has_org_role(routes.organization_id, array['owner', 'admin', 'operator', 'viewer'])
);

drop policy if exists "routes_manage_by_admin_owner" on public.routes;
create policy "routes_manage_by_admin_owner"
on public.routes for all to authenticated
using (
    public.user_has_org_role(routes.organization_id, array['owner', 'admin'])
)
with check (
    public.user_has_org_role(routes.organization_id, array['owner', 'admin'])
);

-- Políticas de viajes
drop policy if exists "viajes_read_org_members" on public.viajes;
create policy "viajes_read_org_members"
on public.viajes for select to authenticated
using (
    public.user_has_org_role(viajes.empresa_id, array['owner', 'admin', 'operator', 'viewer'])
    or exists (
        select 1
        from public.routes r
        where r.id = viajes.route_id
          and public.user_has_org_role(r.organization_id, array['owner', 'admin', 'operator', 'viewer'])
    )
);

drop policy if exists "viajes_insert_org_roles" on public.viajes;
create policy "viajes_insert_org_roles"
on public.viajes for insert to authenticated
with check (
    (
        empresa_id is not null
        and public.user_has_org_role(empresa_id, array['owner', 'admin', 'operator'])
    )
    or (
        route_id is not null
        and exists (
            select 1
            from public.routes r
            where r.id = route_id
              and public.user_has_org_role(r.organization_id, array['owner', 'admin', 'operator'])
        )
    )
);

drop policy if exists "viajes_update_org_roles" on public.viajes;
create policy "viajes_update_org_roles"
on public.viajes for update to authenticated
using (
    public.user_has_org_role(viajes.empresa_id, array['owner', 'admin', 'operator'])
    or exists (
        select 1
        from public.routes r
        where r.id = viajes.route_id
          and public.user_has_org_role(r.organization_id, array['owner', 'admin', 'operator'])
    )
)
with check (
    (
        empresa_id is not null
        and public.user_has_org_role(empresa_id, array['owner', 'admin', 'operator'])
    )
    or (
        route_id is not null
        and exists (
            select 1
            from public.routes r
            where r.id = route_id
              and public.user_has_org_role(r.organization_id, array['owner', 'admin', 'operator'])
        )
    )
);

drop policy if exists "viajes_delete_org_roles" on public.viajes;
create policy "viajes_delete_org_roles"
on public.viajes for delete to authenticated
using (
    public.user_has_org_role(viajes.empresa_id, array['owner', 'admin'])
    or exists (
        select 1
        from public.routes r
        where r.id = viajes.route_id
          and public.user_has_org_role(r.organization_id, array['owner', 'admin'])
    )
);

-- No se exponen viajes a anon. El acceso público se resuelve solo por UUID mediante SECURITY DEFINER.
revoke all on table public.viajes from anon;

-- Como seguridad, no se deja SELECT true ni listado por patente; la función pública solo acepta un UUID exacto.
