-- G1-G3: una invitación de la org A no da acceso a un conductor de la org B.
reset role;
select set_config('request.jwt.claims', '', false);

insert into auth.users(id, email) values
 ('81000000-0000-4000-8000-0000000000a1','binding-a@example.test'),
 ('81000000-0000-4000-8000-0000000000b1','binding-b@example.test');
insert into public.organizations(id, name, owner_id) values
 ('8100000a-0000-4000-8000-000000000000','Org Binding A','81000000-0000-4000-8000-0000000000a1'),
 ('8100000b-0000-4000-8000-000000000000','Org Binding B','81000000-0000-4000-8000-0000000000b1');
insert into public.organization_members(organization_id, user_id, role) values
 ('8100000a-0000-4000-8000-000000000000','81000000-0000-4000-8000-0000000000a1','owner'),
 ('8100000b-0000-4000-8000-000000000000','81000000-0000-4000-8000-0000000000b1','owner');
insert into public.conductores(id, nombre, telefono, rut) values
 ('81cb0000-0000-4000-8000-000000000000','Conductor B','+56900000000','81111111-1');
insert into public.organization_drivers(organization_id, conductor_id, status) values
 ('8100000b-0000-4000-8000-000000000000','81cb0000-0000-4000-8000-000000000000','ACTIVE');
insert into public.conductor_documentos(conductor_id, tipo_documento, storage_path) values
 ('81cb0000-0000-4000-8000-000000000000','licencia_frente','binding-b/licencia.jpg');
insert into storage.objects(bucket_id, name) values ('fleetops-documents','binding-b/licencia.jpg');
insert into public.organization_driver_invites(organization_id, token_hash, expires_at, created_by)
select '8100000a-0000-4000-8000-000000000000', encode(extensions.digest(t, 'sha256'), 'hex'),
       now() + interval '1 day', '81000000-0000-4000-8000-0000000000a1'
  from unnest(array['binding-a-1','binding-a-2','binding-a-3']) t;
insert into public.organization_driver_invites(organization_id, token_hash, expires_at, created_by) values
 ('8100000b-0000-4000-8000-000000000000', encode(extensions.digest('binding-b-1', 'sha256'), 'hex'),
  now() + interval '1 day', '81000000-0000-4000-8000-0000000000b1');

create or replace function pg_temp.binding_sqlstate(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then return sqlstate;
end $$;
grant execute on function pg_temp.binding_sqlstate(text) to public;

create or replace function pg_temp.org_a_sees_b() returns text language sql as $$
  select format('%s objeto(s), %s conductor(es)',
    (select count(*) from storage.objects where name = 'binding-b/licencia.jpg'),
    (select count(*) from public.conductores where id = '81cb0000-0000-4000-8000-000000000000'))
$$;
grant execute on function pg_temp.org_a_sees_b() to public;

set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$
declare
  hb text := encode(extensions.digest('binding-b-1', 'sha256'), 'hex');
  r text;
begin
  r := pg_temp.binding_sqlstate($q$select public.complete_organization_driver_onboarding('binding-a-1','Atacante','81111111-1','+569','S','A5','L',current_date + 1,'BIND01','[]','[]')$q$);
  assert r = '42501', format('G1: onboarding con RUT de otra org = %s', r);

  r := pg_temp.binding_sqlstate(format($q$select public.complete_organization_driver_onboarding('binding-a-2','N','82222222-2','+569','S','A5','L',current_date + 1,'BIND02',%L::jsonb,'[]')$q$,
    json_build_array(json_build_object('tipo_documento','licencia_frente','storage_path',
      'onboarding/' || hb || '/drivers/frente/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1.jpg'))::text));
  assert r <> 'ok', 'G2: la invitación de A registró un path de la invitación de B';

  r := pg_temp.binding_sqlstate($q$select public.consume_organization_driver_invite('binding-a-3','X','81111111-1','+569')$q$);
  assert r = '42501', format('G3: anon ejecuta consume_organization_driver_invite (%s)', r);
  raise notice 'G1/G2: OK — onboarding anon no toma el RUT de otra org ni paths de otra invitación';
end $$;

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"81000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$
declare r text;
begin
  r := pg_temp.binding_sqlstate($q$select public.consume_organization_driver_invite('binding-a-3','Atacante','81111111-1','+569')$q$);
  assert r = '42501', format('G3: consume con RUT de otra org = %s', r);
  assert pg_temp.org_a_sees_b() = '0 objeto(s), 0 conductor(es)', 'G3: org A ve ' || pg_temp.org_a_sees_b();
  raise notice 'G3: OK — consume_organization_driver_invite no toma el RUT de otra org';
end $$;

reset role;
select set_config('request.jwt.claims', '', false);
