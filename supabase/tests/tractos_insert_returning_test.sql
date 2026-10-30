-- INSERT ... RETURNING en tractos (PostgREST return=representation), dos tenants + sin acceso.
-- Con la política SELECT previa (solo can_access_tracto) el RETURNING falla con 42501: este
-- test FALLA sin 20261029030000_tractos_select_returning.sql.
reset role;
select set_config('request.jwt.claims', '', false);
insert into auth.users(id, email) values
 ('94000000-0000-4000-8000-0000000000a1','rr-a@example.test'),
 ('94000000-0000-4000-8000-0000000000a3','rr-a-op@example.test'),
 ('94000000-0000-4000-8000-0000000000a4','rr-a-view@example.test'),
 ('94000000-0000-4000-8000-0000000000b1','rr-b@example.test'),
 ('94000000-0000-4000-8000-0000000000c1','rr-none@example.test');
insert into public.organizations(id, name, owner_id) values
 ('9400000a-0000-4000-8000-000000000000','RR A','94000000-0000-4000-8000-0000000000a1'),
 ('9400000b-0000-4000-8000-000000000000','RR B','94000000-0000-4000-8000-0000000000b1');
insert into public.organization_members(organization_id, user_id, role) values
 ('9400000a-0000-4000-8000-000000000000','94000000-0000-4000-8000-0000000000a1','owner'),
 ('9400000a-0000-4000-8000-000000000000','94000000-0000-4000-8000-0000000000a3','operator'),
 ('9400000a-0000-4000-8000-000000000000','94000000-0000-4000-8000-0000000000a4','viewer'),
 ('9400000b-0000-4000-8000-000000000000','94000000-0000-4000-8000-0000000000b1','owner');

create temp table rr_log (label text primary key, result text not null);
grant select, insert on table rr_log to public;

-- Ejecuta p_sql como authenticated con los claims del usuario (simula PostgREST).
create or replace function pg_temp.rr_as(p_label text, p_user uuid, p_sql text) returns void
language plpgsql as $$
declare n int; r text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    execute p_sql into r;
    get diagnostics n = row_count;
    r := 'ok rows=' || n || coalesce(' val=' || r, '');
  exception when others then
    r := sqlstate || ' ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  insert into rr_log values (p_label, r);
end $$;

select pg_temp.rr_as('a_owner_returning','94000000-0000-4000-8000-0000000000a1',
  $q$insert into public.tractos(patente, organization_id) values ('RRA001','9400000a-0000-4000-8000-000000000000') returning patente$q$);
select pg_temp.rr_as('a_operator_returning','94000000-0000-4000-8000-0000000000a3',
  $q$insert into public.tractos(patente, organization_id) values ('RRA002','9400000a-0000-4000-8000-000000000000') returning patente$q$);
select pg_temp.rr_as('a_viewer_returning','94000000-0000-4000-8000-0000000000a4',
  $q$insert into public.tractos(patente, organization_id) values ('RRA003','9400000a-0000-4000-8000-000000000000') returning patente$q$);
select pg_temp.rr_as('b_owner_returning_own','94000000-0000-4000-8000-0000000000b1',
  $q$insert into public.tractos(patente, organization_id) values ('RRB001','9400000b-0000-4000-8000-000000000000') returning patente$q$);
select pg_temp.rr_as('b_owner_into_a','94000000-0000-4000-8000-0000000000b1',
  $q$insert into public.tractos(patente, organization_id) values ('RRX001','9400000a-0000-4000-8000-000000000000') returning patente$q$);
select pg_temp.rr_as('none_into_a','94000000-0000-4000-8000-0000000000c1',
  $q$insert into public.tractos(patente, organization_id) values ('RRX002','9400000a-0000-4000-8000-000000000000') returning patente$q$);
select pg_temp.rr_as('a_owner_sees','94000000-0000-4000-8000-0000000000a1',
  $q$select count(*)::text from public.tractos where patente like 'RR%'$q$);
select pg_temp.rr_as('a_viewer_sees','94000000-0000-4000-8000-0000000000a4',
  $q$select count(*)::text from public.tractos where patente like 'RR%'$q$);
select pg_temp.rr_as('b_sees_a','94000000-0000-4000-8000-0000000000b1',
  $q$select count(*)::text from public.tractos where organization_id = '9400000a-0000-4000-8000-000000000000'$q$);
select pg_temp.rr_as('b_sees_total','94000000-0000-4000-8000-0000000000b1',
  $q$select count(*)::text from public.tractos where patente like 'RR%'$q$);
select pg_temp.rr_as('none_sees','94000000-0000-4000-8000-0000000000c1',
  $q$select count(*)::text from public.tractos$q$);

do $$
declare r record; bad text := ''; exp jsonb := jsonb_build_object(
  'a_owner_returning',     'ok rows=1 val=RRA001',
  'a_operator_returning',  'ok rows=1 val=RRA002',
  'a_viewer_returning',    '42501',
  'b_owner_returning_own', 'ok rows=1 val=RRB001',
  'b_owner_into_a',        '42501',
  'none_into_a',           '42501',
  'a_owner_sees',          'ok rows=1 val=2',
  'a_viewer_sees',         'ok rows=1 val=2',
  'b_sees_a',              'ok rows=1 val=0',
  'b_sees_total',          'ok rows=1 val=1',
  'none_sees',             'ok rows=1 val=0');
begin
  for r in select * from rr_log order by label loop
    raise notice 'RR % -> %', r.label, r.result;
    if r.result not like (exp->>r.label) || '%' then bad := bad || r.label || '; '; end if;
  end loop;
  if (select count(*) from rr_log) <> 11 then bad := bad || 'faltan casos; '; end if;
  if bad <> '' then raise exception 'TRACTOS RETURNING: FALLA en %', bad; end if;
  raise notice 'TRACTOS RETURNING: OK — owner/operator RETURNING pasa; viewer, otro tenant y sin acceso 42501; B ve 0 de A; sin acceso ve 0';
end $$;
