-- Reversión de 20261031151000_customer_write_owner_admin.
-- Restaura las policies FOR ALL previas (owner, admin, operator). Ejecutar a mano solo si hay que revertir.
-- Advertencia: vuelve a permitir que un operator escriba clientes y accesos por la API.
begin;

drop policy if exists customers_manage_internal_only on public.customers;
create policy customers_manage_internal_only
    on public.customers as permissive for all to authenticated
    using (public.user_has_org_role(organization_id, array['owner', 'admin', 'operator']))
    with check (public.user_has_org_role(organization_id, array['owner', 'admin', 'operator'])
                and organization_id is not null);

drop policy if exists customer_access_manage_internal_only on public.customer_operation_access;
create policy customer_access_manage_internal_only
    on public.customer_operation_access as permissive for all to authenticated
    using (public.user_has_org_role(organization_id, array['owner', 'admin', 'operator']))
    with check (public.user_has_org_role(organization_id, array['owner', 'admin', 'operator'])
                and organization_id is not null
                and customer_id is not null
                and (route_id is not null or trip_id is not null));

commit;
