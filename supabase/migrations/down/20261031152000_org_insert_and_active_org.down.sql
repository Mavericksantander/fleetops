-- Reversión de 20261031152000_org_insert_and_active_org.sql.
-- Restaura exactamente el estado de main: políticas de organizations
-- (users_create_organizations INSERT y org_owner_manage_organizations FOR ALL),
-- create_customer(text,text,text,text) y create_member_invite(text,text)
-- con sus grants, y elimina las firmas con p_organization_id.
-- Solo para rollback manual; run_local.py no lo aplica (no está en migrations/*.sql).
begin;

drop policy if exists org_owner_delete_organizations on public.organizations;
drop policy if exists org_owner_manage_organizations on public.organizations;
drop policy if exists users_create_organizations on public.organizations;

create policy org_owner_manage_organizations
on public.organizations
as permissive
for all
to authenticated
using ((owner_id = auth.uid()))
with check ((owner_id = auth.uid()));

create policy users_create_organizations
on public.organizations
as permissive
for insert
to authenticated
with check ((owner_id = auth.uid()));

drop function if exists public.create_customer(uuid, text, text, text, text);
drop function if exists public.create_member_invite(uuid, text, text);

CREATE OR REPLACE FUNCTION public.create_customer(p_name text, p_contact_name text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text)
 RETURNS TABLE(customer_id uuid, organization_id uuid, customer_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.create_member_invite(p_email text, p_role text)
 RETURNS TABLE(invite_id uuid, organization_id uuid, organization_name text, role text, invite_token text, invite_url text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_catalog'
AS $function$
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
    v_token := replace(v_token, E'
', '');

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
$function$;

revoke all on function public.create_customer(text, text, text, text) from public, anon;
revoke all on function public.create_member_invite(text, text) from public, anon;
grant execute on function public.create_customer(text, text, text, text) to authenticated, service_role;
grant execute on function public.create_member_invite(text, text) to authenticated, service_role;

commit;
