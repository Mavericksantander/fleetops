-- Policies de anon en fleetops-documents y EXECUTE de private.
-- Corre después de las migraciones, en la misma BD que el test de Storage.
reset role;
select set_config('request.jwt.claims', '', false);
select set_config('storage.operation', '', false);

insert into auth.users(id, email) values
 ('61000000-0000-4000-8000-0000000000a1','anon-storage-a@example.test'),
 ('61000000-0000-4000-8000-0000000000b1','anon-storage-b@example.test');
insert into public.organizations(id, name, owner_id) values
 ('6100000a-0000-4000-8000-000000000000','Org Anon A','61000000-0000-4000-8000-0000000000a1'),
 ('6100000b-0000-4000-8000-000000000000','Org Anon B','61000000-0000-4000-8000-0000000000b1');
insert into public.organization_members(organization_id, user_id, role) values
 ('6100000a-0000-4000-8000-000000000000','61000000-0000-4000-8000-0000000000a1','owner'),
 ('6100000b-0000-4000-8000-000000000000','61000000-0000-4000-8000-0000000000b1','owner');
insert into public.conductores(id, nombre, telefono) values
 ('61ca0000-0000-4000-8000-000000000000','Conductor Anon A','+56933333333');
insert into public.organization_drivers(organization_id, conductor_id, status) values
 ('6100000a-0000-4000-8000-000000000000','61ca0000-0000-4000-8000-000000000000','ACTIVE');

-- 64 hex. El de A está vigente; el consumido y el vencido no sirven para subir.
insert into public.organization_driver_invites(organization_id, token_hash, expires_at, created_by) values
 ('6100000a-0000-4000-8000-000000000000', repeat('a', 64), now() + interval '1 day', '61000000-0000-4000-8000-0000000000a1'),
 ('6100000a-0000-4000-8000-000000000000', repeat('c', 64), now() + interval '1 day', '61000000-0000-4000-8000-0000000000a1'),
 ('6100000a-0000-4000-8000-000000000000', repeat('e', 64), now() - interval '1 day', '61000000-0000-4000-8000-0000000000a1'),
 ('6100000b-0000-4000-8000-000000000000', repeat('b', 64), now() + interval '1 day', '61000000-0000-4000-8000-0000000000b1');
update public.organization_driver_invites
   set consumed_at = now()
 where token_hash = repeat('c', 64);

insert into public.conductor_documentos(conductor_id, tipo_documento, storage_path) values
 ('61ca0000-0000-4000-8000-000000000000','licencia_frente',
  'onboarding/' || repeat('a', 64) || '/drivers/frente/eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1.jpg');
insert into storage.objects(bucket_id, name) values
 ('fleetops-documents','onboarding/' || repeat('a', 64) || '/drivers/frente/eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1.jpg'),
 ('fleetops-documents','onboarding/' || repeat('a', 64) || '/drivers/selfie/dddddddd-dddd-4ddd-8ddd-ddddddddddd1.jpg'),
 ('fleetops-documents','onboarding/' || repeat('b', 64) || '/drivers/selfie/ffffffff-ffff-4fff-8fff-fffffffffff1.jpg'),
 ('fleetops-documents','legacy/no-invite.jpg');

create or replace function private.probe_default_execute() returns int language sql as $$ select 1 $$;

create or replace function pg_temp.anon_denied(p_sql text) returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when insufficient_privilege then return true;
end $$;
grant execute on function pg_temp.anon_denied(text) to public;

