# PRAETOR FleetOps

Aplicacion web estatica para onboarding de conductores, captura operacional y monitoreo de viajes.

## Paginas activas

- `index.html`: landing pública de FleetOps.
- `reportes.html`: formulario público de reporte de operación por viaje.
- `driver.html`: onboarding de conductores por invitación.
- `dashboard.html`: dashboard de operaciones y timeline.
- `customer-dashboard.html`: vista limitada a operaciones autorizadas de clientes.
- `fleetops-admin.html`: acceso privado para aprovisionar organizaciones y sus primeros owners.
- `conductores.html`: pool de conductores agrupado por ruta.
- `routes.html`: organizaciones y rutas configurables por operador.
- `equipo.html`: equipo de la organización, invitaciones y gestión de clientes.
- `login.html`: acceso de operadores por email o Google.
- `success.html`: confirmacion de reportes.
- `404.html`: pagina de recurso no encontrado.

## JavaScript

- `js/supabase.js`: instancia unica del cliente Supabase.
- `js/supabase-config.js`: configuracion local de Supabase; se mantiene fuera de Git.
- `js/supabase-config.example.js`: plantilla sin credenciales para configurar el proyecto.
- `js/organization-context.js`: organización activa y membresías del operador.
- `js/app.js`: GPS, viajes, reportes y finalizacion.
- `js/driver.js`: onboarding y captura de licencia.
- `js/dashboard.js`: dashboard, timeline, perfiles y CSV.
- `js/conductores.js`: pool de conductores por ruta.
- `js/routes.js`: configuración de organizaciones y rutas.
- `js/equipo.js`: invitaciones de colaboradores y gestión de clientes.
- `js/login.js`: autenticacion y redireccion de operadores.
- `js/customer-dashboard.js`: resumen, operaciones e historial operacional del cliente.
- `js/fleetops-admin.js`: administración de plataforma restringida al owner global.

## Estilos

- `dashboard.css`: estilos compartidos del dashboard.
- `conductores.css`: estilos del pool de conductores.
- `routes.css`: estilos de configuración de rutas.
- `login.css`: estilos exclusivos de inicio de sesion.

## Migraciones

`supabase db push` solo lee `supabase/migrations/`. No ejecutes `migrations/`:
son SQL histórico y no equivalen al baseline. El procedimiento para marcar el
baseline en producción, sin correrlo, está en `supabase/MIGRATIONS.md`.

La visibilidad de clientes (rol `customer`, `customers`, `customer_users`,
accesos por operación o ruta, invitación y acceso dual sin perder el rol
interno) ya está en el baseline. `create_customer_for_organization` asocia el
cliente a la organización seleccionada. Sin sesión, `resolve_viaje_public` solo resuelve viajes activos y no devuelve
conductor, patente ni IDs (`20261028131700`); un customer autenticado solo
resuelve viajes autorizados.

Después del baseline (ver `supabase/MIGRATIONS.md`):

- `20261028131700_resolve_viaje_public_anon_minimal` (#25): respuesta mínima
  para anon, solo viajes activos.
- `20261029020000_report_identity_tracto_invite` (#26): `submit_driver_report`
  exige patente normalizada y conductor resuelto; un cambio de `tracto_id`
  exige un tracto de la org del usuario; `consume_organization_driver_invite`
  sin EXECUTE para el API; se elimina `finalizar_viaje(text)`.
- `20261029030000_tractos_select_returning` (#28): la policy SELECT de
  `tractos` evalúa `organization_id` de la fila para que `INSERT ... RETURNING`
  no falle con 42501, sin abrir lectura entre organizaciones.

Cada migración posterior a `20261028002755` tiene su reversión en
`supabase/migrations/down/<versión>_<nombre>.down.sql`. `db push` no lee
`down/`; se ejecuta a mano solo si hay que revertir.

El owner global es una fila de `public.fleetops_platform_owners`, no un email
en el repositorio. Puede crear organizaciones y una invitación para el primer
owner; la propiedad pasa al invitado cuando acepta. El enlace se comparte a
mano. No hay botón para eliminar una organización:
`delete_fleetops_platform_organization` no está en producción ni en el
baseline, y el panel ya no la llama.

## Validacion rapida

```bash
for f in js/*.js scripts/*.mjs; do node --check "$f"; done
```

`.github/workflows/checks.yml` corre ese chequeo y `npm test` (tests de
frontend en `tests/frontend/*.test.mjs`, p. ej. el tracto ligado al conductor
de #30). Los tests SQL (`python supabase/tests/local/run_local.py "dbname=..."`)
aplican shim, migraciones y `supabase/tests/*.sql` (aislamiento RLS de dos
tenants y usuario sin org de #24, más los tests de #25, #26 y #28). Necesitan
Postgres local y psycopg; no están en CI.

## Configuracion local y GitHub

Antes de usar la aplicacion, crea `js/supabase-config.js` a partir de
`js/supabase-config.example.js` y completa la URL del proyecto y su clave
publishable/anon. El archivo real esta excluido por `.gitignore`; no lo agregues
al repositorio.

La clave publishable/anon se utiliza en el navegador y no es un secreto de
servidor. Nunca pongas una clave `service_role` o `sb_secret_` en archivos
publicos: esos permisos deben permanecer en un backend. Si alguna clave
privilegiada estuvo en el codigo o en el historial de Git, revocala y genera una
nueva en Supabase.

## Build de Vercel

`vercel.json` usa `npm run build` (`scripts/build-config.mjs`). Copia los
archivos públicos a `dist/` y escribe `dist/js/supabase-config.js` con
`SUPABASE_URL` y `SUPABASE_ANON_KEY`. El build termina con error si faltan o
si la clave parece `service_role`.

## Integridad de eventos operacionales

El baseline ya incluye timestamp de servidor, actor atribuido, causas
estructuradas de incidente y la alerta del dashboard por viajes activos sin
actualización durante seis horas o más. No vuelvas a ejecutar
`migrations/2026-10-05-operational-event-integrity.sql`. Ese timestamp acredita
cuándo Supabase recibió el reporte, no necesariamente cuándo ocurrió físicamente
el evento.

Los reportes de conductores siguen siendo públicos y el conductor no inicia
sesión: `actor_conductor_id` registra la identidad asociada al viaje, pero no
verifica criptográficamente quién envió el formulario. Los registros anteriores
al cambio quedan identificados como legacy y su actor no se puede reconstruir
con fiabilidad.
