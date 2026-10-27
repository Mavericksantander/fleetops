-- Subida anónima de onboarding, solo con invitación vigente.
-- anon no lee ni reemplaza objetos (sin upsert).
begin;

insert into storage.buckets (id, name, public)
values ('fleetops-documents', 'fleetops-documents', false)
on conflict (id) do nothing;

create or replace function private.driver_invite_may_upload(p_object_name text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select p_object_name is not null
     and p_object_name !~ '\.\.|\\'
     and split_part(p_object_name, '/', 1) = 'onboarding'
     and split_part(p_object_name, '/', 2) ~ '^[0-9a-f]{64}$'
     and split_part(p_object_name, '/', 3) in ('equipment', 'drivers')
     and split_part(p_object_name, '/', 4) ~ '^[a-z0-9-]+$'
     and split_part(p_object_name, '/', 5) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.[a-z0-9]+$'
     and split_part(p_object_name, '/', 6) = ''
     and exists (
       select 1
         from public.organization_driver_invites as invite_row
        where invite_row.token_hash = split_part(p_object_name, '/', 2)
          and invite_row.consumed_at is null
          and invite_row.expires_at > now()
     );
$$;

create or replace function private.can_read_invite_document(p_object_name text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select split_part(p_object_name, '/', 1) = 'onboarding'
     and split_part(p_object_name, '/', 2) ~ '^[0-9a-f]{64}$'
     and exists (
       select 1
         from public.organization_driver_invites as invite_row
        where invite_row.token_hash = split_part(p_object_name, '/', 2)
          and public.user_has_org_role(
            invite_row.organization_id,
            array['owner', 'admin', 'operator', 'viewer']
          )
     );
$$;

revoke all on function private.driver_invite_may_upload(text) from public, anon, authenticated;
revoke all on function private.can_read_invite_document(text) from public, anon, authenticated;
grant usage on schema private to anon;
grant execute on function private.driver_invite_may_upload(text) to anon;
grant execute on function private.can_read_invite_document(text) to authenticated;

drop policy if exists fleetops_documents_anon_invite_insert on storage.objects;
create policy fleetops_documents_anon_invite_insert
on storage.objects
for insert
to anon
with check (
  bucket_id = 'fleetops-documents'
  and private.driver_invite_may_upload(name)
);

drop policy if exists fleetops_documents_anon_invite_delete on storage.objects;
create policy fleetops_documents_anon_invite_delete
on storage.objects
for delete
to anon
using (
  bucket_id = 'fleetops-documents'
  and private.driver_invite_may_upload(name)
);

-- El DELETE de Storage hace RETURNING. Postgres solo devuelve la fila si
-- también pasa una política SELECT. Esta no abre lectura, firma ni listado.
drop policy if exists fleetops_documents_anon_invite_delete_read on storage.objects;
create policy fleetops_documents_anon_invite_delete_read
on storage.objects
for select
to anon
using (
  bucket_id = 'fleetops-documents'
  and private.driver_invite_may_upload(name)
  and storage.allow_only_operation('storage.object.delete_many')
);

drop policy if exists fleetops_documents_org_read on storage.objects;
create policy fleetops_documents_org_read
on storage.objects
for select
to authenticated
using (
  bucket_id = 'fleetops-documents'
  and private.can_read_invite_document(name)
);

create or replace function private.assert_anon_onboarding_document_path()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_kind text;
begin
  if coalesce(auth.role(), '') is distinct from 'anon' then
    return new;
  end if;

  v_kind := case tg_table_name
    when 'conductor_documentos' then 'drivers'
    when 'tracto_documentos' then 'equipment'
  end;

  if v_kind is null
     or split_part(new.storage_path, '/', 3) is distinct from v_kind
     or not private.driver_invite_may_upload(new.storage_path) then
    raise exception 'La ruta del documento no corresponde a la invitación.'
      using errcode = '22023';
  end if;

  return new;
end;
$$;

revoke all on function private.assert_anon_onboarding_document_path() from public, anon, authenticated;

drop trigger if exists conductor_documentos_anon_onboarding_path on public.conductor_documentos;
create trigger conductor_documentos_anon_onboarding_path
before insert on public.conductor_documentos
for each row execute function private.assert_anon_onboarding_document_path();

drop trigger if exists tracto_documentos_anon_onboarding_path on public.tracto_documentos;
create trigger tracto_documentos_anon_onboarding_path
before insert on public.tracto_documentos
for each row execute function private.assert_anon_onboarding_document_path();

commit;
