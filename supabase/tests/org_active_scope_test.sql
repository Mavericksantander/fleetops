-- Alta de organización y RPC acotados a la org pedida.
-- Casos negativos: el INSERT directo y el uso de otra org fallan.
-- Casos positivos: el RPC de alta y los RPC con p_organization_id escriben ahí.
-- Control negativo: la fila del INSERT cumple owner_id = auth.uid()
-- (el WITH CHECK que se eliminó) y el ORDER BY del baseline elige otra org.
-- Si el fixture no separa esas dos orgs, el control falla a propósito.
reset role;
select set_config('request.jwt.claims', '', false);

insert into auth.users(id, email) values
 ('82000000-0000-4000-8000-0000000000a1','scope-admin@example.test'),
 ('82000000-0000-4000-8000-0000000000b1','scope-owner-activa@example.test'),
 ('82000000-0000-4000-8000-0000000000c1','scope-viewer@example.test'),
 ('82000000-0000-4000-8000-0000000000d1','scope-operator@example.test'),
 ('82000000-0000-4000-8000-0000000000e1','scope-nuevo@example.test'),
 ('82000000-0000-4000-8000-0000000000f1','scope-ajena@example.test');
insert into public.organizations(id, name, owner_id, created_at) values
 ('8200000a-0000-4000-8000-000000000001','Org Antigua','82000000-0000-4000-8000-0000000000a1','2020-01-01T00:00:00Z'),
 ('8200000b-0000-4000-8000-000000000002','Org Activa','82000000-0000-4000-8000-0000000000b1','2024-06-01T00:00:00Z'),
 ('8200000c-0000-4000-8000-000000000003','Org Ajena','82000000-0000-4000-8000-0000000000f1','2019-01-01T00:00:00Z');
insert into public.organization_members(organization_id, user_id, role) values
 ('8200000a-0000-4000-8000-000000000001','82000000-0000-4000-8000-0000000000a1','owner'),
 ('8200000b-0000-4000-8000-000000000002','82000000-0000-4000-8000-0000000000b1','owner'),
 ('8200000b-0000-4000-8000-000000000002','82000000-0000-4000-8000-0000000000a1','admin'),
 ('8200000b-0000-4000-8000-000000000002','82000000-0000-4000-8000-0000000000c1','viewer'),
 ('8200000b-0000-4000-8000-000000000002','82000000-0000-4000-8000-0000000000d1','operator'),
 ('8200000c-0000-4000-8000-000000000003','82000000-0000-4000-8000-0000000000f1','owner');

do $$
declare
  v_user uuid := '82000000-0000-4000-8000-0000000000a1';
  v_antigua uuid := '8200000a-0000-4000-8000-000000000001';
  v_activa uuid := '8200000b-0000-4000-8000-000000000002';
  v_old_customer uuid;
  v_old_invite uuid;
  n int;
begin
  assert to_regprocedure('public.create_customer(text,text,text,text)') is null,
         'sigue create_customer(text,text,text,text)';
  assert to_regprocedure('public.create_member_invite(text,text)') is null,
         'sigue create_member_invite(text,text)';
  assert to_regprocedure('public.create_customer(uuid,text,text,text,text)') is not null,
         'falta create_customer(uuid,text,text,text,text)';
  assert to_regprocedure('public.create_member_invite(uuid,text,text)') is not null,
         'falta create_member_invite(uuid,text,text)';
  assert not has_function_privilege('anon', 'public.create_customer(uuid,text,text,text,text)', 'execute'),
         'anon ejecuta create_customer';
  assert not has_function_privilege('anon', 'public.create_member_invite(uuid,text,text)', 'execute'),
         'anon ejecuta create_member_invite';
  assert has_function_privilege('authenticated', 'public.create_customer(uuid,text,text,text,text)', 'execute'),
         'authenticated no ejecuta create_customer';
  assert has_function_privilege('authenticated', 'public.create_member_invite(uuid,text,text)', 'execute'),
         'authenticated no ejecuta create_member_invite';

  select count(*) into n
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public'
     and c.relname = 'organizations'
     and p.polname = 'users_create_organizations';
  assert n = 0, 'users_create_organizations sigue presente';

  select count(*) into n
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public'
     and c.relname = 'organizations'
     and p.polcmd in ('a', '*');
  assert n = 0, format('queda una policy INSERT o ALL en organizations (%s)', n);

  select o.id into v_old_customer
    from public.organizations o
   where o.owner_id = v_user
      or exists (
          select 1
            from public.organization_members om
           where om.organization_id = o.id
             and om.user_id = v_user
             and om.role in ('owner', 'admin')
      )
   order by (o.owner_id = v_user) desc, o.created_at
   limit 1;

  select o.id into v_old_invite
    from public.organizations o
   where o.owner_id = v_user
      or exists (
          select 1
            from public.organization_members om
           where om.organization_id = o.id
             and om.user_id = v_user
             and om.role = 'admin'
      )
   order by (o.owner_id = v_user) desc, o.created_at
   limit 1;

  assert v_old_customer = v_antigua, 'control: create_customer viejo no elegía Org Antigua';
  assert v_old_invite = v_antigua, 'control: create_member_invite viejo no elegía Org Antigua';
  assert v_old_customer <> v_activa and v_old_invite <> v_activa,
         'control negativo inválido: el ORDER BY del baseline ya apunta a la org activa';
  raise notice 'CONTROL: OK — el ORDER BY del baseline elige Org Antigua, no Org Activa';
