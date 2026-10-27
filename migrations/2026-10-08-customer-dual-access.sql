-- Allow existing organization members to also accept customer visibility access
-- without changing or removing their current organization role.
create or replace function public.accept_member_invite(p_token text)
returns table (
    organization_id uuid,
    role text
)
language plpgsql
security definer
set search_path = public, extensions, pg_catalog
as $$
#variable_conflict use_column
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

    if v_invite.platform_bootstrap then
        if exists (
            select 1
            from public.organization_members om
            where om.organization_id = v_invite.organization_id
              and om.user_id = v_user_id
        ) then
            raise exception 'Tu usuario ya pertenece a esta organización.';
        end if;

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

        if exists (
            select 1
            from public.customer_users cu
            where cu.organization_id = v_invite.organization_id
              and cu.user_id = v_user_id
              and cu.customer_id <> v_invite.customer_id
        ) then
            raise exception 'Este usuario ya tiene acceso a otro cliente de esta organización.';
        end if;

        insert into public.customer_users (organization_id, customer_id, user_id, role)
        values (v_invite.organization_id, v_invite.customer_id, v_user_id, 'customer')
        on conflict (customer_id, user_id) do nothing;

        insert into public.organization_members (organization_id, user_id, role)
        values (v_invite.organization_id, v_user_id, 'customer')
        on conflict (organization_id, user_id) do nothing;
    else
        if v_invite.role not in ('owner', 'admin', 'operator', 'viewer') then
            raise exception 'El rol de invitación no es válido.';
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
