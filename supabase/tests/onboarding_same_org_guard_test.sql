-- Una invitación sin usar no reescribe un conductor de la misma org ni
-- reasigna su tracto, y el alta exige documentos de licencia y de equipo.
reset role;
select set_config('request.jwt.claims', '', false);

insert into auth.users(id, email) values
 ('82000000-0000-4000-8000-0000000000a1','same-org-a@example.test');
insert into public.organizations(id, name, owner_id) values
 ('8200000a-0000-4000-8000-000000000000','Org Same','82000000-0000-4000-8000-0000000000a1');
insert into public.organization_members(organization_id, user_id, role) values
 ('8200000a-0000-4000-8000-000000000000','82000000-0000-4000-8000-0000000000a1','owner');
insert into public.tractos(id, patente, estado, organization_id) values
 ('82a10000-0000-4000-8000-000000000001','SAME01','Ocupado', null),
 ('82a10000-0000-4000-8000-000000000002','ORGPLT','Disponible','8200000a-0000-4000-8000-000000000000'),
 ('82a10000-0000-4000-8000-000000000003','FREE01','Ocupado', null);
insert into public.conductores(
    id, nombre, telefono, rut, licencia, tipo_licencia, ciudad,
    patente_habitual, estado, tracto_id, licencia_vencimiento
) values
 ('82cb0000-0000-4000-8000-000000000001','Conductor Original','+56982000001','83333333-3',
  'LIC-ORIGINAL','A5','Calama','SAME01','Ocupado','82a10000-0000-4000-8000-000000000001','2030-01-01'),
 ('82cb0000-0000-4000-8000-000000000002','Sin Org','+56982000002','87777777-7',
  null, null, 'Iquique', null, 'Disponible', null, null);
insert into public.organization_drivers(organization_id, conductor_id, status) values
 ('8200000a-0000-4000-8000-000000000000','82cb0000-0000-4000-8000-000000000001','ACTIVE');
insert into public.organization_driver_invites(organization_id, token_hash, expires_at, created_by)
select '8200000a-0000-4000-8000-000000000000',
       encode(extensions.digest(t, 'sha256'), 'hex'),
       now() + interval '1 day',
       '82000000-0000-4000-8000-0000000000a1'
  from unnest(array[
      'same-org-rut','same-org-plate','same-org-orgplate',
      'missing-docs','partial-docs','new-driver','unlinked-plate','unlinked-rut'
  ]) t;

create temp table same_org_log (
    label text primary key,
    result text not null
);
grant select, insert, update, delete on table same_org_log to public;

create or replace function pg_temp.same_org_err(p_sql text) returns text
language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $$;
grant execute on function pg_temp.same_org_err(text) to public;

create or replace function pg_temp.onboarding_docs(p_token text)
returns table(conductor jsonb, tracto jsonb)
language plpgsql
security definer
set search_path = public, extensions, pg_catalog
as $$
declare
  h text := encode(digest(p_token, 'sha256'), 'hex');
begin
  conductor := jsonb_build_array(
    jsonb_build_object('tipo_documento','licencia_frente','storage_path','onboarding/' || h || '/drivers/frente/82000000-0000-4000-8000-000000000001.jpg','mime_type','image/jpeg','tamano_bytes','10'),
    jsonb_build_object('tipo_documento','licencia_reverso','storage_path','onboarding/' || h || '/drivers/reverso/82000000-0000-4000-8000-000000000002.jpg','mime_type','image/jpeg','tamano_bytes','10'),
    jsonb_build_object('tipo_documento','selfie','storage_path','onboarding/' || h || '/drivers/selfie/82000000-0000-4000-8000-000000000003.jpg','mime_type','image/jpeg','tamano_bytes','10')
  );
  tracto := jsonb_build_array(
    jsonb_build_object('tipo_documento','permiso_circulacion','storage_path','onboarding/' || h || '/equipment/permiso-circulacion/82000000-0000-4000-8000-000000000004.pdf','mime_type','application/pdf','tamano_bytes','10'),
    jsonb_build_object('tipo_documento','soap','storage_path','onboarding/' || h || '/equipment/soap/82000000-0000-4000-8000-000000000005.pdf','mime_type','application/pdf','tamano_bytes','10'),
    jsonb_build_object('tipo_documento','revision_tecnica','storage_path','onboarding/' || h || '/equipment/revision-tecnica/82000000-0000-4000-8000-000000000006.pdf','mime_type','application/pdf','tamano_bytes','10'),
    jsonb_build_object('tipo_documento','padron_vehicular','storage_path','onboarding/' || h || '/equipment/padron/82000000-0000-4000-8000-000000000007.pdf','mime_type','application/pdf','tamano_bytes','10')
  );
  return next;
