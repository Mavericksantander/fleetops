-- RPCs requeridas por la integración frontend de invitaciones.

create or replace function public.resolve_organization_driver_invite(
    p_token text
)
returns table (
    organization_id uuid,
    organization_name text,
    expires_at timestamptz
)
language plpgsql
security definer
set search_path = public, extensions, pg_catalog
as $$
begin
    return query
    select o.id, o.name, i.expires_at
      from public.organization_driver_invites i
      join public.organizations o on o.id = i.organization_id
     where i.token_hash = encode(digest(trim(p_token), 'sha256'), 'hex')
       and i.consumed_at is null
       and i.expires_at > now();
end;
$$;

revoke all on function public.resolve_organization_driver_invite(text) from public;
grant execute on function public.resolve_organization_driver_invite(text) to anon, authenticated;

create or replace function public.reject_organization_driver(
    p_organization_id uuid,
    p_conductor_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
    if auth.uid() is null
       or not public.can_manage_membership(p_organization_id, auth.uid()) then
        raise exception 'Solo owner/admin puede rechazar conductores.';
    end if;

    delete from public.organization_drivers
     where organization_id = p_organization_id
       and conductor_id = p_conductor_id
       and status = 'PENDING';

    return found;
end;
$$;

revoke all on function public.reject_organization_driver(uuid, uuid) from public;
grant execute on function public.reject_organization_driver(uuid, uuid) to authenticated;
