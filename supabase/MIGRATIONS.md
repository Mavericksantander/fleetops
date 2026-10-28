# Migraciones

`supabase db push` aplica solo `supabase/migrations/`, en orden de versión.
`migrations/` no es historia de Supabase: no ejecutarla.

Consulta de solo lectura a `supabase_migrations.schema_migrations` el 2026-10-27, después del merge de #10 (5574821). md5 = `md5(array_to_string(statements, E'\n'))` contra `md5sum` del archivo.
No se escribió nada en producción ni en PREPROD.

| Versión | Archivo | Producción `sqvmyigzayuqahzmkujn` |
|---|---|---|
| `20261027000000` | `baseline_prod_schema.sql` | Fila presente con 0 statements: marcada por `migration repair`, el SQL no se ejecutó. No ejecutar este SQL. |
| `20261027180547` | `t012_rls_hardening.sql` | Un statement, md5 `c5b7d9ab6e42da3d13d505cb4f99cf0e`, igual al archivo. |
| `20261027190841` | `fleetops_documents_org_isolation.sql` | Un statement, md5 `508cd910a8bc626837cf6a1ca88fc2e3`, igual al archivo. |
| `20261027192031` | `driver_invite_storage_upload.sql` | Un statement, md5 `650558fb87f486e0f941c47cd22bf000`, igual al archivo. |
| `20261027210000` | `storage_policy_cleanup.sql` | Un statement, md5 `06580c40897b4325913645ddb9b727ef`, igual al archivo tras #8 (no la versión de #7). |
| `20261028000000` | `onboarding_invite_binding.sql` | **Versión distinta**: prod la registró como `20261028002755`. Un statement, md5 `2e270e8b3ceb8b29648128304a671d55`, igual al archivo. |

T012 estaba versionado `20261027000100`. Con ese nombre, `db push` no reconoce la fila de prod e intentaría aplicar el baseline y T012. El rename iguala la versión; el SQL no cambió.

## Repair

Lo corre el fundador, desde la raíz del repo, solo contra producción. CLI 2.122.0 (`supabase migration repair --help`): `--project-ref` vale con el destino linked, que es el default. `--status applied` graba la versión en `schema_migrations` sin ejecutar el SQL. En prod, la fila que dejó para `20261027000000` tiene 0 statements (md5 de vacío `d41d8cd98f00b204e9800998ecf8427e`): una fila reparada no sirve para comparar md5.

```bash
supabase migration list --linked --project-ref sqvmyigzayuqahzmkujn
supabase migration repair --linked --project-ref sqvmyigzayuqahzmkujn --status applied 20261027000000
supabase migration list --linked --project-ref sqvmyigzayuqahzmkujn
```

Ya ejecutado: prod tiene la fila `20261027000000` sin statements. No repetir. No pases `--include-all`: ejecutaría el baseline encima de prod. No repares `20261027180547` (ya aplicada, y el archivo coincide). No repares `20261027000100` (nunca estuvo en prod; el archivo ya no existe).

PREPROD `xhytykgwkwezkjzfjqoh` tiene otra historia: `20261027171715` `preprod_drop_legacy_empty_schema`, `20261027171724` `baseline_prod_schema`, `20261027171731` `t012_rls_hardening`, `20261027200128` `fleetops_documents_org_isolation`, `20261027200133` `driver_invite_storage_upload`, `20261027200138` `storage_policy_cleanup`, `20261028002706` `onboarding_invite_binding`. Las cuatro últimas tienen el mismo md5 que los archivos; baseline y T012 no. Ninguna versión coincide con un archivo: `supabase db push` contra PREPROD intentaría aplicar los cinco archivos, baseline incluido. No usar `db push` ahí sin antes alinear la historia. Esos comandos de repair no aplican ahí.


## Plan de repair pendiente (NO ejecutado)

Lo decide y lo corre el fundador. Ninguno de estos comandos reescribe el esquema: solo tocan `supabase_migrations.schema_migrations`. CLI 2.122.0. No usar `--include-all` ni `db push` hasta terminar el paso 4.

Estado al 2026-10-27, después de #10. El SQL de `onboarding_invite_binding` está aplicado en los dos proyectos, con el md5 del archivo y las guardas presentes en `pg_get_functiondef`. Solo difiere la versión.

| | Archivo | Prod | PREPROD |
|---|---|---|---|
| onboarding_invite_binding | `20261028000000` | `20261028002755` | `20261028002706` |

**Paso 1 · repo (PR aparte).** Renombrar `supabase/migrations/20261028000000_onboarding_invite_binding.sql` a `20261028002755_onboarding_invite_binding.sql`, sin cambiar el contenido. Así prod queda igual al repo sin repair y el md5 de la fila sigue comparándose contra el archivo.

**Paso 2 · prod.** Sin repair. Verificación:

```bash
supabase link --project-ref sqvmyigzayuqahzmkujn
supabase migration list --linked
```

Local y remoto deben mostrar las mismas 6 versiones. Si en vez del paso 1 se prefiere no renombrar, el repair sería `supabase migration repair --linked --status reverted 20261028002755` y luego `--status applied 20261028000000`. Eso pierde los statements guardados en la fila.

**Paso 3 · PREPROD.** Alinea su historia con la del repo. El esquema ya tiene todo lo de estos archivos; las cuatro últimas filas tienen el md5 de su archivo, pero baseline y T012 no.

```bash
supabase link --project-ref xhytykgwkwezkjzfjqoh
supabase migration list --linked
supabase migration repair --linked --status reverted 20261027171715 20261027171724 20261027171731 20261027200128 20261027200133 20261027200138 20261028002706
supabase migration repair --linked --status applied 20261027000000 20261027180547 20261027190841 20261027192031 20261027210000 20261028002755
supabase migration list --linked
```

Primero `reverted` y después `applied`, en ese orden. Si el segundo falla, la historia queda vacía pero el esquema no cambia: repetir el segundo comando.

**Paso 4 · verificar los dos proyectos** (solo lectura):

```sql
select version, name, cardinality(statements)
  from supabase_migrations.schema_migrations
 order by version;
```

Deben salir exactamente las 6 versiones del repo. Las filas reparadas pueden tener 0 statements; eso es esperado. Después, `supabase db push --dry-run --linked` en cada proyecto no debe listar ninguna migración pendiente.

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
