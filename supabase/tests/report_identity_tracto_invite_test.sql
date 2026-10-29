-- Reporte sin identidad, retarget de tracto_id y EXECUTE revocado.
-- Fixtures sintéticos (prefijo e1). Falla en main, sin 20261029020000.
reset role;
select set_config('request.jwt.claims', '', false);

insert into auth.users(id, email) values
 ('e1000000-0000-4000-8000-0000000000a1','sec-a@example.test'),
 ('e1000000-0000-4000-8000-0000000000b1','sec-b@example.test');
insert into public.organizations(id, name, owner_id) values
 ('e100000a-0000-4000-8000-000000000000','Sec Org A','e1000000-0000-4000-8000-0000000000a1'),
 ('e100000b-0000-4000-8000-000000000000','Sec Org B','e1000000-0000-4000-8000-0000000000b1');
insert into public.organization_members(organization_id, user_id, role) values
 ('e100000a-0000-4000-8000-000000000000','e1000000-0000-4000-8000-0000000000a1','owner'),
 ('e100000b-0000-4000-8000-000000000000','e1000000-0000-4000-8000-0000000000b1','owner');
insert into public.tractos(id, patente, organization_id) values
 ('e17a0000-0000-4000-8000-000000000001','SEC0A1','e100000a-0000-4000-8000-000000000000'),
 ('e17a0000-0000-4000-8000-000000000002','SEC0A2','e100000a-0000-4000-8000-000000000000'),
 ('e17b0000-0000-4000-8000-000000000001','SEC0B1','e100000b-0000-4000-8000-000000000000');
insert into public.conductores(id, driver_id, nombre, telefono, rut, tracto_id) values
 ('e1ca0000-0000-4000-8000-000000000001','FLE-E1A1','Conductor Sec A','+56900000091','91.111.111-1','e17a0000-0000-4000-8000-000000000001'),
 ('e1ca0000-0000-4000-8000-000000000002','FLE-E1A2','Conductor Sec A2','+56900000092','92.222.222-2','e17b0000-0000-4000-8000-000000000001');
insert into public.organization_drivers(organization_id, conductor_id, status) values
 ('e100000a-0000-4000-8000-000000000000','e1ca0000-0000-4000-8000-000000000001','ACTIVE'),
 ('e100000a-0000-4000-8000-000000000000','e1ca0000-0000-4000-8000-000000000002','ACTIVE');
insert into public.viajes(id, patente, conductor, conductor_id, empresa, empresa_id, ruta) values
 ('e1fa0000-0000-4000-8000-000000000001','SEC0A1','Conductor Sec A','e1ca0000-0000-4000-8000-000000000001','Sec Org A','e100000a-0000-4000-8000-000000000000','Ruta Sec');

create temp table sec_failures(msg text);
create or replace function pg_temp.sec_fail(p_msg text) returns void
language sql security definer set search_path = pg_temp, pg_catalog as $$
  insert into pg_temp.sec_failures(msg) values (p_msg);
$$;
grant execute on function pg_temp.sec_fail(text) to public;

set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
do $$
declare r record;
begin
  select * into r from public.submit_driver_report(
    'e1fa0000-0000-4000-8000-000000000001', 'Cargando',
    p_patente => 'sec-0a1', p_driver_id => 'fle-e1a1');
  if r.report_id is null or r.conductor <> 'Conductor Sec A' then
    perform pg_temp.sec_fail('reporte con patente y conductor activo no se registró');
  end if;

  begin
    perform public.submit_driver_report(
      'e1fa0000-0000-4000-8000-000000000001', 'Cargando',
      p_patente => 'SEC0A1', p_conductor => 'Fantasma');
    perform pg_temp.sec_fail('reporte sin identidad fue aceptado');
  exception
    when invalid_parameter_value then null;
    when others then perform pg_temp.sec_fail('reporte sin identidad falló con ' || sqlstate);
  end;

  begin
    perform public.submit_driver_report('e1fa0000-0000-4000-8000-000000000001', 'Cargando');
    perform pg_temp.sec_fail('reporte solo con UUID fue aceptado');
  exception
    when invalid_parameter_value then null;
    when others then perform pg_temp.sec_fail('reporte solo con UUID falló con ' || sqlstate);
  end;
