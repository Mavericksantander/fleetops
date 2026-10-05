# PRAETOR FleetOps

Aplicacion web estatica para onboarding de conductores, captura operacional y monitoreo de viajes.

## Paginas activas

- `index.html`: landing pública de FleetOps.
- `reportes.html`: formulario público de reporte de operación por viaje.
- `driver.html`: onboarding y recuperacion de identidad por RUT.
- `dashboard.html`: dashboard de operaciones y timeline.
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

## Validacion rapida

```bash
node --check js/app.js
node --check js/driver.js
node --check js/dashboard.js
node --check js/conductores.js
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