end $$;

create or replace function pg_temp.scope_sqlstate(p_sql text) returns text
language plpgsql
as $$
begin
  execute p_sql;
  return 'ok';
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $$;
grant execute on function pg_temp.scope_sqlstate(text) to public;

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"82000000-0000-4000-8000-0000000000e1","role":"authenticated"}', false);
do $$
declare
  r text;
  v_org uuid;
  n int;
  v_user uuid := '82000000-0000-4000-8000-0000000000e1';
begin
  assert auth.uid() = v_user, 'auth.uid() del usuario sin org no es el esperado';
  r := pg_temp.scope_sqlstate(format(
    $q$insert into public.organizations(name, owner_id) values ('Org Insert Directo', %L::uuid)$q$,
    v_user));
  assert r like '42501%', format('INSERT directo del usuario sin org = %s', r);
  assert not exists (select 1 from public.organizations where name = 'Org Insert Directo'),
         'el INSERT directo creó una organización';

  select organization_id into v_org
    from public.create_organization_for_current_user('Empresa Nueva');
  assert v_org is not null, 'el RPC no creó la organización';
  select count(*) into n from public.organization_members
   where user_id = v_user and role = 'owner';
  assert n = 1, format('memberships owner tras el RPC = %s', n);
  select count(*) into n
    from public.organization_subscriptions s
    join public.organizations o on o.id = s.organization_id
   where o.owner_id = v_user;
  assert n = 1, format('suscripciones del usuario nuevo = %s', n);

  r := pg_temp.scope_sqlstate($q$select public.create_organization_for_current_user('Empresa Segunda')$q$);
  assert position('ya pertenece a una organización' in r) > 0, format('segundo RPC = %s', r);
  select count(*) into n from public.organizations where owner_id = v_user;
  assert n = 1, format('organizaciones del usuario nuevo = %s', n);

  update public.organizations set name = 'Empresa Nueva Renombrada' where id = v_org;
  get diagnostics n = row_count;
  assert n = 1, 'el owner no pudo actualizar su organización';

  delete from public.organizations where id = v_org;
  get diagnostics n = row_count;
  assert n = 1, 'el owner no pudo borrar su organización';
  raise notice 'ALTA: OK — INSERT directo rechazado; el RPC crea una sola organización';
end $$;

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"82000000-0000-4000-8000-0000000000a1","role":"authenticated"}', false);
do $$
declare
  r text;
  v_org uuid;
  v_customer uuid;
  n int;
  v_user uuid := '82000000-0000-4000-8000-0000000000a1';
  v_antigua uuid := '8200000a-0000-4000-8000-000000000001';
  v_activa uuid := '8200000b-0000-4000-8000-000000000002';
  v_ajena uuid := '8200000c-0000-4000-8000-000000000003';
begin
  assert auth.uid() = v_user, 'auth.uid() del admin no es el esperado';
  r := pg_temp.scope_sqlstate(format(
    $q$insert into public.organizations(name, owner_id) values ('Org Segunda Del Admin', %L::uuid)$q$,
    v_user));
  assert r like '42501%', format('INSERT directo de quien ya tiene org = %s', r);
  assert not exists (select 1 from public.organizations where name = 'Org Segunda Del Admin'),
         'quien ya pertenece a una org insertó otra';

  r := pg_temp.scope_sqlstate($q$select public.create_organization_for_current_user('Otra Empresa')$q$);
  assert position('ya pertenece a una organización' in r) > 0,
         format('RPC de alta para quien ya es miembro = %s', r);

  r := pg_temp.scope_sqlstate(format(
    $q$select public.create_customer(%L::uuid, 'Cliente Ajeno')$q$, v_ajena));
  assert position('No tienes permisos para crear clientes' in r) > 0,
         format('create_customer en org ajena = %s', r);
  r := pg_temp.scope_sqlstate(format(
    $q$select public.create_member_invite(%L::uuid, 'ajeno@example.test', 'admin')$q$, v_ajena));
  assert position('No tienes permisos para invitar colaboradores' in r) > 0,
         format('create_member_invite en org ajena = %s', r);
  r := pg_temp.scope_sqlstate($q$select public.create_customer(null, 'Sin Org')$q$);
  assert position('No tienes permisos para crear clientes' in r) > 0,
         format('create_customer sin org = %s', r);
  r := pg_temp.scope_sqlstate($q$select public.create_member_invite(null, 'sin-org@example.test', 'viewer')$q$);
  assert position('No tienes permisos para invitar colaboradores' in r) > 0,
         format('create_member_invite sin org = %s', r);

  select customer_id, organization_id into v_customer, v_org
    from public.create_customer(v_activa, 'Cliente Activa', 'Contacto', 'activa@example.test', '+56911111111');
  assert v_org = v_activa, format('create_customer escribió en %s', v_org);
  select count(*) into n from public.customers where id = v_customer and organization_id = v_activa;
  assert n = 1, 'el cliente no quedó en Org Activa';
  select count(*) into n from public.customers where organization_id = v_antigua;
  assert n = 0, 'create_customer escribió en Org Antigua';

  select organization_id into v_org
    from public.create_member_invite(v_activa, 'miembro-activa@example.test', 'operator');
  assert v_org = v_activa, format('create_member_invite escribió en %s', v_org);
  select count(*) into n from public.organization_member_invites
   where organization_id = v_activa and email = 'miembro-activa@example.test' and role = 'operator';
  assert n = 1, 'la invitación no quedó en Org Activa';
  select count(*) into n from public.organization_member_invites where organization_id = v_antigua;
  assert n = 0, 'create_member_invite escribió en Org Antigua';

  select organization_id into v_org
    from public.create_member_invite(v_antigua, 'miembro-antigua@example.test', 'viewer');
  assert v_org = v_antigua, format('la org pedida antigua devolvió %s', v_org);
  select count(*) into n from public.organization_member_invites
   where organization_id = v_antigua and email = 'miembro-antigua@example.test';
  assert n = 1, 'pedir Org Antigua no escribió ahí';
  select count(*) into n from public.organization_member_invites
   where organization_id = v_activa and email = 'miembro-antigua@example.test';
  assert n = 0, 'pedir Org Antigua escribió en Org Activa';
  raise notice 'ORG ACTIVA: OK — cliente e invitación quedan en la org pedida';
