-- Trigger conductores_tracto_org con dos tenants (A y B):
-- alta por invitación válida pasa; tracto de OTRA org se rechaza (42501) sin
-- sesión (ruta SECURITY DEFINER) y como usuario autenticado del otro tenant;
-- un usuario sin acceso no cambia el tracto.
reset role;
select set_config('request.jwt.claims', '', false);

insert into auth.users(id, email) values
 ('93000000-0000-4000-8000-0000000000a1','tt-a@example.test'),
 ('93000000-0000-4000-8000-0000000000b1','tt-b@example.test'),
 ('93000000-0000-4000-8000-0000000000c1','tt-none@example.test');
insert into public.organizations(id, name, owner_id) values
 ('9300000a-0000-4000-8000-000000000000','TT A','93000000-0000-4000-8000-0000000000a1'),
 ('9300000b-0000-4000-8000-000000000000','TT B','93000000-0000-4000-8000-0000000000b1');
insert into public.organization_members(organization_id, user_id, role) values
 ('9300000a-0000-4000-8000-000000000000','93000000-0000-4000-8000-0000000000a1','owner'),
 ('9300000b-0000-4000-8000-000000000000','93000000-0000-4000-8000-0000000000b1','owner');
insert into public.tractos(id, patente, estado, organization_id) values
 ('93a10000-0000-4000-8000-000000000001','TTA001','Disponible','9300000a-0000-4000-8000-000000000000'),
 ('93a10000-0000-4000-8000-000000000002','TTA002','Disponible','9300000a-0000-4000-8000-000000000000'),
 ('93b10000-0000-4000-8000-000000000001','TTB001','Disponible','9300000b-0000-4000-8000-000000000000');
insert into public.conductores(id, nombre, telefono, rut, estado, tracto_id) values
 ('93ca0000-0000-4000-8000-000000000001','Cond A','+56993000001','93111111-1','Disponible','93a10000-0000-4000-8000-000000000001'),
 ('93cb0000-0000-4000-8000-000000000001','Cond B','+56993000002','93222222-2','Disponible','93b10000-0000-4000-8000-000000000001');
insert into public.organization_drivers(organization_id, conductor_id, status) values
 ('9300000a-0000-4000-8000-000000000000','93ca0000-0000-4000-8000-000000000001','ACTIVE'),
 ('9300000b-0000-4000-8000-000000000000','93cb0000-0000-4000-8000-000000000001','ACTIVE');
insert into public.organization_driver_invites(organization_id, token_hash, expires_at, created_by)
select '9300000a-0000-4000-8000-000000000000', encode(extensions.digest(t, 'sha256'), 'hex'),
       now() + interval '1 day', '93000000-0000-4000-8000-0000000000a1'
  from unnest(array['tt-ok','tt-plate-b']) t;

create temp table tt_log (label text primary key, result text not null);
grant select, insert, update, delete on table tt_log to public;

create or replace function pg_temp.tt_err(p_sql text) returns text
language plpgsql as $$
declare n int;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return 'ok rows=' || n;
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $$;
grant execute on function pg_temp.tt_err(text) to public;

-- Ruta interna SECURITY DEFINER sin sesión (dueño postgres).
create or replace function pg_temp.tt_definer(p_conductor uuid, p_tracto uuid) returns text
language plpgsql security definer set search_path = public, pg_catalog as $$
begin
  return pg_temp.tt_err(format('update public.conductores set tracto_id = %L where id = %L', p_tracto, p_conductor));
end $$;
grant execute on function pg_temp.tt_definer(uuid, uuid) to public;