create or replace function pg_temp.anon_sqlstate(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then return sqlstate;
end $$;
grant execute on function pg_temp.anon_sqlstate(text) to public;

do $$
declare n int;
begin
  select count(*) into n from pg_policy
   where polrelid = 'storage.objects'::regclass
     and polname = 'fleetops_documents_org_read';
  assert n = 0, 'fleetops_documents_org_read sigue creada';

  select count(*) into n from pg_policy
   where polrelid = 'storage.objects'::regclass
     and polname in (
       'fleetops_documents_anon_invite_insert',
       'fleetops_documents_anon_invite_delete',
       'fleetops_documents_anon_invite_delete_read');
  assert n = 3, format('policies anon de storage = %s', n);

  assert has_function_privilege('anon', 'private.driver_invite_may_upload(text)', 'execute'),
         'anon no ejecuta driver_invite_may_upload';
  assert not has_function_privilege('authenticated', 'private.driver_invite_may_upload(text)', 'execute'),
         'authenticated ejecuta driver_invite_may_upload';
  assert not has_function_privilege('anon', 'private.can_access_document_path(text, text[])', 'execute'),
         'anon ejecuta can_access_document_path';
  assert has_function_privilege('authenticated', 'private.can_access_document_path(text, text[])', 'execute'),
         'authenticated no ejecuta can_access_document_path';
  assert not has_function_privilege('anon', 'private.probe_default_execute()', 'execute'),
         'anon ejecuta una función nueva de private';
  assert not has_function_privilege('public', 'private.probe_default_execute()', 'execute'),
         'public ejecuta una función nueva de private';
  assert has_function_privilege('anon', 'public.resolve_viaje_public(uuid)', 'execute'),
         'anon perdió resolve_viaje_public';
  assert has_function_privilege('anon', 'public.submit_driver_report(uuid,text,text,text,text,text,text,text,double precision,double precision,double precision,text,text)', 'execute'),
         'anon perdió submit_driver_report';
  assert has_function_privilege('anon', 'public.resolve_organization_driver_invite(text)', 'execute'),
         'anon perdió resolve_organization_driver_invite';
  assert has_function_privilege('anon', 'public.complete_organization_driver_onboarding(text,text,text,text,text,text,text,date,text,jsonb,jsonb)', 'execute'),
         'anon perdió complete_organization_driver_onboarding';
  assert has_function_privilege('anon', 'public.get_member_invite_context(text)', 'execute'),
         'anon perdió get_member_invite_context';
  assert has_function_privilege('anon', 'public.get_customer_member_invite_context(text)', 'execute'),
         'anon perdió get_customer_member_invite_context';
  assert not has_function_privilege('anon', 'public.create_member_invite(text,text)', 'execute'),
         'anon ejecuta create_member_invite';
  raise notice 'PRIVILEGIOS: OK — anon solo ejecuta driver_invite_may_upload en private; los RPC públicos de la demo siguen';
end $$;

drop function private.probe_default_execute();

-- El miembro lee el path registrado y no el objeto suelto del prefijo.
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"61000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$
declare n int;
begin
  select count(*) into n from storage.objects
   where name = 'onboarding/' || repeat('a', 64) || '/drivers/frente/eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1.jpg';
  assert n = 1, 'el dueño no lee el documento registrado';
  select count(*) into n from storage.objects
   where name = 'onboarding/' || repeat('a', 64) || '/drivers/selfie/dddddddd-dddd-4ddd-8ddd-ddddddddddd1.jpg';
  assert n = 0, 'el dueño lee un objeto de la invitación sin fila de documento';
  select count(*) into n from storage.objects
   where name = 'onboarding/' || repeat('b', 64) || '/drivers/selfie/ffffffff-ffff-4fff-8fff-fffffffffff1.jpg';
  assert n = 0, 'org A lee el objeto de la invitación de org B';
  raise notice 'ORG READ: OK — path registrado sí, prefijo de invitación sin fila no';
end $$;

select set_config('request.jwt.claims', '{"sub":"61000000-0000-4000-8000-0000000000b1","role":"authenticated"}', false);
do $$
declare n int;
begin
  select count(*) into n from storage.objects
   where name like 'onboarding/' || repeat('b', 64) || '/%'
      or name like 'onboarding/' || repeat('a', 64) || '/%';
  assert n = 0, format('org B ve %s objetos de onboarding', n);
  raise notice 'ORG B: OK — sin fila de documento no lee ni su prefijo';
end $$;

reset role;
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$
declare n int; v_id uuid;
begin
  select count(*) into n from storage.objects;
  assert n = 0, format('anon ve %s objetos', n);

  insert into storage.objects(bucket_id, name) values
   ('fleetops-documents','onboarding/' || repeat('a', 64) || '/drivers/reverso/11111111-1111-4111-8111-111111111111.jpg');
  select count(*) into n from storage.objects
   where name like '%/reverso/%';
  assert n = 0, 'anon lee el objeto que acaba de subir';

  perform set_config('storage.operation', 'storage.object.delete_many', true);
  select count(*) into n from storage.objects
   where name like '%/reverso/%';
  assert n = 1, 'la policy de DELETE RETURNING no deja ver el objeto';
  perform set_config('storage.operation', '', true);
  select count(*) into n from storage.objects where name like '%/reverso/%';
  assert n = 0, 'anon sigue leyendo después de limpiar storage.operation';

  update storage.objects set metadata = '{"pwn":true}'::jsonb
   where name like '%/reverso/%';
  get diagnostics n = row_count;
  assert n = 0, 'anon actualizó un objeto';

  perform set_config('storage.operation', 'object.delete_many', true);
  delete from storage.objects
   where name = 'onboarding/' || repeat('a', 64) || '/drivers/reverso/11111111-1111-4111-8111-111111111111.jpg'
   returning id into v_id;
  assert v_id is not null, 'el DELETE RETURNING de anon no devolvió la fila';

  delete from storage.objects where name = 'legacy/no-invite.jpg';
  get diagnostics n = row_count;
  assert n = 0, 'anon borró un objeto fuera de una invitación vigente';

  assert pg_temp.anon_sqlstate($q$insert into storage.objects(bucket_id, name) values ('fleetops-documents','onboarding/' || repeat('c', 64) || '/drivers/selfie/22222222-2222-4222-8222-222222222222.jpg')$q$) = '42501',
         'anon subió con invitación consumida';
  assert pg_temp.anon_sqlstate($q$insert into storage.objects(bucket_id, name) values ('fleetops-documents','onboarding/' || repeat('e', 64) || '/drivers/selfie/33333333-3333-4333-8333-333333333333.jpg')$q$) = '42501',
         'anon subió con invitación vencida';
  assert pg_temp.anon_sqlstate($q$insert into storage.objects(bucket_id, name) values ('fleetops-documents','onboarding/' || repeat('a', 64) || '/../selfie/44444444-4444-4444-8444-444444444444.jpg')$q$) = '42501',
         'anon subió un path con ..';
  assert pg_temp.anon_sqlstate($q$insert into storage.objects(bucket_id, name) values ('other-bucket','onboarding/' || repeat('a', 64) || '/drivers/selfie/55555555-5555-4555-8555-555555555555.jpg')$q$) = '42501',
         'anon subió a otro bucket';
  assert pg_temp.anon_denied($q$select private.can_access_document_path('x', array['owner'])$q$),
         'anon ejecuta can_access_document_path';
  assert private.driver_invite_may_upload('onboarding/' || repeat('a', 64) || '/drivers/selfie/66666666-6666-4666-8666-666666666666.jpg'),
         'driver_invite_may_upload rechazó un path vigente';
  assert not private.driver_invite_may_upload('onboarding/' || repeat('c', 64) || '/drivers/selfie/66666666-6666-4666-8666-666666666666.jpg'),
         'driver_invite_may_upload aceptó una invitación consumida';
  raise notice 'ANON STORAGE: OK — sube y borra solo la invitación vigente; no lee, no lista y no pisa';
end $$;

reset role;
select set_config('request.jwt.claims', '', false);
select set_config('storage.operation', '', false);
