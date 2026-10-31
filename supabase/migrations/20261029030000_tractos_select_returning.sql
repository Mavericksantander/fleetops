-- INSERT ... RETURNING en tractos (PostgREST Prefer: return=representation) fallaba con 42501
-- para todos los roles: con RETURNING, Postgres exige que la fila nueva cumpla también la
-- política SELECT. tractos_select_org usaba private.can_access_tracto(id), función STABLE que
-- busca la fila en public.tractos con el snapshot del statement, anterior al INSERT: no la ve.
-- Fix: la política SELECT evalúa también la columna organization_id de la fila (sin subconsulta
-- sobre tractos). Mismos roles de lectura; no abre lectura entre organizaciones. Se mantiene la
-- ruta por conductor (can_access_tracto) para tractos legados sin organization_id.
begin;
drop policy if exists tractos_select_org on public.tractos;
create policy tractos_select_org on public.tractos
    for select to authenticated
    using (
        public.user_has_org_role(organization_id, array['owner','admin','operator','viewer'])
        or private.can_access_tracto(id, array['owner','admin','operator','viewer'])
    );
commit;