end $$;

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"82000000-0000-4000-8000-0000000000c1","role":"authenticated"}', false);
do $$
declare
  r text;
  v_activa uuid := '8200000b-0000-4000-8000-000000000002';
begin
  r := pg_temp.scope_sqlstate(format(
    $q$select public.create_member_invite(%L::uuid, 'viewer@example.test', 'viewer')$q$, v_activa));
  assert position('No tienes permisos para invitar colaboradores' in r) > 0,
         format('viewer invitó = %s', r);
  raise notice 'VIEWER: OK — no invita en la org activa';
end $$;

set role authenticated;
select set_config('request.jwt.claims', '{"sub":"82000000-0000-4000-8000-0000000000d1","role":"authenticated"}', false);
do $$
declare
  r text;
  v_activa uuid := '8200000b-0000-4000-8000-000000000002';
begin
  r := pg_temp.scope_sqlstate(format(
    $q$select public.create_customer(%L::uuid, 'Cliente Operador')$q$, v_activa));
  assert position('No tienes permisos para crear clientes' in r) > 0,
         format('operator creó cliente = %s', r);
  raise notice 'OPERATOR: OK — no crea clientes en la org activa';
end $$;

set role authenticated;
select set_config('request.jwt.claims', '{"role":"authenticated"}', false);
do $$
declare r text;
begin
  assert auth.uid() is null, 'la sesión vacía tiene uid';
  r := pg_temp.scope_sqlstate($q$select public.create_customer('8200000b-0000-4000-8000-000000000002', 'Sin Sesion')$q$);
  assert position('Debes iniciar sesión' in r) > 0, format('create_customer sin sesión = %s', r);
  r := pg_temp.scope_sqlstate($q$select public.create_member_invite('8200000b-0000-4000-8000-000000000002', 'sin-sesion@example.test', 'admin')$q$);
  assert position('Debes iniciar sesión' in r) > 0, format('create_member_invite sin sesión = %s', r);
  raise notice 'SESIÓN: OK — sin uid los RPC no escriben';
end $$;

reset role;
select set_config('request.jwt.claims', '', false);

do $$
declare n int;
begin
  select count(*) into n from public.organizations
   where name in ('Org Insert Directo', 'Org Segunda Del Admin', 'Empresa Segunda', 'Otra Empresa', 'Empresa Nueva', 'Empresa Nueva Renombrada');
  assert n = 0, format('quedó un alta que debía rechazarse (%s)', n);
  select count(*) into n from public.customers
   where name in ('Cliente Ajeno', 'Sin Org', 'Cliente Operador', 'Sin Sesion');
  assert n = 0, format('quedó un cliente que debía rechazarse (%s)', n);
  select count(*) into n from public.organization_member_invites
   where email in ('ajeno@example.test', 'sin-org@example.test', 'viewer@example.test', 'sin-sesion@example.test');
  assert n = 0, format('quedó una invitación que debía rechazarse (%s)', n);
  select count(*) into n from public.customers
   where name = 'Cliente Activa' and organization_id = '8200000b-0000-4000-8000-000000000002';
  assert n = 1, 'Org Activa no tiene el cliente creado';
  select count(*) into n from public.customers
   where name = 'Cliente Activa' and organization_id = '8200000a-0000-4000-8000-000000000001';
  assert n = 0, 'Org Antigua tiene el cliente de la org activa';
  raise notice 'BARRIDO: OK — no quedó ninguna fila de los casos negativos';
end $$;
