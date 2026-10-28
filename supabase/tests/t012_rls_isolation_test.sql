-- =====================================================================
-- T-012 · Pruebas de aislamiento RLS (SQL plano, sin pgTAP).
-- Corre SOLO en una BD local/desechable: crea fixtures ficticios.
-- Cada bloque lanza EXCEPTION si una aserción falla.
-- =====================================================================
reset role;
select set_config('request.jwt.claims', '', false);

-- Fixtures (ficticios) -------------------------------------------------
insert into auth.users(id, email) values
 ('00000000-0000-0000-0000-0000000000a1','owner-a@example.test'),
 ('00000000-0000-0000-0000-0000000000a2','viewer-a@example.test'),
 ('00000000-0000-0000-0000-0000000000b1','owner-b@example.test');
insert into public.organizations(id, name, owner_id) values
 ('0000000a-0000-0000-0000-000000000000','Org A','00000000-0000-0000-0000-0000000000a1'),
 ('0000000b-0000-0000-0000-000000000000','Org B','00000000-0000-0000-0000-0000000000b1');
insert into public.organization_members(organization_id, user_id, role) values
 ('0000000a-0000-0000-0000-000000000000','00000000-0000-0000-0000-0000000000a1','owner'),
 ('0000000a-0000-0000-0000-000000000000','00000000-0000-0000-0000-0000000000a2','viewer'),
 ('0000000b-0000-0000-0000-000000000000','00000000-0000-0000-0000-0000000000b1','owner');
insert into public.tractos(id, patente, organization_id) values
 ('7a000000-0000-0000-0000-000000000000','AAAA11','0000000a-0000-0000-0000-000000000000'),
 ('7b000000-0000-0000-0000-000000000000','BBBB22', null);           -- legado sin org (como el onboarding)
insert into public.conductores(id, driver_id, nombre, telefono, rut, tracto_id) values
 ('ca000000-0000-0000-0000-000000000000','FLE-A001','Conductor A','+56 9 1111 1111','11.111.111-1','7a000000-0000-0000-0000-000000000000'),
 ('cb000000-0000-0000-0000-000000000000','FLE-B001','Conductor B','+56 9 2222 2222','22.222.222-2','7b000000-0000-0000-0000-000000000000');
insert into public.organization_drivers(organization_id, conductor_id, status) values
 ('0000000a-0000-0000-0000-000000000000','ca000000-0000-0000-0000-000000000000','ACTIVE'),
 ('0000000b-0000-0000-0000-000000000000','cb000000-0000-0000-0000-000000000000','ACTIVE');
insert into public.conductor_documentos(conductor_id, tipo_documento, storage_path) values
 ('ca000000-0000-0000-0000-000000000000','selfie','a/selfie.jpg'),
 ('cb000000-0000-0000-0000-000000000000','selfie','b/selfie.jpg');
insert into public.tracto_documentos(tracto_id, tipo_documento, storage_path) values
 ('7a000000-0000-0000-0000-000000000000','padron_vehicular','a/padron.pdf'),
 ('7b000000-0000-0000-0000-000000000000','padron_vehicular','b/padron.pdf');
insert into public.viajes(id, patente, conductor, conductor_id, empresa, empresa_id, ruta) values
 ('fa000000-0000-0000-0000-000000000000','AAAA11','Conductor A','ca000000-0000-0000-0000-000000000000','Org A','0000000a-0000-0000-0000-000000000000','Ruta A'),
 ('fb000000-0000-0000-0000-000000000000','BBBB22','Conductor B','cb000000-0000-0000-0000-000000000000','Org B','0000000b-0000-0000-0000-000000000000','Ruta B');
insert into public.customers(id, organization_id, name) values
 ('c0000000-0000-0000-0000-00000000000a','0000000a-0000-0000-0000-000000000000','Cliente A');
insert into public.reportes(conductor, conductor_id, patente, empresa, ruta, estado, latitud, longitud, viaje_id) values
 ('Conductor A','ca000000-0000-0000-0000-000000000000','AAAA11','Org A','Ruta A','En ruta',-23.6,-70.4,'fa000000-0000-0000-0000-000000000000'),
 ('Conductor B','cb000000-0000-0000-0000-000000000000','BBBB22','Org B','Ruta B','En ruta',-24.1,-70.2,'fb000000-0000-0000-0000-000000000000');

-- Helper: ¿el rol actual puede ejecutar la sentencia? ------------------
create or replace function pg_temp.denied(p_sql text) returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when insufficient_privilege then return true;
end $$;
grant execute on function pg_temp.denied(text) to public;

