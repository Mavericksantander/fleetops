-- Reversión de 20261029030000_tractos_select_returning.sql: política previa (T-012).
begin;
drop policy if exists tractos_select_org on public.tractos;
create policy tractos_select_org on public.tractos
    for select to authenticated
    using (private.can_access_tracto(id, array['owner','admin','operator','viewer']));
commit;
