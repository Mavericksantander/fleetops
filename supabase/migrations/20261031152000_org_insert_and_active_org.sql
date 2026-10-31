-- Alta de organización solo por create_organization_for_current_user.
-- users_create_organizations (INSERT, owner_id = auth.uid()) dejaba a
-- cualquier autenticado crear otra organización sin pasar por la regla
-- «ya pertenece a una organización». org_owner_manage_organizations es
-- FOR ALL con el mismo WITH CHECK, así que también autorizaba ese INSERT:
-- se deja en UPDATE y DELETE.
-- create_member_invite y create_customer dejan de elegir la org más
-- antigua que el usuario posee o administra. Reciben p_organization_id
-- y lo autorizan con user_has_org_role, igual que
-- create_customer_for_organization. La firma vieja se elimina.
begin;

drop policy if exists users_create_organizations on public.organizations;
drop policy if exists org_owner_manage_organizations on public.organizations;

create policy org_owner_manage_organizations
on public.organizations
as permissive
for update
to authenticated
using ((owner_id = auth.uid()))
with check ((owner_id = auth.uid()));

create policy org_owner_delete_organizations
on public.organizations
as permissive
for delete
to authenticated
using ((owner_id = auth.uid()));

drop function if exists public.create_customer(text, text, text, text);
drop function if exists public.create_member_invite(text, text);

create or replace function public.create_customer(p_organization_id uuid, p_name text, p_contact_name text default null::text, p_email text default null::text, p_phone text default null::text)
returns table(customer_id uuid, organization_id uuid, customer_name text)
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
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

    insert into public.customers (
        organization_id,
        name,
        contact_name,
        email,
        phone,
        created_by
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
$function$;

create or replace function public.create_member_invite(p_organization_id uuid, p_email text, p_role text)
returns table(invite_id uuid, organization_id uuid, organization_name text, role text, invite_token text, invite_url text)
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_catalog'
as $function$
declare
    v_user_id uuid := auth.uid();
    v_email text := lower(btrim(coalesce(p_email, '')));
    v_role text := lower(btrim(coalesce(p_role, '')));
    v_organization_name text;
    v_invite_id uuid;
    v_token text;
    v_expires_at timestamptz := now() + interval '7 days';
begin
    if v_user_id is null then
        raise exception 'Debes iniciar sesión para invitar colaboradores.';
    end if;

    if p_organization_id is null
       or not public.user_has_org_role(p_organization_id, array['owner', 'admin']) then
        raise exception 'No tienes permisos para invitar colaboradores en esta organización.';
    end if;

    if v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
        raise exception 'Ingresa un email válido.';
    end if;

    if v_role not in ('admin', 'operator', 'viewer') then
        raise exception 'El rol debe ser admin, operator o viewer.';
    end if;

    select o.name
      into v_organization_name
      from public.organizations o
     where o.id = p_organization_id;

    if v_organization_name is null then
        raise exception 'No tienes permisos para invitar colaboradores en esta organización.';
    end if;

    v_token := translate(encode(gen_random_bytes(32), 'base64'), E'+/=', '-_');
    v_token := replace(v_token, E'
', '');

    insert into public.organization_member_invites (
        organization_id, email, role, token_hash, expires_at, created_by
    )
    values (
        p_organization_id,
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
        p_organization_id,
        v_organization_name,
        v_role,
        v_token,
        'login.html?invite=' || v_token;
end;
$function$;

revoke all on function public.create_customer(uuid, text, text, text, text) from public, anon;
revoke all on function public.create_member_invite(uuid, text, text) from public, anon;
grant execute on function public.create_customer(uuid, text, text, text, text) to authenticated, service_role;
grant execute on function public.create_member_invite(uuid, text, text) to authenticated, service_role;

commit;
