-- is_fleetops_platform_owner: email confirmado en auth.users, no el claim.
reset role;
select set_config('request.jwt.claims', '', false);

insert into auth.users(id, email, email_confirmed_at) values
 ('91000000-0000-4000-8000-000000000001', '  Platform-Owner@Example.test  ', null),
 ('91000000-0000-4000-8000-000000000002', 'other-confirmed@example.test', now());
insert into public.fleetops_platform_owners(email)
values ('platform-owner@example.test');

set role authenticated;
select set_config(
    'request.jwt.claims',
    '{"sub":"91000000-0000-4000-8000-000000000001","role":"authenticated","email":"platform-owner@example.test"}',
    false);
do $$ begin
    assert public.is_fleetops_platform_owner() is false,
        'aceptó al owner con email sin confirmar';
end $$;

reset role;
update auth.users
   set email_confirmed_at = now()
 where id = '91000000-0000-4000-8000-000000000001';
set role authenticated;
select set_config(
    'request.jwt.claims',
    '{"sub":"91000000-0000-4000-8000-000000000001","role":"authenticated","email":"attacker@example.test"}',
    false);
do $$ begin
    assert public.is_fleetops_platform_owner() is true,
        'rechazó un email confirmado que está en fleetops_platform_owners';
end $$;

reset role;
update auth.users
   set email = 'not-in-table@example.test'
 where id = '91000000-0000-4000-8000-000000000001';
set role authenticated;
select set_config(
    'request.jwt.claims',
    '{"sub":"91000000-0000-4000-8000-000000000001","role":"authenticated","email":"platform-owner@example.test"}',
    false);
do $$ begin
    assert public.is_fleetops_platform_owner() is false,
        'confió en el email del JWT';
end $$;

select set_config(
    'request.jwt.claims',
    '{"sub":"91000000-0000-4000-8000-000000000002","role":"authenticated","email":"other-confirmed@example.test"}',
    false);
do $$ begin
    assert public.is_fleetops_platform_owner() is false,
        'autorizó un email confirmado que no es owner';
    raise notice 'OWNER: OK — sin confirmar no; el claim del JWT no alcanza';
end $$;

reset role;
set role anon;
select set_config(
    'request.jwt.claims',
    '{"role":"anon","email":"platform-owner@example.test"}',
    false);
do $$ begin
    begin
        perform public.is_fleetops_platform_owner();
        raise exception 'anon ejecuta is_fleetops_platform_owner';
    exception
        when insufficient_privilege then null;
    end;
    raise notice 'OWNER ANON: OK — anon no ejecuta is_fleetops_platform_owner';
end $$;

reset role;
select set_config('request.jwt.claims', '', false);