-- ============================ ANON ===================================
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$ begin
  assert pg_temp.denied('select 1 from public.conductores limit 1'), 'anon puede leer conductores';
  assert pg_temp.denied('select 1 from public.reportes limit 1'),    'anon puede leer reportes';
  assert pg_temp.denied($q$insert into public.reportes(conductor,patente,empresa,ruta,estado) values ('x','X','x','x','En ruta')$q$),
         'anon puede insertar reportes directo';
  assert pg_temp.denied('select 1 from public.tractos limit 1'),     'anon puede leer tractos';
  assert pg_temp.denied('select public.create_member_invite(''00000000-0000-0000-0000-000000000000''::uuid,''x@example.test'',''admin'')'), 'anon ejecuta create_member_invite';
  assert pg_temp.denied('select public.list_fleetops_platform_organizations()'), 'anon ejecuta list_fleetops_platform_organizations';
  assert pg_temp.denied('select public.finalizar_viaje(''AAAA11''::text)'), 'anon ejecuta finalizar_viaje(text)';
  assert pg_temp.denied('select public.user_has_org_role(null, array[''owner''])'), 'anon ejecuta user_has_org_role';
  raise notice 'ANON: OK — sin lectura de conductores/reportes/tractos, sin insert directo, sin RPC internas';
end $$;
-- Flujo público que debe seguir funcionando
do $$ declare n int; r record; begin
  select count(*) into n from public.resolve_viaje_public('fa000000-0000-0000-0000-000000000000');
  assert n = 1, 'anon ya no resuelve el viaje del QR';
  select * into r from public.submit_driver_report('fa000000-0000-0000-0000-000000000000','Cargando',
         p_patente => 'aaaa-11', p_driver_id => 'fle-a001', p_latitud => -23.5, p_longitud => -70.3);
  assert r.report_id is not null and r.conductor = 'Conductor A', 'submit_driver_report no registró el reporte';
  -- Driver ID de otra organización: rechazado
  begin
    perform public.submit_driver_report('fa000000-0000-0000-0000-000000000000','Cargando', p_driver_id => 'FLE-B001');
    assert false, 'aceptó un Driver ID de otra organización';
  exception when invalid_parameter_value then null; end;
  -- Patente distinta a la del viaje: rechazado
  begin
    perform public.submit_driver_report('fa000000-0000-0000-0000-000000000000','Cargando', p_patente => 'ZZZZ99', p_driver_id => 'FLE-A001');
    assert false, 'aceptó patente distinta a la del viaje';
  exception when invalid_parameter_value then null; end;
  -- UUID inexistente: rechazado
  begin
    perform public.submit_driver_report('ffffffff-0000-0000-0000-000000000000','Cargando', p_conductor => 'x');
    assert false, 'aceptó viaje inexistente';
  exception when invalid_parameter_value then null; end;
  select count(*) into n from public.resolve_organization_driver_invite('token-invalido');
  assert n = 0, 'resolve_organization_driver_invite devolvió algo con token inválido';
  raise notice 'ANON: OK — QR (resolve_viaje_public) y submit_driver_report funcionan con validación de viaje/patente/org';
end $$;

