-- fleetops-documents: el objeto solo es accesible si su name coincide con un
-- storage_path de conductor_documentos o tracto_documentos y private.can_access_*
-- autoriza a ese conductor o tracto. Las rutas (js/driver.js) son
-- onboarding/<uuid>/drivers|equipment/<carpeta>/<uuid>.<ext> y no traen organization_id.
-- Transaccional. Ensayar en preprod antes de producción.
begin;

create or replace function private.can_access_document_path(p_path text, p_roles text[])
returns boolean
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
    select coalesce(p_path, '') <> ''
       and (
            exists (
                select 1 from public.conductor_documentos d
                 where d.storage_path = p_path
                   and private.can_access_conductor(d.conductor_id, p_roles)
            )
            or exists (
                select 1 from public.tracto_documentos d
                 where d.storage_path = p_path
                   and private.can_access_tracto(d.tracto_id, p_roles)
            )
       )
       and not exists (
            select 1 from public.conductor_documentos d
             where d.storage_path = p_path
               and not private.can_access_conductor(d.conductor_id, p_roles)
       )
       and not exists (
            select 1 from public.tracto_documentos d
             where d.storage_path = p_path
               and not private.can_access_tracto(d.tracto_id, p_roles)
       );
$$;

revoke all on function private.can_access_document_path(text, text[]) from public, anon;
grant execute on function private.can_access_document_path(text, text[]) to authenticated, service_role;

-- Un storage_path no se puede reasignar a otro documento (el alta autenticada
-- de conductor_documentos / tracto_documentos aceptaría el path de otra org).
create or replace function private.reject_reused_storage_path()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
    if exists (
        select 1 from public.conductor_documentos d
         where d.storage_path = new.storage_path
           and (tg_table_name <> 'conductor_documentos' or d.id is distinct from new.id)
    ) or exists (
        select 1 from public.tracto_documentos d
         where d.storage_path = new.storage_path
           and (tg_table_name <> 'tracto_documentos' or d.id is distinct from new.id)
    ) then
        raise exception 'storage_path ya está asociado a otro documento'
            using errcode = '23505';
    end if;
    return new;
end;
$$;

revoke all on function private.reject_reused_storage_path() from public, anon, authenticated;

drop trigger if exists conductor_documentos_storage_path_owner on public.conductor_documentos;
create trigger conductor_documentos_storage_path_owner
    before insert or update of storage_path on public.conductor_documentos
    for each row execute function private.reject_reused_storage_path();

drop trigger if exists tracto_documentos_storage_path_owner on public.tracto_documentos;
create trigger tracto_documentos_storage_path_owner
    before insert or update of storage_path on public.tracto_documentos
    for each row execute function private.reject_reused_storage_path();

update storage.buckets
   set public = false,
       file_size_limit = 10485760,
       allowed_mime_types = array[
           'image/jpeg', 'image/png', 'image/webp', 'image/gif',
           'image/heic', 'image/heif', 'application/pdf'
       ]
 where id = 'fleetops-documents';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
select 'fleetops-documents',
       'fleetops-documents',
       false,
       10485760,
       array[
           'image/jpeg', 'image/png', 'image/webp', 'image/gif',
           'image/heic', 'image/heif', 'application/pdf'
       ]
 where not exists (
     select 1 from storage.buckets where id = 'fleetops-documents'
 );

drop policy if exists authenticated_read_fleetops_documents on storage.objects;
drop policy if exists authenticated_upload_fleetops_documents on storage.objects;
drop policy if exists authenticated_update_fleetops_documents on storage.objects;
drop policy if exists authenticated_delete_fleetops_documents on storage.objects;

create policy authenticated_read_fleetops_documents
    on storage.objects for select to authenticated
    using (
        bucket_id = 'fleetops-documents'
        and private.can_access_document_path(name, array['owner','admin','operator','viewer'])
    );

create policy authenticated_upload_fleetops_documents
    on storage.objects for insert to authenticated
    with check (
        bucket_id = 'fleetops-documents'
        and private.can_access_document_path(name, array['owner','admin','operator'])
    );

create policy authenticated_update_fleetops_documents
    on storage.objects for update to authenticated
    using (
        bucket_id = 'fleetops-documents'
        and private.can_access_document_path(name, array['owner','admin','operator'])
    )
    with check (
        bucket_id = 'fleetops-documents'
        and private.can_access_document_path(name, array['owner','admin','operator'])
    );

create policy authenticated_delete_fleetops_documents
    on storage.objects for delete to authenticated
    using (
        bucket_id = 'fleetops-documents'
        and private.can_access_document_path(name, array['owner','admin','operator'])
    );

commit;
