# PRAETOR FleetOps

Aplicacion web estatica para onboarding de conductores, captura operacional y monitoreo de viajes.

## Paginas activas

- `index.html`: landing pública de FleetOps.
- `reportes.html`: formulario público de reporte de operación por viaje.
- `driver.html`: onboarding y recuperacion de identidad por RUT.
- `dashboard.html`: dashboard de operaciones y timeline.
- `customer-dashboard.html`: vista limitada a operaciones autorizadas de clientes.
- `fleetops-admin.html`: acceso privado para aprovisionar organizaciones y sus primeros owners.
- `conductores.html`: pool de conductores agrupado por ruta.
- `routes.html`: organizaciones y rutas configurables por operador.
- `login.html`: acceso de operadores por email o Google.
- `success.html`: confirmacion de reportes.
- `qr.html`: generador de QR para la URL de operación.
- `404.html`: pagina de recurso no encontrado.

## JavaScript

- `js/supabase.js`: instancia unica del cliente Supabase.
- `js/supabase-config.js`: configuracion local de Supabase; se mantiene fuera de Git.
- `js/supabase-config.example.js`: plantilla sin credenciales para configurar el proyecto.
- `js/app.js`: GPS, viajes, reportes y finalizacion.
- `js/driver.js`: onboarding, recuperacion y captura de licencia.
- `js/dashboard.js`: dashboard, timeline, perfiles y CSV.
- `js/conductores.js`: pool de conductores por ruta.
- `js/routes.js`: configuración de organizaciones y rutas.
- `js/login.js`: autenticacion y redireccion de operadores.
- `js/customer-dashboard.js`: resumen, operaciones e historial operacional del cliente.
- `js/fleetops-admin.js`: administración de plataforma restringida al owner global.

## Estilos

- `dashboard.css`: estilos compartidos del dashboard.
- `conductores.css`: estilos del pool de conductores.
- `routes.css`: estilos de configuración de rutas.
- `login.css`: estilos exclusivos de inicio de sesion.

## Archivo historico

Los respaldos anteriores estan en `archive/`. No se cargan desde ninguna pagina activa.

La migracion propuesta para organizaciones, rutas y `viajes.route_id` esta en
`archive/2026-09-16-organizations-routes.sql`. Debe ejecutarse en Supabase antes
de usar `routes.html` o asignar rutas configuradas.

Para la capa de visibilidad para clientes, aplica la migracion
`migrations/2026-10-07-customer-visibility.sql`. Agrega el rol `customer`, la tabla
`customers`, la relación `customer_users`, los accesos por operación/ruta y el
RLS que restringe cada cliente a sus viajes autorizados. Luego aplica
`migrations/2026-10-08-customer-visibility-controls.sql` para habilitar la
invitación vinculada a un cliente, administración y exclusión de accesos por
viaje, auditoría administrativa y restricciones adicionales de los RPCs de lectura.
La creación de clientes desde la interfaz usa `create_customer_for_organization`
para asegurar que el cliente queda asociado a la organización seleccionada.
Si una cuenta que ya pertenece a la organización necesita además acceso al panel
de un cliente, aplica `migrations/2026-10-08-customer-dual-access.sql` después de
las migraciones de visibilidad y de administración global. La cuenta conserva su
rol interno y suma el acceso de cliente; no se convierte en una cuenta de cliente
aislada.
El formulario de reporte conserva compatibilidad con los QR existentes: una persona
que conozca un UUID de viaje puede resolverlo de forma anónima, aunque los usuarios
customer autenticados solo pueden resolver viajes autorizados.

Para habilitar el panel privado de administración global, aplica después
`migrations/2026-10-08-platform-owner-dashboard.sql`. Autoriza como owner global
la cuenta `joseto.maverick@gmail.com`; ese usuario puede crear organizaciones y
generar una invitación para su primer owner. La propiedad de la organización se
transfiere al invitado cuando acepta. El enlace debe compartirse manualmente.
Para habilitar la eliminación permanente de una organización desde ese panel,
aplica también `migrations/2026-10-08-platform-organization-deletion.sql`. La
acción borra los viajes y reportes de la organización, además de sus datos
relacionados por cascada; no elimina las cuentas de autenticación de sus usuarios.

## Validacion rapida

```bash
node --check js/app.js
node --check js/driver.js
node --check js/dashboard.js
node --check js/conductores.js
node --check js/equipo.js
node --check js/customer-dashboard.js
```

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

## Integridad de eventos operacionales

Para habilitar timestamp server-side, actor atribuido, causas estructuradas de
incidente y alertas por falta de actualización, aplica
`migrations/2026-10-05-operational-event-integrity.sql` en Supabase. La migración
preserva los timestamps históricos existentes y usa el reloj del servidor para
nuevos reportes. Ese timestamp acredita cuándo Supabase recibió el reporte, no
necesariamente cuándo ocurrió físicamente el evento. El dashboard marca viajes
activos sin actualización durante seis horas o más.

Los reportes de conductores siguen siendo públicos y el conductor no inicia
sesión: `actor_conductor_id` registra la identidad asociada al viaje, pero no
verifica criptográficamente quién envió el formulario. Los registros anteriores
al cambio quedan identificados como legacy y su actor no se puede reconstruir
con fiabilidad.
