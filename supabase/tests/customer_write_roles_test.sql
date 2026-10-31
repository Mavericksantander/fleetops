-- Escritura de customers y customer_operation_access: solo owner y admin.
-- Control negativo: el operator cumple user_has_org_role(..., owner, admin,
-- operator) y no cumple owner/admin. El INSERT trae organization_id y, en
-- accesos, customer_id y route_id: el WITH CHECK de la policy que incluía
-- operator. Si el fixture no arma ese operator, el control falla a propósito.
reset role;
select set_config('request.jwt.claims', '', false);

insert into auth.users(id, email) values
 ('83000000-0000-4000-8000-000000000001','cust-owner@example.test'),
 ('83000000-0000-4000-8000-000000000002','cust-admin@example.test'),
 ('83000000-0000-4000-8000-000000000003','cust-operator@example.test');
insert into public.organizations(id, name, owner_id) values
 ('8300000a-0000-4000-8000-000000000001','Org Clientes','83000000-0000-4000-8000-000000000001');
insert into public.organization_members(organization_id, user_id, role) values
 ('8300000a-0000-4000-8000-000000000001','83000000-0000-4000-8000-000000000001','owner'),
 ('8300000a-0000-4000-8000-000000000001','83000000-0000-4000-8000-000000000002','admin'),
 ('8300000a-0000-4000-8000-000000000001','83000000-0000-4000-8000-000000000003','operator');
insert into public.customers(id, organization_id, name) values
 ('8300000c-0000-4000-8000-000000000001','8300000a-0000-4000-8000-000000000001','Cliente Semilla');
insert into public.routes(id, organization_id, name) values
 ('8300000d-0000-4000-8000-000000000001','8300000a-0000-4000-8000-000000000001','Ruta Semilla'),
 ('8300000d-0000-4000-8000-000000000002','8300000a-0000-4000-8000-000000000001','Ruta Libre');
insert into public.customer_operation_access(id, organization_id, customer_id, route_id) values
 ('8300000e-0000-4000-8000-000000000001','8300000a-0000-4000-8000-000000000001','8300000c-0000-4000-8000-000000000001','8300000d-0000-4000-8000-000000000001');

create or replace function pg_temp.write_sqlstate(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then
  return sqlstate;
end $$;
grant execute on function pg_temp.write_sqlstate(text) to public;

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"83000000-0000-4000-8000-000000000003","role":"authenticated"}', false);
do $$
declare
  v_org uuid := '8300000a-0000-4000-8000-000000000001';
  v_operator uuid := '83000000-0000-4000-8000-000000000003';
  v_customer uuid := '8300000c-0000-4000-8000-000000000001';
  v_access uuid := '8300000e-0000-4000-8000-000000000001';
  r text;
  n int;
  v_name text;
  v_active boolean;
begin
  assert auth.uid() = v_operator, 'auth.uid() del operator no es el esperado';
  assert not public.user_has_org_role(v_org, array['owner', 'admin']),
         'control negativo inválido: el operator cuenta como owner o admin';
  assert public.user_has_org_role(v_org, array['owner', 'admin', 'operator']),
         'control negativo inválido: el operator no cumple la policy que incluía operator';
  raise notice 'CONTROL: OK — el operator cumple owner/admin/operator y no es owner ni admin';

  r := pg_temp.write_sqlstate($q$
    insert into public.customers(id, organization_id, name)
    values ('8300000c-0000-4000-8000-000000000099','8300000a-0000-4000-8000-000000000001','Cliente del operator')
  $q$);
  assert r = '42501', format('operator INSERT customers = %s', r);
  assert not exists (
    select 1 from public.customers where id = '8300000c-0000-4000-8000-000000000099'
  ), 'el INSERT del operator creó el cliente';

  update public.customers
     set name = 'Cliente Semilla reescrito'
   where id = v_customer;
  get diagnostics n = row_count;
  assert n = 0, format('operator UPDATE customers afectó %s filas', n);
  select name into v_name from public.customers where id = v_customer;
  assert v_name = 'Cliente Semilla', format('el cliente semilla quedó como %s', v_name);

  delete from public.customers where id = v_customer;
  get diagnostics n = row_count;
  assert n = 0, format('operator DELETE customers afectó %s filas', n);
  assert exists (select 1 from public.customers where id = v_customer),
         'el operator borró el cliente semilla';

  select count(*) into n from public.customers where organization_id = v_org;
  assert n = 1, format('el operator lee %s clientes; la policy de lectura cambió', n);

  r := pg_temp.write_sqlstate($q$
    insert into public.customer_operation_access(id, organization_id, customer_id, route_id)
    values ('8300000e-0000-4000-8000-000000000099','8300000a-0000-4000-8000-000000000001',
            '8300000c-0000-4000-8000-000000000001','8300000d-0000-4000-8000-000000000002')
  $q$);
  assert r = '42501', format('operator INSERT customer_operation_access = %s', r);
  assert not exists (
    select 1 from public.customer_operation_access where id = '8300000e-0000-4000-8000-000000000099'
  ), 'el INSERT del operator creó el acceso';

  update public.customer_operation_access
     set active = false
   where id = v_access;
  get diagnostics n = row_count;
  assert n = 0, format('operator UPDATE customer_operation_access afectó %s filas', n);
  select active into v_active from public.customer_operation_access where id = v_access;
  assert v_active, 'el operator revocó el acceso semilla';

  delete from public.customer_operation_access where id = v_access;
  get diagnostics n = row_count;
  assert n = 0, format('operator DELETE customer_operation_access afectó %s filas', n);
  assert exists (select 1 from public.customer_operation_access where id = v_access),
         'el operator borró el acceso semilla';

  select count(*) into n from public.customer_operation_access where organization_id = v_org;
  assert n = 1, format('el operator lee %s accesos; la policy de lectura cambió', n);
  raise notice 'OPERATOR: OK — INSERT 42501; UPDATE y DELETE no tocan filas; la lectura sigue';