create or replace function pg_temp.tt_onboard(p_token text, p_rut text, p_tel text, p_patente text) returns text
language plpgsql set search_path = public, extensions, pg_catalog as $$
declare h text := encode(digest(p_token, 'sha256'), 'hex');
begin
  return pg_temp.tt_err(format(
    'select public.complete_organization_driver_onboarding(%L,%L,%L,%L,%L,%L,%L,%L,%L,%L::jsonb,%L::jsonb)',
    p_token, 'Nuevo TT', p_rut, p_tel, 'Santiago', 'B', 'LIC-TT', current_date + 10, p_patente,
    jsonb_build_array(
      jsonb_build_object('tipo_documento','licencia_frente','storage_path','onboarding/'||h||'/drivers/frente/93000000-0000-4000-8000-000000000001.jpg','mime_type','image/jpeg','tamano_bytes','10'),
      jsonb_build_object('tipo_documento','licencia_reverso','storage_path','onboarding/'||h||'/drivers/reverso/93000000-0000-4000-8000-000000000002.jpg','mime_type','image/jpeg','tamano_bytes','10'),
      jsonb_build_object('tipo_documento','selfie','storage_path','onboarding/'||h||'/drivers/selfie/93000000-0000-4000-8000-000000000003.jpg','mime_type','image/jpeg','tamano_bytes','10'))::text,
    jsonb_build_array(
      jsonb_build_object('tipo_documento','permiso_circulacion','storage_path','onboarding/'||h||'/equipment/permiso-circulacion/93000000-0000-4000-8000-000000000004.pdf','mime_type','application/pdf','tamano_bytes','10'),
      jsonb_build_object('tipo_documento','soap','storage_path','onboarding/'||h||'/equipment/soap/93000000-0000-4000-8000-000000000005.pdf','mime_type','application/pdf','tamano_bytes','10'),
      jsonb_build_object('tipo_documento','revision_tecnica','storage_path','onboarding/'||h||'/equipment/revision-tecnica/93000000-0000-4000-8000-000000000006.pdf','mime_type','application/pdf','tamano_bytes','10'),
      jsonb_build_object('tipo_documento','padron_vehicular','storage_path','onboarding/'||h||'/equipment/padron/93000000-0000-4000-8000-000000000007.pdf','mime_type','application/pdf','tamano_bytes','10'))::text));
end $$;
-- El RPC se ejecuta con el rol de la sesión (anon).
create or replace function pg_temp.tt_onboard_sql(p_token text, p_rut text, p_tel text, p_patente text) returns text
language sql as $$ select pg_temp.tt_onboard(p_token, p_rut, p_tel, p_patente) $$;
grant execute on function pg_temp.tt_onboard(text,text,text,text), pg_temp.tt_onboard_sql(text,text,text,text) to public;

-- Sin sesión (anon): alta válida y alta con patente de la org B.
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
insert into tt_log values
 ('onboard_ok',      pg_temp.tt_onboard_sql('tt-ok','93333333-3','+56993000003','TTNEW1')),
 ('onboard_plate_b', pg_temp.tt_onboard_sql('tt-plate-b','93444444-4','+56993000004','TTB001')),
 ('anon_direct_b',   pg_temp.tt_err($q$update public.conductores set tracto_id='93b10000-0000-4000-8000-000000000001' where id='93ca0000-0000-4000-8000-000000000001'$q$));

-- Sin sesión, ruta SECURITY DEFINER: conductor A -> tracto B (cross-org) y A -> A.
reset role;
select set_config('request.jwt.claims', '', false);
insert into tt_log values
 ('definer_cross',  pg_temp.tt_definer('93ca0000-0000-4000-8000-000000000001','93b10000-0000-4000-8000-000000000001')),
 ('definer_own',    pg_temp.tt_definer('93ca0000-0000-4000-8000-000000000001','93a10000-0000-4000-8000-000000000002'));
update public.conductores set tracto_id = '93a10000-0000-4000-8000-000000000001' where id = '93ca0000-0000-4000-8000-000000000001';

