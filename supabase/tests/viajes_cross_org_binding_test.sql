-- V1: la org A no puede crear ni editar viajes con conductor o ruta de la org B,
-- y un viaje no le da acceso al conductor de B.
reset role;
select set_config('request.jwt.claims', '', false);

insert into auth.users(id, email) values
 ('82000000-0000-4000-8000-0000000000a1','viajes-a@example.test'),
 ('82000000-0000-4000-8000-0000000000b1','viajes-b@example.test');
insert into public.organizations(id, name, owner_id) values
 ('8200000a-0000-4000-8000-000000000000','Org Viajes A','82000000-0000-4000-8000-0000000000a1'),
 ('8200000b-0000-4000-8000-000000000000','Org Viajes B','82000000-0000-4000-8000-0000000000b1');
insert into public.organization_members(organization_id, user_id, role) values
 ('8200000a-0000-4000-8000-000000000000','82000000-0000-4000-8000-0000000000a1','owner'),
 ('8200000b-0000-4000-8000-000000000000','82000000-0000-4000-8000-0000000000b1','owner');
insert into public.conductores(id, nombre, telefono) values
 ('82ca0000-0000-4000-8000-000000000000','Conductor A','+56900000001'),
 ('82cb0000-0000-4000-8000-000000000000','Conductor B','+56900000002');
insert into public.organization_drivers(organization_id, conductor_id, status) values
 ('8200000a-0000-4000-8000-000000000000','82ca0000-0000-4000-8000-000000000000','ACTIVE'),
 ('8200000b-0000-4000-8000-000000000000','82cb0000-0000-4000-8000-000000000000','ACTIVE');
insert into public.routes(id, organization_id, name) values
 ('82a10000-0000-4000-8000-000000000000','8200000a-0000-4000-8000-000000000000','Ruta A'),
 ('82b10000-0000-4000-8000-000000000000','8200000b-0000-4000-8000-000000000000','Ruta B');
insert into public.conductor_documentos(conductor_id, tipo_documento, storage_path) values
 ('82cb0000-0000-4000-8000-000000000000','licencia_frente','viajes-b/licencia.jpg');
insert into storage.objects(bucket_id, name) values ('fleetops-documents','viajes-b/licencia.jpg');
-- Viaje cruzado preexistente (como el que deja la política anterior): empresa A, conductor B.
insert into public.viajes(id, patente, empresa_id, conductor_id) values
 ('82f00000-0000-4000-8000-000000000000','VXOLD1','8200000a-0000-4000-8000-000000000000','82cb0000-0000-4000-8000-000000000000');

create or replace function pg_temp.v1_sqlstate(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then return sqlstate;
end $$;
grant execute on function pg_temp.v1_sqlstate(text) to public;

create or replace function pg_temp.v1_sees_b() returns text language sql as $$
  select format('%s conductor(es), %s documento(s), %s objeto(s), %s viaje(s) nuevos con ruta B',
    (select count(*) from public.conductores where id = '82cb0000-0000-4000-8000-000000000000'),
    (select count(*) from public.conductor_documentos where conductor_id = '82cb0000-0000-4000-8000-000000000000'),
    (select count(*) from storage.objects where name = 'viajes-b/licencia.jpg'),
    (select count(*) from public.viajes where route_id = '82b10000-0000-4000-8000-000000000000'))
$$;
grant execute on function pg_temp.v1_sees_b() to public;

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"82000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$
declare r text;
begin
  -- Negativos: viaje con conductor o ruta de B (insert y update).
  r := pg_temp.v1_sqlstate($q$insert into public.viajes(patente, empresa_id, conductor_id) values ('VX0001','8200000a-0000-4000-8000-000000000000','82cb0000-0000-4000-8000-000000000000')$q$);
  assert r = '42501', format('V1: insert empresa A + conductor B = %s', r);
  r := pg_temp.v1_sqlstate($q$insert into public.viajes(patente, empresa_id, route_id) values ('VX0002','8200000a-0000-4000-8000-000000000000','82b10000-0000-4000-8000-000000000000')$q$);
  assert r = '42501', format('V1: insert empresa A + ruta B = %s', r);
  r := pg_temp.v1_sqlstate($q$insert into public.viajes(patente, route_id, conductor_id) values ('VX0003','82a10000-0000-4000-8000-000000000000','82cb0000-0000-4000-8000-000000000000')$q$);
  assert r = '42501', format('V1: insert ruta A + conductor B = %s', r);

  -- Positivo: viaje legítimo de A (como conductores.js: empresa, ruta y conductor de A).
  r := pg_temp.v1_sqlstate($q$insert into public.viajes(id, patente, empresa_id, route_id, conductor_id) values ('82f0000a-0000-4000-8000-000000000000','VXA001','8200000a-0000-4000-8000-000000000000','82a10000-0000-4000-8000-000000000000','82ca0000-0000-4000-8000-000000000000')$q$);
  assert r = 'ok', format('V1: viaje legítimo de A = %s', r);
  r := pg_temp.v1_sqlstate($q$update public.viajes set estado = 'EN RUTA' where id = '82f0000a-0000-4000-8000-000000000000'$q$);
  assert r = 'ok', format('V1: update legítimo de A = %s', r);
  assert (select count(*) from public.conductores where id = '82ca0000-0000-4000-8000-000000000000') = 1,
    'V1: A no ve a su propio conductor';

  r := pg_temp.v1_sqlstate($q$update public.viajes set conductor_id = '82cb0000-0000-4000-8000-000000000000' where id = '82f0000a-0000-4000-8000-000000000000'$q$);
  assert r = '42501', format('V1: update a conductor B = %s', r);
  r := pg_temp.v1_sqlstate($q$update public.viajes set route_id = '82b10000-0000-4000-8000-000000000000' where id = '82f0000a-0000-4000-8000-000000000000'$q$);
  assert r = '42501', format('V1: update a ruta B = %s', r);

  -- El viaje cruzado preexistente ya no prueba la pertenencia del conductor B.
  assert pg_temp.v1_sees_b() = '0 conductor(es), 0 documento(s), 0 objeto(s), 0 viaje(s) nuevos con ruta B',
    'V1: org A ve ' || pg_temp.v1_sees_b();
  raise notice 'V1: OK — A no crea ni edita viajes con datos de B y no ve al conductor de B';
end $$;

-- Control: B sí ve a su conductor, su documento y su objeto (los datos existen).
select set_config('request.jwt.claims', '{"sub":"82000000-0000-4000-8000-0000000000b1","role":"authenticated"}', false);
do $$
begin
  assert pg_temp.v1_sees_b() = '1 conductor(es), 1 documento(s), 1 objeto(s), 0 viaje(s) nuevos con ruta B',
    'V1 control: org B ve ' || pg_temp.v1_sees_b();
  raise notice 'V1 control: OK — B ve sus propios datos';
end $$;

reset role;
select set_config('request.jwt.claims', '', false);
