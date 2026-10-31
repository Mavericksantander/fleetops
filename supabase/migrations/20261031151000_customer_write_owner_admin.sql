-- customers_manage_internal_only y customer_access_manage_internal_only
-- eran FOR ALL con user_has_org_role(..., owner, admin, operator).
-- Un operator autenticado escribía directo por la API. Los RPC de la
-- página (create_customer_for_organization y los de invitación) solo
-- aceptan owner y admin. Las policies de SELECT no se tocan.
begin;

drop policy if exists customers_manage_internal_only on public.customers;
create policy customers_manage_internal_only
    on public.customers
    as permissive
    for all
    to authenticated
    using (
        public.user_has_org_role(organization_id, array['owner', 'admin'])
    )
    with check (
        public.user_has_org_role(organization_id, array['owner', 'admin'])
        and organization_id is not null
    );

drop policy if exists customer_access_manage_internal_only on public.customer_operation_access;
create policy customer_access_manage_internal_only
    on public.customer_operation_access
    as permissive
    for all
    to authenticated
    using (
        public.user_has_org_role(organization_id, array['owner', 'admin'])
    )
    with check (
        public.user_has_org_role(organization_id, array['owner', 'admin'])
        and organization_id is not null
        and customer_id is not null
        and (route_id is not null or trip_id is not null)
    );

commit;
