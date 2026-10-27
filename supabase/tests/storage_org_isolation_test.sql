-- =====================================================================
-- Storage fleetops-documents · aislamiento por organización.
-- Corre después de las migraciones, en la misma BD local que T-012.
-- Las rutas copian js/driver.js:
--   onboarding/<uuid>/drivers/<carpeta>/<uuid>.jpg
--   onboarding/<uuid>/equipment/<carpeta>/<uuid>.<ext>
-- El segundo segmento NO es el organization_id.
-- =====================================================================
reset role;
select set_config('request.jwt.claims', '', false);

insert into auth.users(id, email) values
 ('51000000-0000-4000-8000-0000000000a1','storage-owner-a@example.test'),
 ('51000000-0000-4000-8000-0000000000a2','storage-viewer-a@example.test'),
 ('51000000-0000-4000-8000-0000000000b1','storage-owner-b@example.test');
insert into public.organizations(id, name, owner_id) values
 ('5100000a-0000-4000-8000-000000000000','Org SA','51000000-0000-4000-8000-0000000000a1'),
 ('5100000b-0000-4000-8000-000000000000','Org SB','51000000-0000-4000-8000-0000000000b1');
insert into public.organization_members(organization_id, user_id, role) values
 ('5100000a-0000-4000-8000-000000000000','51000000-0000-4000-8000-0000000000a1','owner'),
 ('5100000a-0000-4000-8000-000000000000','51000000-0000-4000-8000-0000000000a2','viewer'),
 ('5100000b-0000-4000-8000-000000000000','51000000-0000-4000-8000-0000000000b1','owner');
insert into public.tractos(id, patente, organization_id) values
 ('517a0000-0000-4000-8000-000000000000','SAAAA1','5100000a-0000-4000-8000-000000000000'),
 ('517b0000-0000-4000-8000-000000000000','SBBBB2', null);
insert into public.conductores(id, nombre, telefono, tracto_id) values
 ('51ca0000-0000-4000-8000-000000000000','Conductor SA','+56911111111','517a0000-0000-4000-8000-000000000000'),
 ('51cb0000-0000-4000-8000-000000000000','Conductor SB','+56922222222','517b0000-0000-4000-8000-000000000000');
insert into public.organization_drivers(organization_id, conductor_id, status) values
 ('5100000a-0000-4000-8000-000000000000','51ca0000-0000-4000-8000-000000000000','ACTIVE'),
 ('5100000b-0000-4000-8000-000000000000','51cb0000-0000-4000-8000-000000000000','ACTIVE');

-- B_SELFIE lleva el id de la org A en el path a propósito.
insert into public.conductor_documentos(conductor_id, tipo_documento, storage_path) values
 ('51ca0000-0000-4000-8000-000000000000','selfie','onboarding/11111111-1111-4111-8111-111111111111/drivers/selfie/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1.jpg'),
 ('51ca0000-0000-4000-8000-000000000000','licencia_frente','onboarding/11111111-1111-4111-8111-111111111111/drivers/frente/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3.jpg'),
 ('51ca0000-0000-4000-8000-000000000000','licencia_reverso','onboarding/11111111-1111-4111-8111-111111111111/drivers/reverso/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4.jpg'),
 ('51cb0000-0000-4000-8000-000000000000','selfie','onboarding/5100000a-0000-4000-8000-000000000000/drivers/selfie/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1.jpg');
insert into public.tracto_documentos(tracto_id, tipo_documento, storage_path) values
 ('517a0000-0000-4000-8000-000000000000','padron_vehicular','onboarding/11111111-1111-4111-8111-111111111111/equipment/padron/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2.pdf'),
 ('517a0000-0000-4000-8000-000000000000','soap','onboarding/11111111-1111-4111-8111-111111111111/equipment/soap/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5.pdf'),
 ('517b0000-0000-4000-8000-000000000000','padron_vehicular','onboarding/22222222-2222-4222-8222-222222222222/equipment/padron/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2.pdf');

insert into storage.buckets (id, name, public)
values ('other-bucket', 'other-bucket', false)
on conflict (id) do nothing;
insert into storage.objects(bucket_id, name) values
 ('fleetops-documents','onboarding/11111111-1111-4111-8111-111111111111/drivers/selfie/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1.jpg'),
 ('fleetops-documents','onboarding/11111111-1111-4111-8111-111111111111/equipment/padron/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2.pdf'),
 ('fleetops-documents','onboarding/5100000a-0000-4000-8000-000000000000/drivers/selfie/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1.jpg'),
 ('fleetops-documents','onboarding/22222222-2222-4222-8222-222222222222/equipment/padron/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2.pdf'),
 ('fleetops-documents','onboarding/33333333-3333-4333-8333-333333333333/drivers/frente/cccccccc-cccc-4ccc-8ccc-ccccccccccc1.jpg'),
 ('other-bucket','onboarding/11111111-1111-4111-8111-111111111111/drivers/selfie/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1.jpg');