end $$;

reset role;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"e1000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$
declare n int; tid uuid;
begin
  select count(*) into n from public.tractos where id = 'e17b0000-0000-4000-8000-000000000001';
  if n <> 1 then
    perform pg_temp.sec_fail('el fixture no hace visible el tracto de la otra org');
  end if;

  update public.conductores set ciudad = 'Calama'
   where id = 'e1ca0000-0000-4000-8000-000000000001';
  get diagnostics n = row_count;
  if n <> 1 then
    perform pg_temp.sec_fail('no pudo editar su conductor');
  end if;

  update public.conductores set tracto_id = 'e17a0000-0000-4000-8000-000000000002'
   where id = 'e1ca0000-0000-4000-8000-000000000001';
  get diagnostics n = row_count;
  if n <> 1 then
    perform pg_temp.sec_fail('retarget a la propia org fue rechazado');
  end if;

  begin
    update public.conductores set tracto_id = 'e17b0000-0000-4000-8000-000000000001'
     where id = 'e1ca0000-0000-4000-8000-000000000001';
    get diagnostics n = row_count;
    perform pg_temp.sec_fail(format('retarget a otra org fue aceptado (%s)', n));
  exception
    when insufficient_privilege then null;
    when others then perform pg_temp.sec_fail('retarget a otra org falló con ' || sqlstate);
  end;

  select tracto_id into tid from public.conductores
   where id = 'e1ca0000-0000-4000-8000-000000000001';
  if tid is distinct from 'e17a0000-0000-4000-8000-000000000002' then
    perform pg_temp.sec_fail('tracto_id quedó en ' || coalesce(tid::text, 'null'));
  end if;
end $$;

reset role;
do $$
declare sig text := 'public.consume_organization_driver_invite(text,text,text,text,text,text,text)';
begin
  if has_function_privilege('public', sig, 'execute') then
    perform pg_temp.sec_fail('PUBLIC ejecuta consume_organization_driver_invite');
  end if;
  if has_function_privilege('anon', sig, 'execute') then
    perform pg_temp.sec_fail('anon ejecuta consume_organization_driver_invite');
  end if;
  if has_function_privilege('authenticated', sig, 'execute') then
    perform pg_temp.sec_fail('authenticated ejecuta consume_organization_driver_invite');
  end if;
end $$;

set role anon;
do $$
begin
  begin
    perform public.consume_organization_driver_invite('x','N','1','9');
    perform pg_temp.sec_fail('anon ejecutó consume_organization_driver_invite');
  exception
    when insufficient_privilege then null;
    when others then perform pg_temp.sec_fail('anon ejecutó consume_organization_driver_invite (' || sqlstate || ')');
  end;
end $$;

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"e1000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$
begin
  begin
    perform public.consume_organization_driver_invite('x','N','1','9');
    perform pg_temp.sec_fail('authenticated ejecutó consume_organization_driver_invite');
  exception
    when insufficient_privilege then null;
    when others then perform pg_temp.sec_fail('authenticated ejecutó consume_organization_driver_invite (' || sqlstate || ')');
  end;
end $$;

reset role;
set role anon;
do $$
begin
  begin
    perform public.finalizar_viaje('SEC0A1'::text);
    perform pg_temp.sec_fail('anon ejecutó finalizar_viaje(text)');
  exception
    when undefined_function then null;
    when insufficient_privilege then
      perform pg_temp.sec_fail('finalizar_viaje(text) sigue definida');
    when others then
      perform pg_temp.sec_fail('finalizar_viaje(text) respondió ' || sqlstate);
  end;
end $$;

reset role;
select set_config('request.jwt.claims', '', false);
do $$
declare s text;
begin
  select string_agg(msg, E'\n' order by msg) into s from sec_failures;
  if s is not null then
    raise exception '%', s;
  end if;
  raise notice 'OK — reporte sin identidad rechazado, tracto de otra org rechazado, consume sin EXECUTE, finalizar_viaje(text) eliminada';
end $$;
