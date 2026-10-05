-- Crea la primera organización y su membership owner de forma atómica.

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
    v_user_id uuid;
    v_organization_id uuid;
    v_name text;
begin
    v_user_id := auth.uid();

    if v_user_id is null then
        raise exception 'Debes iniciar sesión para crear una organización.';
    end if;

    -- Serializa intentos concurrentes del mismo usuario antes de comprobar memberships.
    perform pg_advisory_xact_lock(hashtextextended(v_user_id::text, 0));

    v_name := btrim(coalesce(p_name, ''));
    if v_name = '' then
        raise exception 'El nombre de la empresa es obligatorio.';
    end if;

    if length(v_name) > 120 then
        raise exception 'El nombre de la empresa no puede superar 120 caracteres.';
    end if;

    if exists (
        select 1
        from public.organization_members om
        where om.user_id = v_user_id
    ) then
        raise exception 'Tu usuario ya pertenece a una organización.';
    end if;

    insert into public.organizations (name, owner_id)
    values (v_name, v_user_id)
    returning id into v_organization_id;

    insert into public.organization_members (organization_id, user_id, role)
    values (v_organization_id, v_user_id, 'owner');

    return query
    select v_organization_id, v_name;
end;
$$;

revoke all on function public.create_organization_for_current_user(text) from public;
grant execute on function public.create_organization_for_current_user(text) to authenticated;