end $$;

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"83000000-0000-4000-8000-000000000002","role":"authenticated"}', false);
do $$
declare
  v_org uuid := '8300000a-0000-4000-8000-000000000001';
  v_admin uuid := '83000000-0000-4000-8000-000000000002';
  v_customer uuid;
  v_access uuid;
  n int;
  v_active boolean;
begin
  assert auth.uid() = v_admin, 'auth.uid() del admin no es el esperado';
  assert public.user_has_org_role(v_org, array['owner', 'admin']),
         'el admin no cumple user_has_org_role owner/admin';

  insert into public.customers(organization_id, name)
  values (v_org, 'Cliente Admin')
  returning id into v_customer;
  get diagnostics n = row_count;
  assert n = 1, 'el admin no insertó el cliente';

  update public.customers set is_active = false where id = v_customer;
  get diagnostics n = row_count;
  assert n = 1, 'el admin no actualizó el cliente';
  assert exists (
    select 1 from public.customers where id = v_customer and is_active = false
  ), 'el cliente del admin sigue activo';

  insert into public.customer_operation_access(organization_id, customer_id, route_id)
  values (v_org, '8300000c-0000-4000-8000-000000000001', '8300000d-0000-4000-8000-000000000002')
  returning id into v_access;
  get diagnostics n = row_count;
  assert n = 1, 'el admin no insertó el acceso';

  update public.customer_operation_access set active = false where id = v_access;
  get diagnostics n = row_count;
  assert n = 1, 'el admin no revocó el acceso';
  select active into v_active from public.customer_operation_access where id = v_access;
  assert v_active = false, 'el acceso del admin sigue activo';

  delete from public.customer_operation_access where id = v_access;
  get diagnostics n = row_count;
  assert n = 1, 'el admin no borró el acceso';
  delete from public.customers where id = v_customer;
  get diagnostics n = row_count;
  assert n = 1, 'el admin no borró el cliente';
  raise notice 'ADMIN: OK — INSERT, UPDATE y DELETE en customers y customer_operation_access';
end $$;

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"83000000-0000-4000-8000-000000000001","role":"authenticated"}', false);
do $$
declare
  v_org uuid := '8300000a-0000-4000-8000-000000000001';
  v_owner uuid := '83000000-0000-4000-8000-000000000001';
  v_customer uuid;
  v_access uuid;
  n int;
  v_name text;
begin
  assert auth.uid() = v_owner, 'auth.uid() del owner no es el esperado';
  assert public.user_has_org_role(v_org, array['owner', 'admin']),
         'el owner no cumple user_has_org_role owner/admin';

  insert into public.customers(organization_id, name)
  values (v_org, 'Cliente Owner')
  returning id into v_customer;
  get diagnostics n = row_count;
  assert n = 1, 'el owner no insertó el cliente';

  update public.customers set name = 'Cliente Owner renombrado' where id = v_customer;
  get diagnostics n = row_count;
  assert n = 1, 'el owner no actualizó el cliente';
  select name into v_name from public.customers where id = v_customer;
  assert v_name = 'Cliente Owner renombrado', format('el cliente del owner quedó como %s', v_name);

  insert into public.customer_operation_access(organization_id, customer_id, route_id)
  values (v_org, v_customer, '8300000d-0000-4000-8000-000000000001')
  returning id into v_access;
  get diagnostics n = row_count;
  assert n = 1, 'el owner no insertó el acceso';

  update public.customer_operation_access set active = false where id = v_access;
  get diagnostics n = row_count;
  assert n = 1, 'el owner no revocó el acceso';

  delete from public.customer_operation_access where id = v_access;
  get diagnostics n = row_count;
  assert n = 1, 'el owner no borró el acceso';
  delete from public.customers where id = v_customer;
  get diagnostics n = row_count;
  assert n = 1, 'el owner no borró el cliente';

  select name into v_name
    from public.customers
   where id = '8300000c-0000-4000-8000-000000000001';
  assert v_name = 'Cliente Semilla', 'el cliente semilla no sobrevivió a admin y owner';
  raise notice 'OWNER: OK — INSERT, UPDATE y DELETE en customers y customer_operation_access';
end $$;

reset role;
select set_config('request.jwt.claims', '', false);
