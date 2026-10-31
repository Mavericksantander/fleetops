-- resolve_viaje_public: anon solo datos mínimos de viajes activos; 2 tenants; autenticado sin org.
-- Fixtures propios (prefijo 5x) para no depender de otros tests.
reset role;
select set_config('request.jwt.claims', '', false);
insert into auth.users(id, email) values
 ('00000000-0000-0000-0000-0000000005a1','rv-owner-a@example.test'),
 ('00000000-0000-0000-0000-0000000005b1','rv-owner-b@example.test'),
 ('00000000-0000-0000-0000-0000000005ff','rv-sin-org@example.test');
insert into public.organizations(id, name, owner_id) values
 ('0000005a-0000-0000-0000-000000000000','RV Org A','00000000-0000-0000-0000-0000000005a1'),
 ('0000005b-0000-0000-0000-000000000000','RV Org B','00000000-0000-0000-0000-0000000005b1');
insert into public.organization_members(organization_id, user_id, role) values
 ('0000005a-0000-0000-0000-000000000000','00000000-0000-0000-0000-0000000005a1','owner'),
 ('0000005b-0000-0000-0000-000000000000','00000000-0000-0000-0000-0000000005b1','owner');
insert into public.viajes(id, patente, conductor, empresa, empresa_id, ruta, estado, fecha_finalizacion) values
 ('5a000000-0000-0000-0000-000000000001','RVAA11','Conductor RV A','RV Org A','0000005a-0000-0000-0000-000000000000','Ruta RV A','En ruta', null),
 ('5a000000-0000-0000-0000-000000000002','RVAA12','Conductor RV A2','RV Org A','0000005a-0000-0000-0000-000000000000','Ruta RV A2','Finalizado', now()),
 ('5b000000-0000-0000-0000-000000000001','RVBB11','Conductor RV B','RV Org B','0000005b-0000-0000-0000-000000000000','Ruta RV B','En ruta', null);

do $$ begin
  assert (select prosecdef from pg_proc where oid = 'public.resolve_viaje_public(uuid)'::regprocedure),
         'resolve_viaje_public no es SECURITY DEFINER';
  assert (select proconfig from pg_proc where oid = 'public.resolve_viaje_public(uuid)'::regprocedure) = array['search_path=""'],
         format('search_path inesperado: %s', (select proconfig from pg_proc where oid = 'public.resolve_viaje_public(uuid)'::regprocedure));
end $$;

-- ANON
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ declare r record; n int; begin
  select * into strict r from public.resolve_viaje_public('5a000000-0000-0000-0000-000000000001');
  assert r.id = '5a000000-0000-0000-0000-000000000001', 'anon: id';
  assert r.patente is null and r.conductor is null and r.conductor_id is null, 'anon recibe patente/conductor';
  assert r.empresa_id is null and r.route_id is null, 'anon recibe empresa_id/route_id';
  assert r.empresa = 'RV Org A' and r.ruta = 'Ruta RV A' and r.estado = 'En ruta', 'anon perdió empresa/ruta/estado que usa reportes.html';
  select count(*) into n from public.resolve_viaje_public('5a000000-0000-0000-0000-000000000002');
  assert n = 0, 'anon resuelve un viaje finalizado';
  select count(*) into n from public.resolve_viaje_public('ffffffff-0000-0000-0000-000000000000');
  assert n = 0, 'anon resuelve un UUID inexistente';
  raise notice 'RESOLVE ANON: OK — sin patente/conductor/IDs, solo viajes activos';
end $$;

-- ORG A
reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000005a1","role":"authenticated"}', false);
do $$ declare r record; n int; begin
  select * into strict r from public.resolve_viaje_public('5a000000-0000-0000-0000-000000000001');
  assert r.patente = 'RVAA11' and r.conductor = 'Conductor RV A' and r.empresa_id = '0000005a-0000-0000-0000-000000000000',
         'org A no recibe el detalle de su viaje';
  select count(*) into n from public.resolve_viaje_public('5a000000-0000-0000-0000-000000000002');
  assert n = 1, 'org A no resuelve su viaje finalizado';
  select count(*) into n from public.resolve_viaje_public('5b000000-0000-0000-0000-000000000001');
  assert n = 0, 'org A resuelve un viaje de org B';
  raise notice 'RESOLVE ORG A: OK — detalle propio, nada de org B';
end $$;

-- ORG B
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000005b1","role":"authenticated"}', false);
do $$ declare n int; begin
  select count(*) into n from public.resolve_viaje_public('5a000000-0000-0000-0000-000000000001');
  assert n = 0, 'org B resuelve un viaje de org A';
  select count(*) into n from public.resolve_viaje_public('5b000000-0000-0000-0000-000000000001');
  assert n = 1, 'org B no resuelve su viaje';
  raise notice 'RESOLVE ORG B: OK';
end $$;

-- Autenticado sin org
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000005ff","role":"authenticated"}', false);
do $$ declare n int; begin
  select count(*) into n from public.resolve_viaje_public('5a000000-0000-0000-0000-000000000001');
  assert n = 0, 'usuario sin org resuelve viaje de org A';
  select count(*) into n from public.resolve_viaje_public('5b000000-0000-0000-0000-000000000001');
  assert n = 0, 'usuario sin org resuelve viaje de org B';
  raise notice 'RESOLVE SIN ORG: OK — 0 filas';
end $$;

reset role;
select set_config('request.jwt.claims', '', false);