-- Autenticado del tenant B: su conductor -> tracto de A; y owner A -> tracto de B.
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"93000000-0000-4000-8000-0000000000b1","role":"authenticated"}', false);
insert into tt_log values
 ('auth_b_to_a', pg_temp.tt_err($q$update public.conductores set tracto_id='93a10000-0000-4000-8000-000000000002' where id='93cb0000-0000-4000-8000-000000000001'$q$)),
 ('auth_b_on_a', pg_temp.tt_err($q$update public.conductores set tracto_id='93b10000-0000-4000-8000-000000000001' where id='93ca0000-0000-4000-8000-000000000001'$q$));
select set_config('request.jwt.claims', '{"sub":"93000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
insert into tt_log values
 ('auth_a_to_b',  pg_temp.tt_err($q$update public.conductores set tracto_id='93b10000-0000-4000-8000-000000000001' where id='93ca0000-0000-4000-8000-000000000001'$q$)),
 ('auth_a_own',   pg_temp.tt_err($q$update public.conductores set tracto_id='93a10000-0000-4000-8000-000000000002' where id='93ca0000-0000-4000-8000-000000000001'$q$));
-- Autenticado sin org.
select set_config('request.jwt.claims', '{"sub":"93000000-0000-4000-8000-0000000000c1","role":"authenticated"}', false);
insert into tt_log values
 ('auth_none',    pg_temp.tt_err($q$update public.conductores set tracto_id='93a10000-0000-4000-8000-000000000001' where id='93ca0000-0000-4000-8000-000000000001'$q$));

reset role;
select set_config('request.jwt.claims', '', false);
do $$
declare r text; bad text := '';
  procedure_ok boolean;
begin
  for r in select label || ' => ' || result from tt_log order by label loop
    raise notice '%', r;
  end loop;
  select result into r from tt_log where label='onboard_ok';
  if r not like 'ok%' then bad := bad || ' onboard_ok=' || r; end if;
  if (select c.tracto_id from public.conductores c where c.rut='93333333-3')
     is distinct from (select id from public.tractos where patente='TTNEW1') then bad := bad || ' onboard_ok sin tracto'; end if;
  select result into r from tt_log where label='onboard_plate_b';
  if r not like '42501%' then bad := bad || ' onboard_plate_b=' || r; end if;
  select result into r from tt_log where label='anon_direct_b';
  if r not like '42501%' then bad := bad || ' anon_direct_b=' || r; end if;
  select result into r from tt_log where label='definer_cross';
  if r not like '42501%' then bad := bad || ' definer_cross=' || r; end if;
  select result into r from tt_log where label='definer_own';
  if r <> 'ok rows=1' then bad := bad || ' definer_own=' || r; end if;
  select result into r from tt_log where label='auth_b_to_a';
  if r not like '42501%' then bad := bad || ' auth_b_to_a=' || r; end if;
  select result into r from tt_log where label='auth_b_on_a';
  if r not like '42501%' and r <> 'ok rows=0' then bad := bad || ' auth_b_on_a=' || r; end if;
  select result into r from tt_log where label='auth_a_to_b';
  if r not like '42501%' then bad := bad || ' auth_a_to_b=' || r; end if;
  select result into r from tt_log where label='auth_a_own';
  if r <> 'ok rows=1' then bad := bad || ' auth_a_own=' || r; end if;
  select result into r from tt_log where label='auth_none';
  if r not like '42501%' and r <> 'ok rows=0' then bad := bad || ' auth_none=' || r; end if;
  if (select tracto_id from public.conductores where id='93cb0000-0000-4000-8000-000000000001') <> '93b10000-0000-4000-8000-000000000001'
     then bad := bad || ' conductor B cambió de tracto'; end if;
  if (select tracto_id from public.conductores where id='93ca0000-0000-4000-8000-000000000001') <> '93a10000-0000-4000-8000-000000000002'
     then bad := bad || ' conductor A no quedó en TTA002'; end if;
  if bad <> '' then raise exception 'TRACTO 2 TENANTS FALLA:%', bad; end if;
  raise notice 'TRACTO 2 TENANTS: OK — alta por invitación pasa; cross-org 42501 sin sesión (definer) y autenticado; sin acceso no cambia';
end $$;
