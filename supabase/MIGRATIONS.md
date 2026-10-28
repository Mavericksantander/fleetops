# Migraciones

`supabase db push` aplica solo `supabase/migrations/`, en orden de versión.
`migrations/` no es historia de Supabase: no ejecutarla.

Consulta de solo lectura a `supabase_migrations.schema_migrations` el 2026-10-27, después del merge de #8 (audit nocturno). md5 = `md5(array_to_string(statements, E'\n'))` contra `md5sum` del archivo.
No se escribió nada en producción ni en PREPROD.

| Versión | Archivo | Producción `sqvmyigzayuqahzmkujn` |
|---|---|---|
| `20261027000000` | `baseline_prod_schema.sql` | Fila presente con 0 statements: marcada por `migration repair`, el SQL no se ejecutó. No ejecutar este SQL. |
| `20261027180547` | `t012_rls_hardening.sql` | Un statement, md5 `c5b7d9ab6e42da3d13d505cb4f99cf0e`, igual al archivo. |
| `20261027190841` | `fleetops_documents_org_isolation.sql` | Un statement, md5 `508cd910a8bc626837cf6a1ca88fc2e3`, igual al archivo. |
| `20261027192031` | `driver_invite_storage_upload.sql` | Un statement, md5 `650558fb87f486e0f941c47cd22bf000`, igual al archivo. |
| `20261027210000` | `storage_policy_cleanup.sql` | Un statement, md5 `06580c40897b4325913645ddb9b727ef`, igual al archivo tras #8 (no la versión de #7). |

T012 estaba versionado `20261027000100`. Con ese nombre, `db push` no reconoce la fila de prod e intentaría aplicar el baseline y T012. El rename iguala la versión; el SQL no cambió.

## Repair

Lo corre el fundador, desde la raíz del repo, solo contra producción. CLI 2.122.0 (`supabase migration repair --help`): `--project-ref` vale con el destino linked, que es el default. `--status applied` lee `supabase/migrations/<version>_*.sql` y graba versión, nombre y statements en `schema_migrations`. No ejecuta el SQL.

```bash
supabase migration list --linked --project-ref sqvmyigzayuqahzmkujn
supabase migration repair --linked --project-ref sqvmyigzayuqahzmkujn --status applied 20261027000000
supabase migration list --linked --project-ref sqvmyigzayuqahzmkujn
```

Ya ejecutado: prod tiene la fila `20261027000000` sin statements. No repetir. No pases `--include-all`: ejecutaría el baseline encima de prod. No repares `20261027180547` (ya aplicada, y el archivo coincide). No repares `20261027000100` (nunca estuvo en prod; el archivo ya no existe).

PREPROD `xhytykgwkwezkjzfjqoh` tiene otra historia: `20261027171715` `preprod_drop_legacy_empty_schema`, `20261027171724` `baseline_prod_schema`, `20261027171731` `t012_rls_hardening`, `20261027200128` `fleetops_documents_org_isolation`, `20261027200133` `driver_invite_storage_upload`, `20261027200138` `storage_policy_cleanup`. Las tres últimas tienen el mismo md5 que los archivos; baseline y T012 no. Ninguna versión coincide con un archivo: `supabase db push` contra PREPROD intentaría aplicar los cinco archivos, baseline incluido. No usar `db push` ahí sin antes alinear la historia. Esos comandos de repair no aplican ahí.

## Por qué sigue `migrations/`

El baseline salió de catálogos, no de un `pg_dump` ni de reaplicar esos archivos.

- `migrations/2026-10-08-platform-organization-deletion.sql` define `public.delete_fleetops_platform_organization(uuid)`. En prod `pg_proc` devuelve 0 filas y el baseline no la tiene. `js/fleetops-admin.js` la llama. No la muevas a `supabase/migrations/` en este cambio: el próximo `db push` la crearía en prod.
- `migrations/2026-10-08-platform-owner-dashboard.sql` inserta un email personal en `public.fleetops_platform_owners`. El baseline crea la tabla y no carga datos. Prod tiene 1 fila (`count(*)`; no se leyó el email).

El resto de objetos creados por `migrations/` aparece en el baseline, pero los cuerpos no se compararon statement a statement. Por eso la carpeta se conserva y queda fuera de `db push`.

## `archive/`

`archive/2026-09-16-organizations-routes.sql` se eliminó. En el baseline y en prod están `organizations`, `organization_members`, `routes`, `viajes.route_id`, `idx_routes_organization_active` e `idx_viajes_route_id`. Las políticas `members_read_routes`, `owners_manage_organizations`, `members_manage_routes`, `authenticated_update_viajes_route` y `owners_manage_memberships` no están en prod. `migrations/2026-09-17-multiempresa-rbac.sql` las reemplaza y ese estado está en el baseline. El check de rol de ese archivo (`owner`, `operator`) es anterior al del baseline (`owner`, `admin`, `operator`, `viewer`, `customer`).

## Owner de plataforma

La autorización es la tabla. `is_fleetops_platform_owner()` une `auth.users` con `public.fleetops_platform_owners` si el email está confirmado. En un entorno nuevo, insertar a mano o en un `supabase/seed.sql` no versionado:

```sql
insert into public.fleetops_platform_owners (email)
values (lower(btrim('owner@example.com')))
on conflict (email) do nothing;
```

No reejecutar el INSERT histórico en prod.

## Funciones nuevas

`20261027210000` ejecuta `alter default privileges for role postgres revoke execute on functions from public`. Aplica a toda función nueva que cree `postgres`, en cualquier schema y para todos los roles: ya no heredan `EXECUTE` de `PUBLIC`. En `public`, el default de Supabase sigue otorgando `EXECUTE` a `anon`, `authenticated` y `service_role`. Fuera de `public` hay que poner un `GRANT EXECUTE` explícito al rol que deba llamarla.

## Checks

`.github/workflows/checks.yml` corre `node --check` sobre `js/*.js` y `scripts/*.mjs`. `supabase/tests/local/run_local.py` necesita Postgres local y psycopg; no está en ese workflow.