-- ===================== USUARIO ORG A (owner) =========================
reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', false);
do $$ declare n int; begin
  select count(*) into n from public.conductores where id = 'cb000000-0000-0000-0000-000000000000';
  assert n = 0, 'org A ve conductor de org B';
  select count(*) into n from public.conductores where id = 'ca000000-0000-0000-0000-000000000000';
  assert n = 1, 'org A no ve su propio conductor';
  select count(*) into n from public.reportes where viaje_id = 'fb000000-0000-0000-0000-000000000000';
  assert n = 0, 'org A ve reportes de org B';
  select count(*) into n from public.reportes where viaje_id = 'fa000000-0000-0000-0000-000000000000';
  assert n = 2, format('org A debería ver 2 reportes propios, ve %s', n);
  select count(*) into n from public.tractos where id = '7b000000-0000-0000-0000-000000000000';
  assert n = 0, 'org A ve tracto de org B';
  select count(*) into n from public.tractos where id = '7a000000-0000-0000-0000-000000000000';
  assert n = 1, 'org A no ve su tracto';
  select count(*) into n from public.conductor_documentos where conductor_id = 'cb000000-0000-0000-0000-000000000000';
  assert n = 0, 'org A ve documentos de conductor de org B';
  select count(*) into n from public.tracto_documentos where tracto_id = '7b000000-0000-0000-0000-000000000000';
  assert n = 0, 'org A ve documentos de tracto de org B';
  select count(*) into n from public.conductor_documentos; assert n = 1, 'org A: conductor_documentos <> 1';
  select count(*) into n from public.tracto_documentos;    assert n = 1, 'org A: tracto_documentos <> 1';
  -- Escrituras cruzadas: 0 filas afectadas / rechazadas
  update public.tractos set estado = 'Inactivo' where id = '7b000000-0000-0000-0000-000000000000';
  get diagnostics n = row_count; assert n = 0, 'org A modificó tracto de org B';
  delete from public.tracto_documentos where tracto_id = '7b000000-0000-0000-0000-000000000000';
  get diagnostics n = row_count; assert n = 0, 'org A borró documentos de org B';
  update public.conductores set ciudad = 'X' where id = 'cb000000-0000-0000-0000-000000000000';
  get diagnostics n = row_count; assert n = 0, 'org A modificó conductor de org B';
  begin
    insert into public.reportes(conductor,patente,empresa,ruta,estado,viaje_id)
    values ('x','BBBB22','x','x','En ruta','fb000000-0000-0000-0000-000000000000');
    assert false, 'org A insertó reporte en viaje de org B';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.tractos(patente, organization_id) values ('CCCC33','0000000b-0000-0000-0000-000000000000');
    assert false, 'org A creó tracto en org B';
  exception when insufficient_privilege then null; end;
  -- Escrituras propias permitidas
  insert into public.reportes(conductor,patente,empresa,ruta,estado,viaje_id)
  values ('Torre A','AAAA11','Org A','Ruta A','En ruta','fa000000-0000-0000-0000-000000000000');
  update public.conductores set ciudad = 'Antofagasta' where id = 'ca000000-0000-0000-0000-000000000000';
  get diagnostics n = row_count; assert n = 1, 'org A no puede editar su conductor';
  select count(*) into n from public.viajes where id = 'fb000000-0000-0000-0000-000000000000';
  assert n = 0, 'org A ve viaje de org B';
  select count(*) into n from public.organizations where id = '0000000b-0000-0000-0000-000000000000';
  assert n = 0, 'org A ve la organización B';
  raise notice 'ORG A (owner): OK — ve solo lo suyo, no lee ni escribe datos de org B';
end $$;

-- ===================== USUARIO ORG A (viewer) ========================
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}', false);
do $$ declare n int; begin
  select count(*) into n from public.conductores; assert n = 1, 'viewer A: conductores <> 1';
  update public.tractos set estado = 'Inactivo' where id = '7a000000-0000-0000-0000-000000000000';
  get diagnostics n = row_count; assert n = 0, 'viewer pudo modificar tracto';
  begin
    insert into public.reportes(conductor,patente,empresa,ruta,estado,viaje_id)
    values ('x','AAAA11','x','x','En ruta','fa000000-0000-0000-0000-000000000000');
    assert false, 'viewer insertó reporte';
  exception when insufficient_privilege then null; end;
  raise notice 'ORG A (viewer): OK — solo lectura de su org';
end $$;

-- ===================== USUARIO ORG B (owner) =========================
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', false);
do $$ declare n int; begin
  select count(*) into n from public.conductores;           assert n = 1, 'org B: conductores <> 1';
  select count(*) into n from public.reportes;              assert n = 1, format('org B: reportes = %s (esperado 1)', n);
  select count(*) into n from public.tractos;               assert n = 1, 'org B: tractos <> 1 (tracto legado vía conductor)';
  select count(*) into n from public.conductor_documentos;  assert n = 1, 'org B: conductor_documentos <> 1';
  select count(*) into n from public.tracto_documentos;     assert n = 1, 'org B: tracto_documentos <> 1';
  select count(*) into n from public.reportes where viaje_id = 'fa000000-0000-0000-0000-000000000000';
  assert n = 0, 'org B ve reportes de org A';
  select count(*) into n from public.viajes where id = 'fa000000-0000-0000-0000-000000000000';
  assert n = 0, 'org B ve viaje de org A';
  raise notice 'ORG B (owner): OK — no ve datos de org A';
end $$;

-- ====================== Autenticado sin org ==========================
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000ff","role":"authenticated"}', false);
do $$ declare n int; begin
  select (select count(*) from public.conductores) + (select count(*) from public.reportes)
       + (select count(*) from public.tractos) + (select count(*) from public.conductor_documentos)
       + (select count(*) from public.tracto_documentos) into n;
  assert n = 0, format('usuario sin organización ve %s filas', n);
  select (select count(*) from public.viajes) + (select count(*) from public.organizations)
       + (select count(*) from public.organization_members) + (select count(*) from public.customers) into n;
  assert n = 0, format('usuario sin organización ve %s filas en viajes/organizations/members/customers', n);
  update public.viajes set ruta = 'X';
  get diagnostics n = row_count; assert n = 0, 'usuario sin organización modificó viajes';
  raise notice 'SIN ORG: OK — 0 filas en conductores/reportes/tractos/documentos/viajes/organizations/customers';
end $$;

reset role;
select set_config('request.jwt.claims', '', false);
