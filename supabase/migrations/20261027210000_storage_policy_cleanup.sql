-- Las cuatro policies de prod (solo bucket_id) las reemplaza
-- 20261027190841 con el mismo nombre: no se vuelven a tirar.
-- fleetops_documents_org_read no hace falta: el miembro lee el objeto
-- por authenticated_read_fleetops_documents cuando el path está en
-- conductor_documentos o tracto_documentos.
-- anon sigue pudiendo ejecutar private.driver_invite_may_upload:
-- sus policies de storage la llaman.
begin;

drop policy if exists fleetops_documents_org_read on storage.objects;
drop function if exists private.can_read_invite_document(text);

revoke execute on all functions in schema private from public, anon;

-- El EXECUTE a PUBLIC es un default global. Un REVOKE IN SCHEMA no lo pisa.
alter default privileges revoke execute on functions from public, anon;
alter default privileges in schema private
    revoke execute on functions from public, anon;

grant execute on function private.driver_invite_may_upload(text) to anon;

commit;