end $$;
grant execute on function pg_temp.onboarding_docs(text) to public;

create or replace function pg_temp.same_org_call(p_token text, p_nombre text, p_rut text, p_telefono text, p_patente text, p_conductor jsonb, p_tracto jsonb)
returns text language sql as $$
  select pg_temp.same_org_err(format(
    'select public.complete_organization_driver_onboarding(%L,%L,%L,%L,%L,%L,%L,%L,%L,%L::jsonb,%L::jsonb)',
    p_token, p_nombre, p_rut, p_telefono, 'Santiago', 'B', 'LIC-HACK',
    current_date + 10, p_patente, p_conductor::text, p_tracto::text
  ))
$$;
grant execute on function pg_temp.same_org_call(text, text, text, text, text, jsonb, jsonb) to public;

set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);

insert into same_org_log(label, result)
select 'rut', pg_temp.same_org_call(
    'same-org-rut','Intruso','83333333-3','+56982000011','NEW001', docs.conductor, docs.tracto)
  from pg_temp.onboarding_docs('same-org-rut') docs
union all
select 'plate', pg_temp.same_org_call(
    'same-org-plate','Otro','84444444-4','+56982000012','SAME01', docs.conductor, docs.tracto)
  from pg_temp.onboarding_docs('same-org-plate') docs
union all
select 'orgplate', pg_temp.same_org_call(
    'same-org-orgplate','Otro','84444444-5','+56982000013','ORGPLT', docs.conductor, docs.tracto)
  from pg_temp.onboarding_docs('same-org-orgplate') docs
union all
select 'missing', pg_temp.same_org_call(
    'missing-docs','Nuevo','85555555-5','+56982000014','MISS01','[]'::jsonb,'[]'::jsonb)
union all
select 'partial', pg_temp.same_org_call(
    'partial-docs','Nuevo','85555555-6','+56982000015','PART01',
    jsonb_build_array(jsonb_build_object(
        'tipo_documento','licencia_frente',
        'storage_path','onboarding/' || encode(extensions.digest('partial-docs','sha256'),'hex') || '/drivers/frente/82000000-0000-4000-8000-000000000001.jpg')),
    jsonb_build_array(jsonb_build_object(
        'tipo_documento','permiso_circulacion',
        'storage_path','onboarding/' || encode(extensions.digest('partial-docs','sha256'),'hex') || '/equipment/permiso-circulacion/82000000-0000-4000-8000-000000000004.pdf')))
union all
select 'new', pg_temp.same_org_call(
    'new-driver','Nuevo','86666666-6','+56982000016','NEW003', docs.conductor, docs.tracto)
  from pg_temp.onboarding_docs('new-driver') docs
union all
select 'free-plate', pg_temp.same_org_call(
    'unlinked-plate','Libre','86666666-7','+56982000017','FREE01', docs.conductor, docs.tracto)
  from pg_temp.onboarding_docs('unlinked-plate') docs
union all
select 'free-rut', pg_temp.same_org_call(
    'unlinked-rut','Actualizado','87777777-7','+56982000018','NEW004', docs.conductor, docs.tracto)
  from pg_temp.onboarding_docs('unlinked-rut') docs;

reset role;
select set_config('request.jwt.claims', '', false);

do $$
declare
  r text;
  snap text;
  n int;