create or replace function pg_temp.storage_denied(p_sql text) returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when insufficient_privilege then return true;
end $$;
grant execute on function pg_temp.storage_denied(text) to public;

create or replace function pg_temp.storage_sqlstate(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then return sqlstate;
end $$;
grant execute on function pg_temp.storage_sqlstate(text) to public;

do $$
declare
    b storage.buckets%rowtype;
    n int;
    r record;
begin
    select * into b from storage.buckets where id = 'fleetops-documents';
    assert b.public = false, 'bucket fleetops-documents quedó público';
    assert b.file_size_limit = 10485760, format('file_size_limit=%s', b.file_size_limit);
    assert b.allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif','image/heic','image/heif','application/pdf'],
           format('allowed_mime_types=%s', b.allowed_mime_types);

    select count(*) into n from pg_policy
     where polrelid = 'storage.objects'::regclass
       and polname in (
           'authenticated_read_fleetops_documents',
           'authenticated_upload_fleetops_documents',
           'authenticated_update_fleetops_documents',
           'authenticated_delete_fleetops_documents');
    assert n = 4, format('políticas fleetops-documents = %s', n);
    for r in
        select polname,
               coalesce(pg_get_expr(polqual, polrelid), '') as u,
               coalesce(pg_get_expr(polwithcheck, polrelid), '') as c
          from pg_policy
         where polrelid = 'storage.objects'::regclass
           and polname like '%fleetops_documents'
    loop
        assert (r.u || r.c) like '%can_access_document_path%', r.polname || ' no usa el helper';
        assert (r.u || r.c) like '%fleetops-documents%', r.polname || ' no restringe el bucket';
    end loop;
    raise notice 'BUCKET: OK — privado, 10 MiB, MIME imagen/PDF; 4 políticas por organización';
end $$;

-- ============================ ANON ===================================
set role anon;
do $$
declare n int;
begin
    select count(*) into n from storage.objects;
    assert n = 0, format('anon ve %s objetos', n);
    assert pg_temp.storage_denied($q$insert into storage.objects(bucket_id, name) values ('fleetops-documents','onboarding/33333333-3333-4333-8333-333333333333/drivers/frente/cccccccc-cccc-4ccc-8ccc-ccccccccccc1.jpg')$q$),
           'anon puede insertar en fleetops-documents';
    assert pg_temp.storage_denied($q$select private.can_access_document_path('x', array['owner'])$q$),
           'anon ejecuta can_access_document_path';
    raise notice 'ANON: OK — sin lectura, sin upload, sin helper';
end $$;

-- ===================== USUARIO ORG A (owner) =========================
reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"51000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$
declare n int;
begin
    select count(*) into n from storage.objects
     where name = 'onboarding/11111111-1111-4111-8111-111111111111/drivers/selfie/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1.jpg';
    assert n = 1, 'org A no lee su selfie';
    select count(*) into n from storage.objects
     where name = 'onboarding/11111111-1111-4111-8111-111111111111/equipment/padron/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2.pdf';
    assert n = 1, 'org A no lee su padrón';
    select count(*) into n from storage.objects
     where name = 'onboarding/5100000a-0000-4000-8000-000000000000/drivers/selfie/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1.jpg';
    assert n = 0, 'org A lee la selfie de org B (el path contiene el id de org A)';
    select count(*) into n from storage.objects
     where name = 'onboarding/22222222-2222-4222-8222-222222222222/equipment/padron/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2.pdf';
    assert n = 0, 'org A lee el padrón de org B (tracto sin organization_id)';
    select count(*) into n from storage.objects
     where name = 'onboarding/33333333-3333-4333-8333-333333333333/drivers/frente/cccccccc-cccc-4ccc-8ccc-ccccccccccc1.jpg';
    assert n = 0, 'org A lee un objeto sin fila de documento';
    select count(*) into n from storage.objects where bucket_id = 'other-bucket';
    assert n = 0, 'org A lee otro bucket';
    select count(*) into n from storage.objects where bucket_id = 'fleetops-documents';
    assert n = 2, format('org A ve %s objetos de fleetops-documents, esperaba 2', n);

    update storage.objects set metadata = '{"ok":true}'::jsonb
     where name = 'onboarding/11111111-1111-4111-8111-111111111111/drivers/selfie/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1.jpg';
    get diagnostics n = row_count;
    assert n = 1, 'org A no actualizó su selfie';

    update storage.objects set metadata = '{"pwn":true}'::jsonb
     where name = 'onboarding/5100000a-0000-4000-8000-000000000000/drivers/selfie/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1.jpg';
    get diagnostics n = row_count;
    assert n = 0, 'org A actualizó la selfie de org B';

    delete from storage.objects
     where name = 'onboarding/22222222-2222-4222-8222-222222222222/equipment/padron/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2.pdf';
    get diagnostics n = row_count;
    assert n = 0, 'org A borró el padrón de org B';

    assert pg_temp.storage_sqlstate($q$update storage.objects set name = 'onboarding/5100000a-0000-4000-8000-000000000000/drivers/selfie/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1.jpg' where name = 'onboarding/11111111-1111-4111-8111-111111111111/drivers/selfie/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1.jpg'$q$) = '42501',
           'org A renombró su objeto al path de org B';
    select count(*) into n from storage.objects
     where name = 'onboarding/11111111-1111-4111-8111-111111111111/drivers/selfie/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1.jpg';
    assert n = 1, 'el rename cruzado alteró el objeto de org A';

    insert into storage.objects(bucket_id, name)
    values ('fleetops-documents','onboarding/11111111-1111-4111-8111-111111111111/drivers/frente/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3.jpg');
    get diagnostics n = row_count;
    assert n = 1, 'org A no subió el frente ya registrado en conductor_documentos';

    assert pg_temp.storage_sqlstate($q$insert into storage.objects(bucket_id, name) values ('fleetops-documents','onboarding/33333333-3333-4333-8333-333333333333/drivers/frente/dddddddd-dddd-4ddd-8ddd-ddddddddddd1.jpg')$q$) = '42501',
           'org A subió un path que no está en documentos';
    assert pg_temp.storage_sqlstate($q$insert into storage.objects(bucket_id, name) values ('other-bucket','onboarding/11111111-1111-4111-8111-111111111111/drivers/frente/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3.jpg')$q$) = '42501',
           'org A subió a otro bucket';

    assert pg_temp.storage_sqlstate($q$insert into public.conductor_documentos(conductor_id, tipo_documento, storage_path) values ('51ca0000-0000-4000-8000-000000000000','selfie','onboarding/5100000a-0000-4000-8000-000000000000/drivers/selfie/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1.jpg')$q$) = '23505',
           'org A reasignó el storage_path de org B';

    delete from storage.objects
     where name = 'onboarding/11111111-1111-4111-8111-111111111111/equipment/padron/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2.pdf';
    get diagnostics n = row_count;
    assert n = 1, 'org A no borró su padrón';
    select count(*) into n from storage.objects
     where name = 'onboarding/11111111-1111-4111-8111-111111111111/equipment/padron/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2.pdf';
    assert n = 0, 'el padrón de org A sigue visible';

    raise notice 'ORG A (owner): OK — lee/escribe lo suyo; no lee, no pisa y no borra lo de org B';
end $$;

-- Fallo cerrado: si un path queda en dos orgs, nadie lo lee.
reset role;
do $$
declare n int;
begin
    alter table public.conductor_documentos disable trigger conductor_documentos_storage_path_owner;
    insert into public.conductor_documentos(conductor_id, tipo_documento, storage_path)
    values ('51ca0000-0000-4000-8000-000000000000','selfie',
            'onboarding/22222222-2222-4222-8222-222222222222/equipment/padron/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2.pdf');

    perform set_config('request.jwt.claims', '{"sub":"51000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
    set local role authenticated;
    select count(*) into n from storage.objects
     where name = 'onboarding/22222222-2222-4222-8222-222222222222/equipment/padron/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2.pdf';
    if n <> 0 then
        raise exception 'org A leyó el padrón de org B tras copiar el storage_path';
    end if;

    perform set_config('request.jwt.claims', '{"sub":"51000000-0000-4000-8000-0000000000b1","role":"authenticated"}', true);
    select count(*) into n from storage.objects
     where name = 'onboarding/22222222-2222-4222-8222-222222222222/equipment/padron/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2.pdf';
    if n <> 0 then
        raise exception 'org B sigue leyendo un path también apuntado por org A';
    end if;

    raise exception 'rollback path compartido';
exception
    when others then
        if sqlerrm <> 'rollback path compartido' then
            raise;
        end if;
end $$;

do $$
declare enabled char;
begin
    select tgenabled into enabled from pg_trigger
     where tgname = 'conductor_documentos_storage_path_owner';
    assert enabled = 'O', 'el trigger de storage_path quedó deshabilitado';
    raise notice 'PATH COMPARTIDO: OK — trigger rechaza la reasignación (23505) y, si existe, nadie lee el objeto';
end $$;

-- ===================== USUARIO ORG A (viewer) ========================
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"51000000-0000-4000-8000-0000000000a2","role":"authenticated"}', false);
do $$
declare n int;
begin
    select count(*) into n from storage.objects
     where name = 'onboarding/11111111-1111-4111-8111-111111111111/drivers/selfie/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1.jpg';
    assert n = 1, 'viewer A no lee la selfie de su org';
    select count(*) into n from storage.objects
     where name = 'onboarding/5100000a-0000-4000-8000-000000000000/drivers/selfie/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1.jpg';
    assert n = 0, 'viewer A lee org B';

    update storage.objects set metadata = '{"viewer":true}'::jsonb
     where name = 'onboarding/11111111-1111-4111-8111-111111111111/drivers/selfie/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1.jpg';
    get diagnostics n = row_count;
    assert n = 0, 'viewer A actualizó un objeto';

    delete from storage.objects
     where name = 'onboarding/11111111-1111-4111-8111-111111111111/drivers/frente/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3.jpg';
    get diagnostics n = row_count;
    assert n = 0, 'viewer A borró el frente';

    assert pg_temp.storage_sqlstate($q$insert into storage.objects(bucket_id, name) values ('fleetops-documents','onboarding/11111111-1111-4111-8111-111111111111/drivers/reverso/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4.jpg')$q$) = '42501',
           'viewer A subió el reverso';
    raise notice 'ORG A (viewer): OK — lectura de su org, sin upload/update/delete';
end $$;

-- ===================== USUARIO ORG B (owner) =========================
select set_config('request.jwt.claims', '{"sub":"51000000-0000-4000-8000-0000000000b1","role":"authenticated"}', false);
do $$
declare n int;
begin
    select count(*) into n from storage.objects
     where name = 'onboarding/5100000a-0000-4000-8000-000000000000/drivers/selfie/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1.jpg';
    assert n = 1, 'org B no lee su selfie';
    select count(*) into n from storage.objects
     where name = 'onboarding/22222222-2222-4222-8222-222222222222/equipment/padron/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2.pdf';
    assert n = 1, 'org B no lee su padrón (tracto sin organization_id)';
    select count(*) into n from storage.objects
     where name = 'onboarding/11111111-1111-4111-8111-111111111111/drivers/selfie/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1.jpg';
    assert n = 0, 'org B lee la selfie de org A';
    select count(*) into n from storage.objects
     where name = 'onboarding/11111111-1111-4111-8111-111111111111/drivers/frente/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3.jpg';
    assert n = 0, 'org B lee el frente que subió org A';
    select count(*) into n from storage.objects where bucket_id = 'fleetops-documents';
    assert n = 2, format('org B ve %s objetos, esperaba 2', n);

    assert pg_temp.storage_sqlstate($q$insert into storage.objects(bucket_id, name) values ('fleetops-documents','onboarding/11111111-1111-4111-8111-111111111111/equipment/soap/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5.pdf')$q$) = '42501',
           'org B subió el SOAP de org A';
    update storage.objects set metadata = '{"pwn":true}'::jsonb
     where name = 'onboarding/11111111-1111-4111-8111-111111111111/drivers/selfie/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1.jpg';
    get diagnostics n = row_count;
    assert n = 0, 'org B actualizó la selfie de org A';
    raise notice 'ORG B (owner): OK — solo sus objetos, incluido el tracto sin organization_id';
end $$;

-- ====================== Autenticado sin org ==========================
select set_config('request.jwt.claims', '{"sub":"51000000-0000-4000-8000-0000000000ff","role":"authenticated"}', false);
do $$
declare n int;
begin
    select count(*) into n from storage.objects;
    assert n = 0, format('usuario sin org ve %s objetos', n);
    assert pg_temp.storage_denied($q$insert into storage.objects(bucket_id, name) values ('fleetops-documents','onboarding/11111111-1111-4111-8111-111111111111/equipment/soap/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5.pdf')$q$),
           'usuario sin org subió un documento de org A';
    raise notice 'SIN ORG: OK — 0 objetos, upload rechazado';
end $$;

reset role;
select set_config('request.jwt.claims', '', false);