begin
  select result into r from same_org_log where label = 'rut';
  assert r = '42501 El RUT ya está registrado en esta empresa.', format('S1 RUT misma org = %s', r);
  select format('%s|%s|%s|%s|%s|%s|%s', nombre, telefono, licencia, tipo_licencia, ciudad, estado, patente_habitual)
    into snap
    from public.conductores
   where id = '82cb0000-0000-4000-8000-000000000001';
  assert snap = 'Conductor Original|+56982000001|LIC-ORIGINAL|A5|Calama|Ocupado|SAME01',
    format('S1 reescribió al conductor: %s', snap);
  assert (select licencia_vencimiento from public.conductores where id = '82cb0000-0000-4000-8000-000000000001') = date '2030-01-01',
    'S1 cambió el vencimiento';
  assert (select tracto_id from public.conductores where id = '82cb0000-0000-4000-8000-000000000001')
      = '82a10000-0000-4000-8000-000000000001',
    'S1 reasignó el tracto del conductor';
  assert not exists (select 1 from public.tractos where patente = 'NEW001'), 'S1 creó NEW001';
  assert (select count(*) from public.conductor_documentos where conductor_id = '82cb0000-0000-4000-8000-000000000001') = 0,
    'S1 insertó documentos';
  assert (select consumed_at from public.organization_driver_invites
           where token_hash = encode(extensions.digest('same-org-rut','sha256'),'hex')) is null,
    'S1 consumió la invitación';

  select result into r from same_org_log where label = 'plate';
  assert r = '42501 La patente ya está registrada en esta empresa.', format('S2 patente misma org = %s', r);
  assert not exists (select 1 from public.conductores where rut = '84444444-4'), 'S2 creó conductor';
  assert (select estado from public.tractos where patente = 'SAME01') = 'Ocupado', 'S2 cambió el estado del tracto';
  assert (select consumed_at from public.organization_driver_invites
           where token_hash = encode(extensions.digest('same-org-plate','sha256'),'hex')) is null,
    'S2 consumió la invitación';

  select result into r from same_org_log where label = 'orgplate';
  assert r = '42501 La patente ya está registrada en esta empresa.', format('S3 patente por organization_id = %s', r);
  assert not exists (select 1 from public.conductores where rut = '84444444-5'), 'S3 creó conductor';
  assert not exists (
      select 1 from public.conductores where tracto_id = '82a10000-0000-4000-8000-000000000002'
  ), 'S3 reasignó ORGPLT';

  select result into r from same_org_log where label = 'missing';
  assert r = 'P0001 Faltan documentos de licencia o de equipo.', format('S4 sin documentos = %s', r);
  assert not exists (select 1 from public.conductores where rut = '85555555-5'), 'S4 creó conductor';
  assert not exists (select 1 from public.tractos where patente = 'MISS01'), 'S4 creó tracto';

  select result into r from same_org_log where label = 'partial';
  assert r = 'P0001 Faltan documentos de licencia o de equipo.', format('S5 documentos parciales = %s', r);
  assert not exists (select 1 from public.conductores where rut = '85555555-6'), 'S5 creó conductor';

  select result into r from same_org_log where label = 'new';
  assert r = 'ok', format('S6 alta nueva = %s', r);
  select count(*) into n from public.conductor_documentos d
    join public.conductores c on c.id = d.conductor_id
   where c.rut = '86666666-6';
  assert n = 3, format('S6 documentos de licencia = %s', n);
  select count(*) into n from public.tracto_documentos d
    join public.tractos t on t.id = d.tracto_id
   where t.patente = 'NEW003';
  assert n = 4, format('S6 documentos de equipo = %s', n);
  assert (select consumed_at from public.organization_driver_invites
           where token_hash = encode(extensions.digest('new-driver','sha256'),'hex')) is not null,
    'S6 no consumió la invitación';

  select result into r from same_org_log where label = 'free-plate';
  assert r = 'ok', format('S7 patente sin org = %s', r);
  assert (select c.tracto_id from public.conductores c where c.rut = '86666666-7')
      = '82a10000-0000-4000-8000-000000000003',
    'S7 no asoció FREE01';
  assert (select estado from public.tractos where patente = 'FREE01') = 'Disponible',
    'S7 no dejó disponible el tracto sin org';

  select result into r from same_org_log where label = 'free-rut';
  assert r = 'ok', format('S8 RUT sin org = %s', r);
  select format('%s|%s|%s', nombre, telefono, licencia) into snap
    from public.conductores where id = '82cb0000-0000-4000-8000-000000000002';
  assert snap = 'Actualizado|+56982000018|LIC-HACK', format('S8 no actualizó el RUT sin org: %s', snap);

  raise notice 'S1-S8: OK — misma org se rechaza sin escribir; sin documentos no hay alta; RUT o patente sin vínculo siguen el alta';
end $$;
