-- =====================================================================
-- T-012 · Baseline del esquema public de PRODUCCIÓN (sin datos)
-- Fuente: snapshot de catálogos de prod (2026-10-27 ~13:40 hora Chile, UTC-3).
-- Objetivo: cerrar el drift repo <-> prod. Esta migración DESCRIBE lo que ya
-- existe en prod: en prod NO debe ejecutarse, sino marcarse como aplicada
--   supabase migration repair --linked --project-ref sqvmyigzayuqahzmkujn --status applied 20261027000000
-- Ajustes mecánicos respecto del snapshot (para que sea ejecutable desde cero):
--   * constraints reordenados (FK al final), índices con IF NOT EXISTS
--     (los PK/UNIQUE ya crean su índice);
--   * se crean public.conductor_seq y el default de reportes.id, que el
--     snapshot de catálogos no incluyó (SUPUESTO: verificar contra
--     `supabase db dump --schema-only` antes de mergear).
-- Requiere entorno Supabase (schemas auth/extensions, roles anon/authenticated,
-- pgcrypto en schema extensions). Emails redactados; sin datos.
-- =====================================================================
set check_function_bodies = off;
create sequence if not exists public.conductor_seq;
create sequence if not exists public.reportes_id_seq;


-- ===== TABLAS =====
create table public.conductor_documentos (
  id uuid not null default gen_random_uuid(),
  conductor_id uuid not null,
  tipo_documento text not null,
  storage_path text not null,
  nombre_archivo text,
  mime_type text,
  tamano_bytes bigint,
  estado_revision text not null default 'Pendiente'::text,
  fecha_carga timestamp with time zone not null default now(),
  fecha_revision timestamp with time zone
);
alter table public.conductor_documentos enable row level security;
create table public.conductores (
  id uuid not null default gen_random_uuid(),
  driver_id text not null default ('FLE-'::text || lpad((nextval('conductor_seq'::regclass))::text, 4, '0'::text)),
  nombre text not null,
  telefono text not null,
  rut text,
  licencia text,
  tipo_licencia text,
  ciudad text,
  patente_habitual text,
  estado text not null default 'Disponible'::text,
  fecha_registro timestamp with time zone not null default now(),
  tracto_id uuid,
  licencia_vencimiento date
);
alter table public.conductores enable row level security;
create table public.customer_operation_access (
  id uuid not null default gen_random_uuid(),
  organization_id uuid not null,
  customer_id uuid not null,
  route_id uuid,
  trip_id uuid,
  active boolean not null default true,
  created_by uuid,
  created_at timestamp with time zone not null default now(),
  is_excluded boolean not null default false
);
alter table public.customer_operation_access enable row level security;
create table public.customer_users (
  id uuid not null default gen_random_uuid(),
  organization_id uuid not null,
  customer_id uuid not null,
  user_id uuid not null,
  role text not null default 'customer'::text,
  created_at timestamp with time zone not null default now()
);
alter table public.customer_users enable row level security;
create table public.customer_visibility_audit (
  id uuid not null default gen_random_uuid(),
  organization_id uuid not null,
  customer_id uuid,
  actor_user_id uuid,
  action text not null,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamp with time zone not null default now()
);
alter table public.customer_visibility_audit enable row level security;
create table public.customers (
  id uuid not null default gen_random_uuid(),
  organization_id uuid not null,
  name text not null,
  contact_name text,
  email text,
  phone text,
  is_active boolean not null default true,
  created_by uuid,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);
alter table public.customers enable row level security;
create table public.fleetops_platform_owners (
  email text not null,
  created_at timestamp with time zone not null default now()
);
alter table public.fleetops_platform_owners enable row level security;
create table public.organization_driver_invites (
  id uuid not null default gen_random_uuid(),
  organization_id uuid not null,
  token_hash text not null,
  expires_at timestamp with time zone not null,
  consumed_at timestamp with time zone,
  consumed_conductor_id uuid,
  created_by uuid not null,
  created_at timestamp with time zone not null default now()
);
alter table public.organization_driver_invites enable row level security;
create table public.organization_drivers (
  organization_id uuid not null,
  conductor_id uuid not null,
  status text not null default 'PENDING'::text,
  invited_at timestamp with time zone not null default now(),
  approved_at timestamp with time zone,
  approved_by uuid,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);
alter table public.organization_drivers enable row level security;
create table public.organization_member_invites (
  id uuid not null default gen_random_uuid(),
  organization_id uuid not null,
  email text not null,
  role text not null,
  token_hash text not null,
  expires_at timestamp with time zone not null,
  consumed_at timestamp with time zone,
  created_by uuid not null,
  created_at timestamp with time zone not null default now(),
  customer_id uuid,
  platform_bootstrap boolean not null default false
);
alter table public.organization_member_invites enable row level security;
create table public.organization_members (
  organization_id uuid not null,
  user_id uuid not null,
  role text not null default 'operator'::text,
  created_at timestamp with time zone not null default now()
);
alter table public.organization_members enable row level security;
create table public.organization_plan_limits (
  plan text not null,
  driver_limit integer,
  operator_limit integer,
  route_limit integer,
  created_at timestamp with time zone not null default now()
);
alter table public.organization_plan_limits enable row level security;
create table public.organization_subscriptions (
  id uuid not null default gen_random_uuid(),
  organization_id uuid not null,
  plan text not null,
  status text not null,
  trial_started_at timestamp with time zone,
  trial_ends_at timestamp with time zone,
  current_period_start timestamp with time zone,
  current_period_end timestamp with time zone,
  provider text,
  provider_customer_id text,
  provider_subscription_id text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);
alter table public.organization_subscriptions enable row level security;
create table public.organizations (
  id uuid not null default gen_random_uuid(),
  name text not null,
  owner_id uuid not null,
  active boolean not null default true,
  created_at timestamp with time zone not null default now()
);
alter table public.organizations enable row level security;
create table public.reportes (
  id bigint not null default nextval('public.reportes_id_seq'::regclass),
  conductor text not null,
  patente text not null,
  empresa text not null,
  ruta text not null,
  estado text not null,
  latitud double precision,
  longitud double precision,
  precision_gps double precision,
  google_maps text,
  observacion text,
  "timestamp" timestamp with time zone not null default now(),
  created_at timestamp with time zone not null default now(),
  viaje_id uuid,
  conductor_id uuid,
  actor_type text default 'legacy'::text,
  actor_conductor_id uuid,
  actor_user_id uuid,
  incident_category text
);
alter table public.reportes enable row level security;
create table public.routes (
  id uuid not null default gen_random_uuid(),
  organization_id uuid not null,
  name text not null,
  origin text,
  destination text,
  client text,
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamp with time zone not null default now()
);
alter table public.routes enable row level security;
create table public.tracto_documentos (
  id uuid not null default gen_random_uuid(),
  tracto_id uuid not null,
  tipo_documento text not null,
  storage_path text not null,
  nombre_archivo text,
  mime_type text,
  tamano_bytes bigint,
  estado_revision text not null default 'Pendiente'::text,
  fecha_carga timestamp with time zone not null default now(),
  fecha_revision timestamp with time zone
);
alter table public.tracto_documentos enable row level security;
create table public.tractos (
  id uuid not null default gen_random_uuid(),
  patente text not null,
  estado text not null default 'Disponible'::text,
  fecha_registro timestamp with time zone not null default now(),
  organization_id uuid
);
alter table public.tractos enable row level security;
create table public.viajes (
  id uuid not null default gen_random_uuid(),
  patente text not null,
  conductor text,
  empresa text,
  ruta text,
  estado text not null default 'ACTIVO'::text,
  fecha_inicio timestamp with time zone not null default now(),
  fecha_finalizacion timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  conductor_id uuid,
  empresa_id uuid,
  route_id uuid
);
alter table public.viajes enable row level security;

-- ===== CONSTRAINTS ===== (reordenado: PK/UNIQUE/CHECK antes que FK)
alter table conductor_documentos add constraint conductor_documentos_estado_revision_check CHECK ((estado_revision = ANY (ARRAY['Pendiente'::text, 'Aprobado'::text, 'Rechazado'::text])));
alter table conductor_documentos add constraint conductor_documentos_pkey PRIMARY KEY (id);
alter table conductor_documentos add constraint conductor_documentos_tipo_documento_check CHECK ((tipo_documento = ANY (ARRAY['licencia_frente'::text, 'licencia_reverso'::text, 'selfie'::text])));
alter table conductores add constraint conductores_driver_id_key UNIQUE (driver_id);
alter table conductores add constraint conductores_estado_check CHECK ((estado = ANY (ARRAY['Disponible'::text, 'Ocupado'::text, 'Inactivo'::text])));
alter table conductores add constraint conductores_pkey PRIMARY KEY (id);
alter table customer_operation_access add constraint customer_access_exclusion_scope CHECK (((NOT is_excluded) OR (trip_id IS NOT NULL))) NOT VALID;
alter table customer_operation_access add constraint customer_access_scope CHECK ((((route_id IS NOT NULL) AND (trip_id IS NULL)) OR ((route_id IS NULL) AND (trip_id IS NOT NULL))));
alter table customer_operation_access add constraint customer_operation_access_pkey PRIMARY KEY (id);
alter table customer_users add constraint customer_users_customer_id_user_id_key UNIQUE (customer_id, user_id);
alter table customer_users add constraint customer_users_organization_id_user_id_key UNIQUE (organization_id, user_id);
alter table customer_users add constraint customer_users_pkey PRIMARY KEY (id);
alter table customer_users add constraint customer_users_role_check CHECK ((role = 'customer'::text));
alter table customer_visibility_audit add constraint customer_visibility_audit_pkey PRIMARY KEY (id);
alter table customers add constraint customers_name_not_blank CHECK ((length(btrim(name)) > 0));
alter table customers add constraint customers_pkey PRIMARY KEY (id);
alter table fleetops_platform_owners add constraint fleetops_platform_owner_email_lowercase CHECK ((email = lower(btrim(email))));
alter table fleetops_platform_owners add constraint fleetops_platform_owners_pkey PRIMARY KEY (email);
alter table organization_driver_invites add constraint organization_driver_invites_pkey PRIMARY KEY (id);
alter table organization_driver_invites add constraint organization_driver_invites_token_hash_key UNIQUE (token_hash);
alter table organization_drivers add constraint organization_drivers_pkey PRIMARY KEY (organization_id, conductor_id);
alter table organization_drivers add constraint organization_drivers_status_check CHECK ((status = ANY (ARRAY['PENDING'::text, 'ACTIVE'::text])));
alter table organization_member_invites add constraint organization_member_invites_pkey PRIMARY KEY (id);
alter table organization_member_invites add constraint organization_member_invites_role_check CHECK ((role = ANY (ARRAY['owner'::text, 'admin'::text, 'operator'::text, 'viewer'::text, 'customer'::text]))) NOT VALID;
alter table organization_member_invites add constraint organization_member_invites_token_hash_key UNIQUE (token_hash);
alter table organization_members add constraint organization_members_pkey PRIMARY KEY (organization_id, user_id);
alter table organization_members add constraint organization_members_role_check CHECK ((role = ANY (ARRAY['owner'::text, 'admin'::text, 'operator'::text, 'viewer'::text, 'customer'::text]))) NOT VALID;
alter table organization_plan_limits add constraint organization_plan_limits_pkey PRIMARY KEY (plan);
alter table organization_plan_limits add constraint organization_plan_limits_plan_check CHECK ((plan = ANY (ARRAY['starter'::text, 'pro'::text, 'enterprise'::text])));
alter table organization_subscriptions add constraint organization_subscriptions_organization_id_key UNIQUE (organization_id);
alter table organization_subscriptions add constraint organization_subscriptions_pkey PRIMARY KEY (id);
alter table organization_subscriptions add constraint organization_subscriptions_plan_check CHECK ((plan = ANY (ARRAY['starter'::text, 'pro'::text, 'enterprise'::text])));
alter table organization_subscriptions add constraint organization_subscriptions_status_check CHECK ((status = ANY (ARRAY['trialing'::text, 'active'::text, 'past_due'::text, 'cancelled'::text, 'expired'::text])));
alter table organizations add constraint organizations_pkey PRIMARY KEY (id);
alter table reportes add constraint reportes_actor_type_check CHECK ((actor_type = ANY (ARRAY['driver_attributed'::text, 'operator'::text, 'legacy'::text]))) NOT VALID;
alter table reportes add constraint reportes_estado_check CHECK ((estado = ANY (ARRAY['En ruta'::text, 'Esperando carga'::text, 'Cargando'::text, 'Esperando descarga'::text, 'Descargando'::text, 'Finalizado'::text, 'Incidente'::text])));
alter table reportes add constraint reportes_incident_category_check CHECK (((incident_category IS NULL) OR (incident_category = ANY (ARRAY['Falla mecánica'::text, 'Accidente'::text, 'Falta de conductor'::text, 'Puerto'::text, 'Cliente'::text, 'Clima'::text, 'Aduana'::text, 'Operación interna'::text, 'Otro'::text])))) NOT VALID;
alter table reportes add constraint reportes_incident_category_required_check CHECK (((estado IS DISTINCT FROM 'Incidente'::text) OR (incident_category IS NOT NULL))) NOT VALID;
alter table reportes add constraint reportes_pkey PRIMARY KEY (id);
alter table routes add constraint routes_organization_id_name_key UNIQUE (organization_id, name);
alter table routes add constraint routes_pkey PRIMARY KEY (id);
alter table tracto_documentos add constraint tracto_documentos_estado_revision_check CHECK ((estado_revision = ANY (ARRAY['Pendiente'::text, 'Aprobado'::text, 'Rechazado'::text])));
alter table tracto_documentos add constraint tracto_documentos_pkey PRIMARY KEY (id);
alter table tracto_documentos add constraint tracto_documentos_tipo_documento_check CHECK ((tipo_documento = ANY (ARRAY['permiso_circulacion'::text, 'soap'::text, 'revision_tecnica'::text, 'padron_vehicular'::text])));
alter table tractos add constraint tractos_patente_key UNIQUE (patente);
alter table tractos add constraint tractos_pkey PRIMARY KEY (id);
alter table viajes add constraint viajes_pkey PRIMARY KEY (id);
alter table conductor_documentos add constraint conductor_documentos_conductor_id_fkey FOREIGN KEY (conductor_id) REFERENCES conductores(id) ON DELETE CASCADE;
alter table conductores add constraint conductores_tracto_id_fkey FOREIGN KEY (tracto_id) REFERENCES tractos(id) ON DELETE SET NULL;
alter table customer_operation_access add constraint customer_operation_access_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table customer_operation_access add constraint customer_operation_access_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE;
alter table customer_operation_access add constraint customer_operation_access_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table customer_operation_access add constraint customer_operation_access_route_id_fkey FOREIGN KEY (route_id) REFERENCES routes(id) ON DELETE CASCADE;
alter table customer_operation_access add constraint customer_operation_access_trip_id_fkey FOREIGN KEY (trip_id) REFERENCES viajes(id) ON DELETE CASCADE;
alter table customer_users add constraint customer_users_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE;
alter table customer_users add constraint customer_users_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table customer_users add constraint customer_users_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table customer_visibility_audit add constraint customer_visibility_audit_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table customer_visibility_audit add constraint customer_visibility_audit_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL;
alter table customer_visibility_audit add constraint customer_visibility_audit_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table customers add constraint customers_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table customers add constraint customers_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table organization_driver_invites add constraint organization_driver_invites_consumed_conductor_id_fkey FOREIGN KEY (consumed_conductor_id) REFERENCES conductores(id) ON DELETE SET NULL;
alter table organization_driver_invites add constraint organization_driver_invites_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table organization_driver_invites add constraint organization_driver_invites_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table organization_drivers add constraint organization_drivers_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES auth.users(id);
alter table organization_drivers add constraint organization_drivers_conductor_id_fkey FOREIGN KEY (conductor_id) REFERENCES conductores(id) ON DELETE CASCADE;
alter table organization_drivers add constraint organization_drivers_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table organization_member_invites add constraint organization_member_invites_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table organization_member_invites add constraint organization_member_invites_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL;
alter table organization_member_invites add constraint organization_member_invites_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table organization_members add constraint organization_members_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table organization_members add constraint organization_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table organization_subscriptions add constraint organization_subscriptions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table organizations add constraint organizations_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table reportes add constraint reportes_actor_conductor_id_fkey FOREIGN KEY (actor_conductor_id) REFERENCES conductores(id) ON DELETE SET NULL;
alter table reportes add constraint reportes_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table reportes add constraint reportes_conductor_id_fkey FOREIGN KEY (conductor_id) REFERENCES conductores(id) ON DELETE SET NULL;
alter table reportes add constraint reportes_viaje_id_fkey FOREIGN KEY (viaje_id) REFERENCES viajes(id);
alter table routes add constraint routes_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table tracto_documentos add constraint tracto_documentos_tracto_id_fkey FOREIGN KEY (tracto_id) REFERENCES tractos(id) ON DELETE CASCADE;
alter table viajes add constraint viajes_conductor_id_fkey FOREIGN KEY (conductor_id) REFERENCES conductores(id) ON DELETE SET NULL;
alter table viajes add constraint viajes_route_id_fkey FOREIGN KEY (route_id) REFERENCES routes(id);

-- ===== ÍNDICES =====
CREATE UNIQUE INDEX IF NOT EXISTS conductor_documentos_pkey ON public.conductor_documentos USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS conductores_driver_id_key ON public.conductores USING btree (driver_id);
CREATE INDEX IF NOT EXISTS conductores_estado_idx ON public.conductores USING btree (estado);
CREATE UNIQUE INDEX IF NOT EXISTS conductores_pkey ON public.conductores USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS conductores_telefono_uk ON public.conductores USING btree (telefono);
CREATE UNIQUE INDEX IF NOT EXISTS customer_access_active_route_unique_idx ON public.customer_operation_access USING btree (customer_id, route_id) WHERE (active AND (route_id IS NOT NULL));
CREATE UNIQUE INDEX IF NOT EXISTS customer_access_active_trip_rule_unique_idx ON public.customer_operation_access USING btree (customer_id, trip_id, is_excluded) WHERE (active AND (trip_id IS NOT NULL));
CREATE INDEX IF NOT EXISTS customer_operation_access_customer_idx ON public.customer_operation_access USING btree (customer_id, active, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS customer_operation_access_pkey ON public.customer_operation_access USING btree (id);
CREATE INDEX IF NOT EXISTS customer_operation_access_route_idx ON public.customer_operation_access USING btree (route_id, active);
CREATE INDEX IF NOT EXISTS customer_operation_access_trip_idx ON public.customer_operation_access USING btree (trip_id, active);
CREATE UNIQUE INDEX IF NOT EXISTS customer_users_customer_id_user_id_key ON public.customer_users USING btree (customer_id, user_id);
CREATE INDEX IF NOT EXISTS customer_users_lookup_idx ON public.customer_users USING btree (organization_id, user_id, customer_id);
CREATE UNIQUE INDEX IF NOT EXISTS customer_users_organization_id_user_id_key ON public.customer_users USING btree (organization_id, user_id);
CREATE UNIQUE INDEX IF NOT EXISTS customer_users_pkey ON public.customer_users USING btree (id);
CREATE INDEX IF NOT EXISTS customer_visibility_audit_org_created_idx ON public.customer_visibility_audit USING btree (organization_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS customer_visibility_audit_pkey ON public.customer_visibility_audit USING btree (id);
CREATE INDEX IF NOT EXISTS customers_organization_active_idx ON public.customers USING btree (organization_id, is_active, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS customers_pkey ON public.customers USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS fleetops_platform_owners_pkey ON public.fleetops_platform_owners USING btree (email);
CREATE INDEX IF NOT EXISTS idx_conductor_documentos_conductor ON public.conductor_documentos USING btree (conductor_id);
CREATE INDEX IF NOT EXISTS idx_routes_organization_active ON public.routes USING btree (organization_id, active);
CREATE INDEX IF NOT EXISTS idx_tracto_documentos_tracto ON public.tracto_documentos USING btree (tracto_id);
CREATE INDEX IF NOT EXISTS idx_viajes_route_id ON public.viajes USING btree (route_id);
CREATE INDEX IF NOT EXISTS organization_driver_invites_expiry_idx ON public.organization_driver_invites USING btree (expires_at) WHERE (consumed_at IS NULL);
CREATE INDEX IF NOT EXISTS organization_driver_invites_org_idx ON public.organization_driver_invites USING btree (organization_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS organization_driver_invites_pkey ON public.organization_driver_invites USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS organization_driver_invites_token_hash_key ON public.organization_driver_invites USING btree (token_hash);
CREATE INDEX IF NOT EXISTS organization_drivers_conductor_idx ON public.organization_drivers USING btree (conductor_id);
CREATE UNIQUE INDEX IF NOT EXISTS organization_drivers_pkey ON public.organization_drivers USING btree (organization_id, conductor_id);
CREATE INDEX IF NOT EXISTS organization_member_invites_lookup_idx ON public.organization_member_invites USING btree (token_hash);
CREATE UNIQUE INDEX IF NOT EXISTS organization_member_invites_pkey ON public.organization_member_invites USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS organization_member_invites_token_hash_key ON public.organization_member_invites USING btree (token_hash);
CREATE UNIQUE INDEX IF NOT EXISTS organization_members_pkey ON public.organization_members USING btree (organization_id, user_id);
CREATE UNIQUE INDEX IF NOT EXISTS organization_plan_limits_pkey ON public.organization_plan_limits USING btree (plan);
CREATE UNIQUE INDEX IF NOT EXISTS organization_subscriptions_organization_id_key ON public.organization_subscriptions USING btree (organization_id);
CREATE UNIQUE INDEX IF NOT EXISTS organization_subscriptions_pkey ON public.organization_subscriptions USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS organizations_pkey ON public.organizations USING btree (id);
CREATE INDEX IF NOT EXISTS reportes_estado_idx ON public.reportes USING btree (estado);
CREATE INDEX IF NOT EXISTS reportes_patente_idx ON public.reportes USING btree (patente);
CREATE INDEX IF NOT EXISTS reportes_patente_timestamp_idx ON public.reportes USING btree (patente, "timestamp" DESC);
CREATE UNIQUE INDEX IF NOT EXISTS reportes_pkey ON public.reportes USING btree (id);
CREATE INDEX IF NOT EXISTS reportes_timestamp_idx ON public.reportes USING btree ("timestamp" DESC);
CREATE UNIQUE INDEX IF NOT EXISTS routes_organization_id_name_key ON public.routes USING btree (organization_id, name);
CREATE UNIQUE INDEX IF NOT EXISTS routes_pkey ON public.routes USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS tracto_documentos_pkey ON public.tracto_documentos USING btree (id);
CREATE UNIQUE INDEX IF NOT EXISTS tractos_patente_key ON public.tractos USING btree (patente);
CREATE UNIQUE INDEX IF NOT EXISTS tractos_pkey ON public.tractos USING btree (id);
CREATE INDEX IF NOT EXISTS viajes_conductor_id_idx ON public.viajes USING btree (conductor_id);
CREATE INDEX IF NOT EXISTS viajes_empresa_id_idx ON public.viajes USING btree (empresa_id);
CREATE UNIQUE INDEX IF NOT EXISTS viajes_pkey ON public.viajes USING btree (id);

-- ===== FUNCIONES =====
CREATE OR REPLACE FUNCTION public.accept_member_invite(p_token text)
 RETURNS TABLE(organization_id uuid, role text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_catalog'
AS $function$
#variable_conflict use_column
declare
    v_user_id uuid := auth.uid();
    v_email text := lower(btrim(coalesce(auth.email(), '')));
    v_invite public.organization_member_invites;
begin
    if v_user_id is null then
        raise exception 'Debes iniciar sesión para aceptar la invitación.';
    end if;

    select *
      into v_invite
      from public.organization_member_invites
     where token_hash = encode(digest(btrim(coalesce(p_token, '')), 'sha256'), 'hex')
     for update;

    if not found then
        raise exception 'La invitación no existe.';
    end if;

    if v_invite.consumed_at is not null then
        raise exception 'Esta invitación ya fue utilizada.';
    end if;

    if v_invite.expires_at <= now() then
        raise exception 'Esta invitación expiró.';
    end if;

    if v_email = '' or lower(v_invite.email) <> v_email then
        raise exception 'El email autenticado no coincide con el email invitado.';
    end if;

    if v_invite.platform_bootstrap then
        if exists (
            select 1
            from public.organization_members om
            where om.organization_id = v_invite.organization_id
              and om.user_id = v_user_id
        ) then
            raise exception 'Tu usuario ya pertenece a esta organización.';
        end if;

        if v_invite.role <> 'owner'
           or v_invite.customer_id is not null
           or not exists (
                select 1
                from public.organizations o
                where o.id = v_invite.organization_id
                  and o.owner_id = v_invite.created_by
           ) then
            raise exception 'La invitación de primer acceso no es válida.';
        end if;

        insert into public.organization_members (organization_id, user_id, role)
        values (v_invite.organization_id, v_user_id, 'owner');

        update public.organizations
           set owner_id = v_user_id
         where id = v_invite.organization_id
           and owner_id = v_invite.created_by;

        if not found then
            raise exception 'La propiedad de la organización ya fue transferida.';
        end if;
    elsif v_invite.role = 'customer' then
        if v_invite.customer_id is null then
            raise exception 'La invitación del cliente no está vinculada a un cliente válido.';
        end if;

        if not exists (
            select 1
            from public.customers c
            where c.id = v_invite.customer_id
              and c.organization_id = v_invite.organization_id
              and c.is_active
        ) then
            raise exception 'El cliente asociado a la invitación no está activo.';
        end if;

        if exists (
            select 1
            from public.customer_users cu
            where cu.organization_id = v_invite.organization_id
              and cu.user_id = v_user_id
              and cu.customer_id <> v_invite.customer_id
        ) then
            raise exception 'Este usuario ya tiene acceso a otro cliente de esta organización.';
        end if;

        insert into public.customer_users (organization_id, customer_id, user_id, role)
        values (v_invite.organization_id, v_invite.customer_id, v_user_id, 'customer')
        on conflict (customer_id, user_id) do nothing;

        insert into public.organization_members (organization_id, user_id, role)
        values (v_invite.organization_id, v_user_id, 'customer')
        on conflict (organization_id, user_id) do nothing;
    else
        if v_invite.role not in ('owner', 'admin', 'operator', 'viewer') then
            raise exception 'El rol de invitación no es válido.';
        end if;

        if exists (
            select 1
            from public.organization_members om
            where om.organization_id = v_invite.organization_id
              and om.user_id = v_user_id
        ) then
            raise exception 'Tu usuario ya pertenece a esta organización.';
        end if;

        insert into public.organization_members (organization_id, user_id, role)
        values (v_invite.organization_id, v_user_id, v_invite.role);
    end if;

    update public.organization_member_invites
       set consumed_at = now()
     where id = v_invite.id;

    return query
    select v_invite.organization_id, v_invite.role;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.approve_organization_driver(p_organization_id uuid, p_conductor_id uuid)
 RETURNS organization_drivers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
    v_driver public.organization_drivers;
begin
    if auth.uid() is null
       or not public.can_manage_membership(p_organization_id, auth.uid()) then
        raise exception 'Solo owner/admin puede aprobar conductores.';
    end if;

    update public.organization_drivers
       set status = 'ACTIVE',
           approved_at = now(),
           approved_by = auth.uid(),
           updated_at = now()
     where organization_id = p_organization_id
       and conductor_id = p_conductor_id
       and status = 'PENDING'
     returning * into v_driver;

    if not found then
        raise exception 'No existe una relación PENDING para aprobar.';
    end if;

    return v_driver;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.audit_customer_visibility_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_catalog'
AS $function$
declare
    v_org_id uuid;
    v_customer_id uuid;
    v_action text;
    v_entity_id uuid;
    v_details jsonb := '{}'::jsonb;
begin
    if tg_table_name = 'customers' then
        v_org_id := coalesce(new.organization_id, old.organization_id);
        v_customer_id := coalesce(new.id, old.id);
        v_entity_id := v_customer_id;
        if tg_op = 'INSERT' then
            v_action := 'customer_created';
        elsif new.is_active is distinct from old.is_active then
            v_action := case when new.is_active then 'customer_activated' else 'customer_deactivated' end;
        else
            return new;
        end if;
    elsif tg_table_name = 'customer_operation_access' then
        v_org_id := coalesce(new.organization_id, old.organization_id);
        v_customer_id := coalesce(new.customer_id, old.customer_id);
        v_entity_id := coalesce(new.id, old.id);
        if tg_op = 'INSERT' and new.active then
            v_action := case when new.is_excluded then 'operation_access_excluded' else 'operation_access_granted' end;
        elsif old.active and not new.active then
            v_action := 'operation_access_revoked';
        else
            return new;
        end if;
        v_details := jsonb_build_object(
            'route_id', new.route_id,
            'trip_id', new.trip_id,
            'is_excluded', new.is_excluded
        );
    elsif tg_table_name = 'organization_member_invites' then
        if new.role <> 'customer' then
            return new;
        end if;
        v_org_id := new.organization_id;
        v_customer_id := new.customer_id;
        v_entity_id := new.id;
        v_action := 'customer_invitation_created';
    elsif tg_table_name = 'customer_users' then
        v_org_id := new.organization_id;
        v_customer_id := new.customer_id;
        v_entity_id := new.user_id;
        v_action := 'customer_user_accepted';
    else
        raise exception 'Tabla no soportada para auditoría de visibilidad.';
    end if;

    insert into public.customer_visibility_audit (
        organization_id, customer_id, actor_user_id, action, entity_id, details
    )
    values (
        v_org_id,
        v_customer_id,
        auth.uid(),
        v_action,
        v_entity_id,
        v_details
    );

    return null;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.can_manage_membership(p_organization_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
    select exists (
        select 1
        from public.organizations o
        where o.id = p_organization_id
          and o.owner_id = p_user_id
    )
    or exists (
        select 1
        from public.organization_members om
        where om.organization_id = p_organization_id
          and om.user_id = p_user_id
          and om.role = 'admin'
    );
$function$
;
CREATE OR REPLACE FUNCTION public.can_read_membership(p_organization_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
    select exists (
        select 1
        from public.organizations o
        where o.id = p_organization_id
          and o.owner_id = p_user_id
    )
    or exists (
        select 1
        from public.organization_members om
        where om.organization_id = p_organization_id
          and om.user_id = p_user_id
          and om.role in ('owner', 'admin')
    );
$function$
;
CREATE OR REPLACE FUNCTION public.complete_organization_driver_onboarding(p_token text, p_nombre text, p_rut text, p_telefono text, p_ciudad text, p_tipo_licencia text, p_licencia text, p_licencia_vencimiento date, p_patente text, p_conductor_documents jsonb DEFAULT '[]'::jsonb, p_tracto_documents jsonb DEFAULT '[]'::jsonb)
 RETURNS TABLE(conductor_id uuid, driver_id text, organization_id uuid, status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_catalog'
AS $function$
declare
    v_invite public.organization_driver_invites%rowtype;
    v_conductor public.conductores%rowtype;
    v_tracto public.tractos%rowtype;
    v_token_hash text;
    v_document jsonb;
begin
    if coalesce(trim(p_token), '') = ''
       or coalesce(trim(p_nombre), '') = ''
       or coalesce(trim(p_rut), '') = ''
       or coalesce(trim(p_telefono), '') = ''
       or coalesce(trim(p_ciudad), '') = ''
       or coalesce(trim(p_tipo_licencia), '') = ''
       or coalesce(trim(p_licencia), '') = ''
       or p_licencia_vencimiento is null
       or coalesce(trim(p_patente), '') = '' then
        raise exception 'Todos los datos obligatorios del onboarding son requeridos.';
    end if;

    if jsonb_typeof(coalesce(p_conductor_documents, '[]'::jsonb)) <> 'array'
       or jsonb_typeof(coalesce(p_tracto_documents, '[]'::jsonb)) <> 'array' then
        raise exception 'El formato de documentos no es válido.';
    end if;

    v_token_hash := encode(digest(trim(p_token), 'sha256'), 'hex');

    select invite_row.*
      into v_invite
      from public.organization_driver_invites as invite_row
     where invite_row.token_hash = v_token_hash
     for update;

    if not found then
        raise exception 'La invitación no existe o no es válida.';
    end if;

    if v_invite.consumed_at is not null then
        raise exception 'La invitación ya fue utilizada.';
    end if;

    if v_invite.expires_at <= now() then
        raise exception 'La invitación ha expirado.';
    end if;

    select conductor_row.*
      into v_conductor
      from public.conductores as conductor_row
     where conductor_row.rut = trim(p_rut)
     limit 1
     for update;

    if found then
        update public.conductores as conductor_target
           set nombre = trim(p_nombre),
               telefono = trim(p_telefono),
               ciudad = trim(p_ciudad),
               tipo_licencia = trim(p_tipo_licencia),
               licencia = trim(p_licencia),
               licencia_vencimiento = p_licencia_vencimiento,
               estado = 'Disponible'
         where conductor_target.id = v_conductor.id
         returning conductor_target.* into v_conductor;
    else
        insert into public.conductores (
            nombre, rut, telefono, ciudad, tipo_licencia,
            licencia, licencia_vencimiento, estado, patente_habitual
        )
        values (
            trim(p_nombre), trim(p_rut), trim(p_telefono), trim(p_ciudad),
            trim(p_tipo_licencia), trim(p_licencia), p_licencia_vencimiento,
            'Disponible', upper(trim(p_patente))
        )
        returning conductores.* into v_conductor;
    end if;

    select tracto_row.*
      into v_tracto
      from public.tractos as tracto_row
     where tracto_row.patente = upper(trim(p_patente))
     limit 1
     for update;

    if found then
        update public.tractos as tracto_target
           set estado = 'Disponible'
         where tracto_target.id = v_tracto.id
         returning tracto_target.* into v_tracto;
    else
        insert into public.tractos (patente, estado)
        values (upper(trim(p_patente)), 'Disponible')
        returning tractos.* into v_tracto;
    end if;

    update public.conductores as conductor_target
       set tracto_id = v_tracto.id,
           patente_habitual = upper(trim(p_patente))
     where conductor_target.id = v_conductor.id
     returning conductor_target.* into v_conductor;

    if not found then
        raise exception 'No fue posible asociar el equipo al conductor.';
    end if;

    for v_document in
        select value from jsonb_array_elements(p_conductor_documents)
    loop
        if coalesce(trim(v_document->>'tipo_documento'), '') = ''
           or coalesce(trim(v_document->>'storage_path'), '') = '' then
            raise exception 'Metadata de documento de conductor incompleta.';
        end if;

        insert into public.conductor_documentos (
            conductor_id, tipo_documento, storage_path, nombre_archivo,
            mime_type, tamano_bytes, estado_revision
        )
        values (
            v_conductor.id,
            v_document->>'tipo_documento',
            v_document->>'storage_path',
            nullif(v_document->>'nombre_archivo', ''),
            nullif(v_document->>'mime_type', ''),
            nullif(v_document->>'tamano_bytes', '')::bigint,
            'Pendiente'
        );
    end loop;

    for v_document in
        select value from jsonb_array_elements(p_tracto_documents)
    loop
        if coalesce(trim(v_document->>'tipo_documento'), '') = ''
           or coalesce(trim(v_document->>'storage_path'), '') = '' then
            raise exception 'Metadata de documento de equipo incompleta.';
        end if;

        insert into public.tracto_documentos (
            tracto_id, tipo_documento, storage_path, nombre_archivo,
            mime_type, tamano_bytes, estado_revision
        )
        values (
            v_tracto.id,
            v_document->>'tipo_documento',
            v_document->>'storage_path',
            nullif(v_document->>'nombre_archivo', ''),
            nullif(v_document->>'mime_type', ''),
            nullif(v_document->>'tamano_bytes', '')::bigint,
            'Pendiente'
        );
    end loop;

    insert into public.organization_drivers as driver_link (
        organization_id, conductor_id, status, invited_at, updated_at
    )
    values (
        v_invite.organization_id, v_conductor.id, 'PENDING',
        v_invite.created_at, now()
    )
    on conflict on constraint organization_drivers_pkey do update
        set updated_at = now();

    update public.organization_driver_invites as invite_target
       set consumed_at = now(),
           consumed_conductor_id = v_conductor.id
     where invite_target.id = v_invite.id
       and invite_target.consumed_at is null;

    if not found then
        raise exception 'La invitación ya fue utilizada.';
    end if;

    return query
    select v_conductor.id,
           v_conductor.driver_id,
           v_invite.organization_id,
           'PENDING'::text;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.consume_organization_driver_invite(p_token text, p_nombre text, p_rut text, p_telefono text, p_ciudad text DEFAULT NULL::text, p_tipo_licencia text DEFAULT NULL::text, p_patente_habitual text DEFAULT NULL::text)
 RETURNS TABLE(conductor_id uuid, organization_id uuid, status text, driver_id text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_catalog'
AS $function$
declare
    v_invite public.organization_driver_invites%rowtype;
    v_conductor public.conductores%rowtype;
    v_token_hash text;
begin
    if coalesce(trim(p_token), '') = ''
       or coalesce(trim(p_nombre), '') = ''
       or coalesce(trim(p_rut), '') = ''
       or coalesce(trim(p_telefono), '') = '' then
        raise exception 'Token y datos de identidad son obligatorios.';
    end if;

    v_token_hash := encode(digest(trim(p_token), 'sha256'), 'hex');

    select *
      into v_invite
      from public.organization_driver_invites as invite_row
     where invite_row.token_hash = v_token_hash
     for update;

    if not found then
        raise exception 'La invitación no existe o no es válida.';
    end if;

    if v_invite.consumed_at is not null then
        raise exception 'La invitación ya fue utilizada.';
    end if;

    if v_invite.expires_at <= now() then
        raise exception 'La invitación ha expirado.';
    end if;

    select *
      into v_conductor
      from public.conductores as conductor_row
     where conductor_row.rut = trim(p_rut)
     limit 1
     for update;

    if found then
        update public.conductores as conductor_target
           set nombre = coalesce(nullif(trim(p_nombre), ''), conductor_target.nombre),
               telefono = coalesce(nullif(trim(p_telefono), ''), conductor_target.telefono),
               ciudad = coalesce(nullif(trim(p_ciudad), ''), conductor_target.ciudad),
               tipo_licencia = coalesce(nullif(trim(p_tipo_licencia), ''), conductor_target.tipo_licencia),
               patente_habitual = coalesce(nullif(trim(p_patente_habitual), ''), conductor_target.patente_habitual)
         where conductor_target.id = v_conductor.id
         returning * into v_conductor;
    else
        insert into public.conductores (
            nombre,
            rut,
            telefono,
            ciudad,
            tipo_licencia,
            patente_habitual
        )
        values (
            trim(p_nombre),
            trim(p_rut),
            trim(p_telefono),
            nullif(trim(p_ciudad), ''),
            nullif(trim(p_tipo_licencia), ''),
            nullif(trim(p_patente_habitual), '')
        )
        returning * into v_conductor;
    end if;

    insert into public.organization_drivers as driver_link (
        organization_id,
        conductor_id,
        status,
        invited_at,
        updated_at
    )
    values (
        v_invite.organization_id,
        v_conductor.id,
        'PENDING',
        v_invite.created_at,
        now()
    )
    on conflict on constraint organization_drivers_pkey do update
        set updated_at = now();

    update public.organization_driver_invites as invite_target
       set consumed_at = now(),
           consumed_conductor_id = v_conductor.id
     where invite_target.id = v_invite.id
       and invite_target.consumed_at is null;

    if not found then
        raise exception 'La invitación ya fue utilizada.';
    end if;

    return query
    select driver_link.conductor_id,
           driver_link.organization_id,
           driver_link.status,
           v_conductor.driver_id
      from public.organization_drivers as driver_link
     where driver_link.organization_id = v_invite.organization_id
       and driver_link.conductor_id = v_conductor.id;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.create_customer(p_name text, p_contact_name text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text)
 RETURNS TABLE(customer_id uuid, organization_id uuid, customer_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
    v_user_id uuid := auth.uid();
    v_name text := btrim(coalesce(p_name, ''));
    v_contact_name text := btrim(coalesce(p_contact_name, ''));
    v_email text := lower(btrim(coalesce(p_email, '')));
    v_phone text := btrim(coalesce(p_phone, ''));
    v_org_id uuid;
    v_customer_id uuid;
begin
    if v_user_id is null then
        raise exception 'Debes iniciar sesión para crear un cliente.';
    end if;

    if v_name = '' then
        raise exception 'El nombre del cliente es obligatorio.';
    end if;

    if length(v_name) > 150 then
        raise exception 'El nombre del cliente no puede superar 150 caracteres.';
    end if;

    select o.id
      into v_org_id
      from public.organizations o
     where o.owner_id = v_user_id
        or exists (
            select 1
            from public.organization_members om
            where om.organization_id = o.id
              and om.user_id = v_user_id
              and om.role in ('owner', 'admin')
        )
     order by (o.owner_id = v_user_id) desc, o.created_at
     limit 1;

    if v_org_id is null then
        raise exception 'No tienes permisos para crear clientes.';
    end if;

    insert into public.customers (
        organization_id,
        name,
        contact_name,
        email,
        phone,
        created_by
    )
    values (
        v_org_id,
        v_name,
        nullif(v_contact_name, ''),
        nullif(v_email, ''),
        nullif(v_phone, ''),
        v_user_id
    )
    returning id into v_customer_id;

    return query
    select v_customer_id, v_org_id, v_name;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.create_customer_for_organization(p_organization_id uuid, p_name text, p_contact_name text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text)
 RETURNS TABLE(customer_id uuid, organization_id uuid, customer_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
    v_user_id uuid := auth.uid();
    v_name text := btrim(coalesce(p_name, ''));
    v_contact_name text := btrim(coalesce(p_contact_name, ''));
    v_email text := lower(btrim(coalesce(p_email, '')));
    v_phone text := btrim(coalesce(p_phone, ''));
    v_customer_id uuid;
begin
    if v_user_id is null then
        raise exception 'Debes iniciar sesión para crear un cliente.';
    end if;

    if p_organization_id is null
       or not public.user_has_org_role(p_organization_id, array['owner', 'admin']) then
        raise exception 'No tienes permisos para crear clientes en esta organización.';
    end if;

    if v_name = '' then
        raise exception 'El nombre del cliente es obligatorio.';
    end if;

    if length(v_name) > 150 then
        raise exception 'El nombre del cliente no puede superar 150 caracteres.';
    end if;

    if v_email <> '' and v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
        raise exception 'Ingresa un email válido.';
    end if;

    insert into public.customers (
        organization_id, name, contact_name, email, phone, created_by
    )
    values (
        p_organization_id,
        v_name,
        nullif(v_contact_name, ''),
        nullif(v_email, ''),
        nullif(v_phone, ''),
        v_user_id
    )
    returning id into v_customer_id;

    return query
    select v_customer_id, p_organization_id, v_name;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.create_customer_member_invite(p_email text, p_customer_id uuid)
 RETURNS TABLE(invite_id uuid, organization_id uuid, organization_name text, role text, invite_token text, invite_url text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_catalog'
AS $function$
declare
    v_user_id uuid := auth.uid();
    v_email text := lower(btrim(coalesce(p_email, '')));
    v_organization_id uuid;
    v_organization_name text;
    v_invite_id uuid;
    v_token text;
begin
    if v_user_id is null then
        raise exception 'Debes iniciar sesión para invitar clientes.';
    end if;

    if v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
        raise exception 'Ingresa un email válido.';
    end if;

    select c.organization_id, o.name
      into v_organization_id, v_organization_name
      from public.customers c
      join public.organizations o on o.id = c.organization_id
     where c.id = p_customer_id
       and c.is_active
       and (
           o.owner_id = v_user_id
           or exists (
               select 1
               from public.organization_members om
               where om.organization_id = c.organization_id
                 and om.user_id = v_user_id
                 and om.role = 'admin'
           )
       );

    if v_organization_id is null then
        raise exception 'No tienes permisos para invitar usuarios a este cliente.';
    end if;

    v_token := translate(encode(gen_random_bytes(32), 'base64'), E'+/=', '-_');
    v_token := replace(v_token, E'
', '');

    insert into public.organization_member_invites (
        organization_id, email, role, customer_id, token_hash, expires_at, created_by
    )
    values (
        v_organization_id,
        v_email,
        'customer',
        p_customer_id,
        encode(digest(v_token, 'sha256'), 'hex'),
        now() + interval '7 days',
        v_user_id
    )
    returning id into v_invite_id;

    return query
    select
        v_invite_id,
        v_organization_id,
        v_organization_name,
        'customer'::text,
        v_token,
        'login.html?invite=' || v_token;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.create_member_invite(p_email text, p_role text)
 RETURNS TABLE(invite_id uuid, organization_id uuid, organization_name text, role text, invite_token text, invite_url text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_catalog'
AS $function$
declare
    v_user_id uuid := auth.uid();
    v_email text := lower(btrim(coalesce(p_email, '')));
    v_role text := lower(btrim(coalesce(p_role, '')));
    v_organization_id uuid;
    v_organization_name text;
    v_invite_id uuid;
    v_token text;
    v_expires_at timestamptz := now() + interval '7 days';
begin
    if v_user_id is null then
        raise exception 'Debes iniciar sesión para invitar colaboradores.';
    end if;

    if v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
        raise exception 'Ingresa un email válido.';
    end if;

    if v_role not in ('admin', 'operator', 'viewer') then
        raise exception 'El rol debe ser admin, operator o viewer.';
    end if;

    select o.id, o.name
      into v_organization_id, v_organization_name
      from public.organizations o
     where o.owner_id = v_user_id
        or exists (
            select 1
              from public.organization_members om
             where om.organization_id = o.id
               and om.user_id = v_user_id
               and om.role = 'admin'
        )
     order by (o.owner_id = v_user_id) desc, o.created_at
     limit 1;

    if v_organization_id is null then
        raise exception 'No tienes permisos para invitar colaboradores.';
    end if;

    v_token := translate(encode(gen_random_bytes(32), 'base64'), E'+/=', '-_');
    v_token := replace(v_token, E'
', '');

    insert into public.organization_member_invites (
        organization_id, email, role, token_hash, expires_at, created_by
    )
    values (
        v_organization_id,
        v_email,
        v_role,
        encode(digest(v_token, 'sha256'), 'hex'),
        v_expires_at,
        v_user_id
    )
    returning id into v_invite_id;

    return query
    select
        v_invite_id,
        v_organization_id,
        v_organization_name,
        v_role,
        v_token,
        'login.html?invite=' || v_token;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.create_organization_driver_invite(p_organization_id uuid)
 RETURNS TABLE(invite_id uuid, invite_token text, expires_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_catalog'
AS $function$
declare
    v_token text;
    v_invite_id uuid;
    v_expires_at timestamptz;
begin
    if auth.uid() is null
       or not public.can_manage_membership(p_organization_id, auth.uid()) then
        raise exception 'No tienes permisos para invitar conductores.';
    end if;

    v_token := encode(gen_random_bytes(32), 'hex');
    v_expires_at := now() + interval '24 hours';

    insert into public.organization_driver_invites (
        organization_id,
        token_hash,
        expires_at,
        created_by
    )
    values (
        p_organization_id,
        encode(digest(v_token, 'sha256'), 'hex'),
        v_expires_at,
        auth.uid()
    )
    returning id into v_invite_id;

    return query
    select v_invite_id, v_token, v_expires_at;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.create_organization_for_current_user(p_name text)
 RETURNS TABLE(organization_id uuid, organization_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
    v_user_id uuid := auth.uid();
    v_organization_id uuid;
    v_name text := btrim(coalesce(p_name, ''));
    v_now timestamptz := now();
begin
    if v_user_id is null then
        raise exception 'Debes iniciar sesión para crear una organización.';
    end if;

    perform pg_advisory_xact_lock(hashtextextended(v_user_id::text, 0));

    if v_name = '' then
        raise exception 'El nombre de la empresa es obligatorio.';
    end if;

    if length(v_name) > 120 then
        raise exception 'El nombre de la empresa no puede superar 120 caracteres.';
    end if;

    if exists (
        select 1 from public.organization_members om where om.user_id = v_user_id
    ) then
        raise exception 'Tu usuario ya pertenece a una organización.';
    end if;

    insert into public.organizations (name, owner_id)
    values (v_name, v_user_id)
    returning id into v_organization_id;

    insert into public.organization_members (organization_id, user_id, role)
    values (v_organization_id, v_user_id, 'owner');

    insert into public.organization_subscriptions (
        organization_id, plan, status, trial_started_at, trial_ends_at
    )
    values (
        v_organization_id, 'starter', 'trialing', v_now, v_now + interval '14 days'
    );

    return query select v_organization_id, v_name;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.create_platform_organization_invite(p_organization_name text, p_email text)
 RETURNS TABLE(organization_id uuid, organization_name text, invite_email text, invite_token text, invite_url text, expires_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_catalog'
AS $function$
declare
    v_name text := btrim(coalesce(p_organization_name, ''));
    v_email text := lower(btrim(coalesce(p_email, '')));
    v_organization_id uuid;
    v_token text;
    v_expires_at timestamptz := now() + interval '7 days';
begin
    if not public.is_fleetops_platform_owner() then
        raise exception 'No tienes permiso para administrar FleetOps.';
    end if;

    if v_name = '' or length(v_name) > 120 then
        raise exception 'Ingresa un nombre de empresa de hasta 120 caracteres.';
    end if;

    if v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
        raise exception 'Ingresa un email válido para el primer usuario.';
    end if;

    insert into public.organizations (name, owner_id)
    values (v_name, auth.uid())
    returning id into v_organization_id;

    v_token := translate(encode(gen_random_bytes(32), 'base64'), E'+/=', '-_');
    v_token := replace(v_token, E'
', '');

    insert into public.organization_member_invites (
        organization_id,
        email,
        role,
        customer_id,
        platform_bootstrap,
        token_hash,
        expires_at,
        created_by
    )
    values (
        v_organization_id,
        v_email,
        'owner',
        null,
        true,
        encode(digest(v_token, 'sha256'), 'hex'),
        v_expires_at,
        auth.uid()
    );

    return query
    select
        v_organization_id,
        v_name,
        v_email,
        v_token,
        'login.html?invite=' || v_token,
        v_expires_at;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.customer_has_trip_access(p_trip_id uuid, p_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
    select
        p_user_id = auth.uid()
        and exists (
            select 1
            from public.viajes v
            left join public.routes r on r.id = v.route_id
            join public.customer_users cu
              on cu.user_id = auth.uid()
             and cu.organization_id = coalesce(v.empresa_id, r.organization_id)
            join public.customers c
              on c.id = cu.customer_id
             and c.organization_id = cu.organization_id
             and c.is_active
            where v.id = p_trip_id
              and not exists (
                  select 1
                  from public.customer_operation_access exclusion
                  where exclusion.customer_id = c.id
                    and exclusion.organization_id = cu.organization_id
                    and exclusion.trip_id = v.id
                    and exclusion.active
                    and exclusion.is_excluded
              )
              and (
                  exists (
                      select 1
                      from public.customer_operation_access direct_access
                      where direct_access.customer_id = c.id
                        and direct_access.organization_id = cu.organization_id
                        and direct_access.trip_id = v.id
                        and direct_access.active
                        and not direct_access.is_excluded
                  )
                  or (
                      exists (
                          select 1
                          from public.customer_operation_access route_access
                          where route_access.customer_id = c.id
                            and route_access.organization_id = cu.organization_id
                            and route_access.route_id = v.route_id
                            and route_access.active
                            and not route_access.is_excluded
                      )
                  )
              )
        );
$function$
;
CREATE OR REPLACE FUNCTION public.finalizar_viaje(p_patente text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
    patente_normalizada text;
    filas_actualizadas integer;
begin

    patente_normalizada :=
        normalize_plate(p_patente);

    update public.viajes
    set
        estado = 'FINALIZADO',
        fecha_finalizacion = now()
    where
        patente = patente_normalizada
        and estado = 'ACTIVO';

    get diagnostics
        filas_actualizadas = row_count;

    if filas_actualizadas = 0 then
        return false;
    end if;

    return true;

end;
$function$
;
CREATE OR REPLACE FUNCTION public.finalizar_viaje(p_viaje_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
    v_organization_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Debe iniciar sesión para autorizar la finalización.';
    end if;

    select coalesce(v.empresa_id, r.organization_id)
      into v_organization_id
      from public.viajes v
      left join public.routes r on r.id = v.route_id
     where v.id = p_viaje_id
     limit 1;

    if v_organization_id is null then
        raise exception 'No existe un viaje válido para finalizar.';
    end if;

    if not public.user_has_org_role(v_organization_id, array['owner', 'admin', 'operator']) then
        raise exception 'No tienes permisos para autorizar la finalización de este viaje.';
    end if;

    update public.viajes
       set estado = 'Finalizado',
           fecha_finalizacion = now()
     where id = p_viaje_id
       and fecha_finalizacion is null;

    return true;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.get_customer_context(p_user_id uuid DEFAULT auth.uid())
 RETURNS TABLE(organization_id uuid, customer_id uuid, customer_name text, role text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
    select cu.organization_id, c.id, c.name, cu.role
    from public.customer_users cu
    join public.customers c
      on c.id = cu.customer_id
     and c.organization_id = cu.organization_id
     and c.is_active
    where p_user_id = auth.uid()
      and cu.user_id = auth.uid()
      and 1 = (
          select count(distinct customer_scope.organization_id)
          from public.customer_users customer_scope
          where customer_scope.user_id = auth.uid()
      );
$function$
;
CREATE OR REPLACE FUNCTION public.get_customer_context_for_org(p_organization_id uuid)
 RETURNS TABLE(organization_id uuid, customer_id uuid, customer_name text, role text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
    select cu.organization_id, c.id, c.name, cu.role
    from public.customer_users cu
    join public.customers c
      on c.id = cu.customer_id
     and c.organization_id = cu.organization_id
     and c.is_active
    where cu.organization_id = p_organization_id
      and cu.user_id = auth.uid();
$function$
;
CREATE OR REPLACE FUNCTION public.get_customer_dashboard_summary(p_user_id uuid DEFAULT auth.uid())
 RETURNS TABLE(customer_id uuid, customer_name text, active_trips bigint, en_ruta bigint, esperando_carga bigint, cargando bigint, esperando_descarga bigint, descargando bigint, incidentes bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
    select
        c.id,
        c.name,
        count(*) filter (where v.trip_status is not null and v.trip_status <> 'Finalizado'),
        count(*) filter (where v.trip_status = 'En ruta'),
        count(*) filter (where v.trip_status = 'Esperando carga'),
        count(*) filter (where v.trip_status = 'Cargando'),
        count(*) filter (where v.trip_status = 'Esperando descarga'),
        count(*) filter (where v.trip_status = 'Descargando'),
        count(*) filter (where v.trip_status = 'Incidente')
    from public.customer_users cu
    join public.customers c
      on c.id = cu.customer_id
     and c.organization_id = cu.organization_id
     and c.is_active
    left join public.get_customer_visible_operations(auth.uid()) v
      on v.customer_id = c.id
    where p_user_id = auth.uid()
      and cu.user_id = auth.uid()
      and 1 = (
          select count(distinct customer_scope.organization_id)
          from public.customer_users customer_scope
          where customer_scope.user_id = auth.uid()
      )
    group by c.id, c.name;
$function$
;
CREATE OR REPLACE FUNCTION public.get_customer_member_invite_context(p_token text)
 RETURNS TABLE(organization_name text, customer_name text, invite_status text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_catalog'
AS $function$
    select
        o.name,
        c.name,
        case
            when invite.consumed_at is not null then 'used'
            when invite.expires_at <= now() then 'expired'
            else 'pending'
        end
    from public.organization_member_invites invite
    join public.organizations o on o.id = invite.organization_id
    join public.customers c
      on c.id = invite.customer_id
     and c.organization_id = invite.organization_id
    where invite.token_hash = encode(digest(btrim(coalesce(p_token, '')), 'sha256'), 'hex')
      and invite.role = 'customer'
    limit 1;
$function$
;
CREATE OR REPLACE FUNCTION public.get_customer_visible_operations(p_user_id uuid DEFAULT auth.uid())
 RETURNS TABLE(trip_id uuid, customer_id uuid, customer_name text, route_id uuid, route_name text, trip_status text, route_label text, patente text, conductor text, fecha_inicio timestamp with time zone, last_report_at timestamp with time zone, last_report_state text, last_report_observacion text, incident_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
    select distinct
        v.id,
        c.id,
        c.name,
        coalesce(v.route_id, coa.route_id),
        r.name,
        case
            when v.fecha_finalizacion is not null then 'Finalizado'
            else coalesce(last_report.estado, v.estado, 'En ruta')
        end,
        v.ruta,
        v.patente,
        v.conductor,
        v.fecha_inicio,
        last_report."timestamp",
        last_report.estado,
        last_report.observacion,
        (
            select count(*)
            from public.reportes rp
            where rp.viaje_id = v.id
              and rp.estado = 'Incidente'
        )
    from public.customer_operation_access coa
    join public.customer_users cu
      on cu.customer_id = coa.customer_id
     and cu.user_id = auth.uid()
     and cu.organization_id = coa.organization_id
    join public.customers c
      on c.id = cu.customer_id
     and c.organization_id = cu.organization_id
     and c.is_active
    join public.viajes v
      on (coa.trip_id = v.id or coa.route_id = v.route_id)
    left join public.routes r on r.id = coalesce(v.route_id, coa.route_id)
    left join lateral (
        select rep."timestamp", rep.estado, rep.observacion
        from public.reportes rep
        where rep.viaje_id = v.id
        order by rep."timestamp" desc
        limit 1
    ) last_report on true
    where p_user_id = auth.uid()
      and 1 = (
          select count(distinct customer_scope.organization_id)
          from public.customer_users customer_scope
          where customer_scope.user_id = auth.uid()
      )
      and coa.active
      and not coa.is_excluded
      and coalesce(v.empresa_id, r.organization_id) = coa.organization_id
      and not exists (
          select 1
          from public.customer_operation_access exclusion
          where exclusion.customer_id = c.id
            and exclusion.organization_id = coa.organization_id
            and exclusion.trip_id = v.id
            and exclusion.active
            and exclusion.is_excluded
      );
$function$
;
CREATE OR REPLACE FUNCTION public.get_customer_visible_operations_for_org(p_organization_id uuid)
 RETURNS TABLE(trip_id uuid, customer_id uuid, customer_name text, route_id uuid, route_name text, trip_status text, route_label text, patente text, conductor text, fecha_inicio timestamp with time zone, last_report_at timestamp with time zone, last_report_state text, last_report_observacion text, incident_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
    select distinct
        v.id,
        c.id,
        c.name,
        coalesce(v.route_id, coa.route_id),
        r.name,
        case
            when v.fecha_finalizacion is not null then 'Finalizado'
            else coalesce(last_report.estado, v.estado, 'En ruta')
        end,
        v.ruta,
        v.patente,
        v.conductor,
        v.fecha_inicio,
        last_report."timestamp",
        last_report.estado,
        last_report.observacion,
        (
            select count(*)
            from public.reportes rp
            where rp.viaje_id = v.id
              and rp.estado = 'Incidente'
        )
    from public.customer_operation_access coa
    join public.customer_users cu
      on cu.customer_id = coa.customer_id
     and cu.user_id = auth.uid()
     and cu.organization_id = p_organization_id
     and cu.organization_id = coa.organization_id
    join public.customers c
      on c.id = cu.customer_id
     and c.organization_id = cu.organization_id
     and c.is_active
    join public.viajes v
      on (coa.trip_id = v.id or coa.route_id = v.route_id)
    left join public.routes r on r.id = coalesce(v.route_id, coa.route_id)
    left join lateral (
        select rep."timestamp", rep.estado, rep.observacion
        from public.reportes rep
        where rep.viaje_id = v.id
        order by rep."timestamp" desc
        limit 1
    ) last_report on true
    where coa.active
      and not coa.is_excluded
      and coalesce(v.empresa_id, r.organization_id) = p_organization_id
      and not exists (
          select 1
          from public.customer_operation_access exclusion
          where exclusion.customer_id = c.id
            and exclusion.organization_id = p_organization_id
            and exclusion.trip_id = v.id
            and exclusion.active
            and exclusion.is_excluded
      );
$function$
;
CREATE OR REPLACE FUNCTION public.get_member_invite_context(p_token text)
 RETURNS TABLE(organization_name text, role text, invite_status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_catalog'
AS $function$
declare
    v_invite public.organization_member_invites;
begin
    select *
      into v_invite
      from public.organization_member_invites
     where token_hash = encode(digest(btrim(coalesce(p_token, '')), 'sha256'), 'hex')
     limit 1;

    if not found then
        raise exception 'La invitación no existe.';
    end if;

    return query
    select
        o.name,
        v_invite.role,
        case
            when v_invite.consumed_at is not null then 'used'
            when v_invite.expires_at <= now() then 'expired'
            else 'pending'
        end
    from public.organizations o
    where o.id = v_invite.organization_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.is_fleetops_platform_owner()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
    select auth.uid() is not null
       and lower(btrim(coalesce(auth.email(), ''))) in (
            select owner.email
            from public.fleetops_platform_owners owner
       );
$function$
;
CREATE OR REPLACE FUNCTION public.list_current_user_organization_team()
 RETURNS TABLE(organization_id uuid, organization_name text, member_id uuid, email text, display_name text, role text, status text, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
    select
        o.id,
        o.name,
        u.id,
        lower(u.email),
        coalesce(
            nullif(u.raw_user_meta_data ->> 'full_name', ''),
            nullif(u.raw_user_meta_data ->> 'name', ''),
            lower(u.email)
        ),
        om.role,
        'active',
        om.created_at
    from public.organizations o
    join public.organization_members om on om.organization_id = o.id
    join auth.users u on u.id = om.user_id
    where o.owner_id = auth.uid()
       or exists (
           select 1
           from public.organization_members viewer
           where viewer.organization_id = o.id
             and viewer.user_id = auth.uid()
             and viewer.role in ('owner', 'admin')
       )
    union all
    select
        o.id,
        o.name,
        null,
        i.email,
        i.email,
        i.role,
        case
            when i.consumed_at is not null then 'active'
            when i.expires_at <= now() then 'expired'
            else 'pending'
        end,
        i.created_at
    from public.organization_member_invites i
    join public.organizations o on o.id = i.organization_id
    where i.consumed_at is null
      and i.expires_at > now()
      and (o.owner_id = auth.uid()
        or exists (
            select 1
            from public.organization_members viewer
            where viewer.organization_id = o.id
              and viewer.user_id = auth.uid()
              and viewer.role in ('owner', 'admin')
        ));
$function$
;
CREATE OR REPLACE FUNCTION public.list_fleetops_platform_organizations()
 RETURNS TABLE(organization_id uuid, organization_name text, created_at timestamp with time zone, first_user_email text, invite_status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
begin
    if not public.is_fleetops_platform_owner() then
        raise exception 'No tienes permiso para administrar FleetOps.';
    end if;

    return query
    select
        o.id,
        o.name,
        o.created_at,
        invite.email,
        case
            when invite.id is null then 'Sin invitación de plataforma'
            when invite.consumed_at is not null then 'Aceptada'
            when invite.expires_at <= now() then 'Expirada'
            else 'Pendiente'
        end
    from public.organizations o
    left join lateral (
        select i.id, i.email, i.consumed_at, i.expires_at
        from public.organization_member_invites i
        where i.organization_id = o.id
          and i.platform_bootstrap
        order by i.created_at desc
        limit 1
    ) invite on true
    order by o.created_at desc;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.normalize_plate(plate text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    select upper(
        regexp_replace(
            coalesce(plate, ''),
            '[^A-Za-z0-9]',
            '',
            'g'
        )
    );
$function$
;
CREATE OR REPLACE FUNCTION public.reject_organization_driver(p_organization_id uuid, p_conductor_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
begin
    if auth.uid() is null
       or not public.can_manage_membership(p_organization_id, auth.uid()) then
        raise exception 'Solo owner/admin puede rechazar conductores.';
    end if;

    delete from public.organization_drivers
     where organization_id = p_organization_id
       and conductor_id = p_conductor_id
       and status = 'PENDING';

    return found;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.resolve_organization_driver_invite(p_token text)
 RETURNS TABLE(organization_id uuid, organization_name text, expires_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_catalog'
AS $function$
begin
    return query
    select o.id, o.name, i.expires_at
      from public.organization_driver_invites i
      join public.organizations o on o.id = i.organization_id
     where i.token_hash = encode(digest(trim(p_token), 'sha256'), 'hex')
       and i.consumed_at is null
       and i.expires_at > now();
end;
$function$
;
CREATE OR REPLACE FUNCTION public.resolve_viaje_public(p_viaje_id uuid)
 RETURNS TABLE(id uuid, patente text, conductor text, conductor_id uuid, empresa text, empresa_id uuid, ruta text, route_id uuid, estado text, fecha_inicio timestamp with time zone, fecha_finalizacion timestamp with time zone, created_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
    select
        v.id,
        v.patente,
        v.conductor,
        v.conductor_id,
        v.empresa,
        coalesce(v.empresa_id, r.organization_id),
        v.ruta,
        v.route_id,
        v.estado,
        v.fecha_inicio,
        v.fecha_finalizacion,
        v.created_at
    from public.viajes v
    left join public.routes r on r.id = v.route_id
    where v.id = p_viaje_id
      and (
          auth.uid() is null
          or public.user_has_org_role(
              coalesce(v.empresa_id, r.organization_id),
              array['owner', 'admin', 'operator', 'viewer']
          )
          or public.customer_has_trip_access(v.id, auth.uid())
      )
    limit 1;
$function$
;
CREATE OR REPLACE FUNCTION public.set_report_operational_metadata()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
begin
    if tg_op = 'INSERT' then
        new."timestamp" := clock_timestamp();
        new.actor_user_id := auth.uid();
        new.actor_conductor_id := new.conductor_id;
        new.actor_type := case
            when auth.uid() is not null then 'operator'
            when new.conductor_id is not null then 'driver_attributed'
            else 'legacy'
        end;
    else
        new."timestamp" := old."timestamp";
        new.actor_user_id := old.actor_user_id;
        new.actor_conductor_id := old.actor_conductor_id;
        new.actor_type := old.actor_type;
    end if;

    if new.estado <> 'Incidente' then
        new.incident_category := null;
    end if;

    return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.user_has_org_role(p_organization_id uuid, p_roles text[])
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
    v_user_id uuid;
begin
    v_user_id := auth.uid();

    if v_user_id is null or p_organization_id is null then
        return false;
    end if;

    return exists (
        select 1
        from public.organization_members om
        where om.organization_id = p_organization_id
          and om.user_id = v_user_id
          and om.role = any(p_roles)
    )
    or exists (
        select 1
        from public.organizations o
        where o.id = p_organization_id
          and o.owner_id = v_user_id
          and 'owner' = any(p_roles)
    );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.validate_customer_operation_access()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
    v_customer_organization_id uuid;
    v_route_organization_id uuid;
    v_trip_organization_id uuid;
begin
    select c.organization_id
      into v_customer_organization_id
      from public.customers c
     where c.id = new.customer_id;

    if v_customer_organization_id is null
       or v_customer_organization_id <> new.organization_id then
        raise exception 'El cliente debe pertenecer a la organización indicada.';
    end if;

    if new.route_id is not null then
        select r.organization_id
          into v_route_organization_id
          from public.routes r
         where r.id = new.route_id;

        if v_route_organization_id is null
           or v_route_organization_id <> new.organization_id then
            raise exception 'La ruta debe pertenecer a la organización indicada.';
        end if;
    end if;

    if new.trip_id is not null then
        select coalesce(v.empresa_id, r.organization_id)
          into v_trip_organization_id
          from public.viajes v
          left join public.routes r on r.id = v.route_id
         where v.id = new.trip_id;

        if v_trip_organization_id is null
           or v_trip_organization_id <> new.organization_id then
            raise exception 'El viaje debe pertenecer a la organización indicada.';
        end if;
    end if;

    return new;
end;
$function$
;

-- ===== TRIGGERS =====
CREATE TRIGGER audit_customer_visibility_access AFTER INSERT OR UPDATE OF active ON public.customer_operation_access FOR EACH ROW EXECUTE FUNCTION audit_customer_visibility_change();
CREATE TRIGGER audit_customer_visibility_customer AFTER INSERT OR UPDATE OF is_active ON public.customers FOR EACH ROW EXECUTE FUNCTION audit_customer_visibility_change();
CREATE TRIGGER audit_customer_visibility_invite AFTER INSERT ON public.organization_member_invites FOR EACH ROW EXECUTE FUNCTION audit_customer_visibility_change();
CREATE TRIGGER audit_customer_visibility_user AFTER INSERT ON public.customer_users FOR EACH ROW EXECUTE FUNCTION audit_customer_visibility_change();
CREATE TRIGGER set_report_operational_metadata BEFORE INSERT OR UPDATE ON public.reportes FOR EACH ROW EXECUTE FUNCTION set_report_operational_metadata();
CREATE TRIGGER validate_customer_operation_access BEFORE INSERT OR UPDATE ON public.customer_operation_access FOR EACH ROW EXECUTE FUNCTION validate_customer_operation_access();

-- ===== POLÍTICAS RLS =====
create policy authenticated_manage_conductor_documentos on public.conductor_documentos as PERMISSIVE for ALL to authenticated using (true) with check (true);
create policy authenticated_read_conductor_documentos on public.conductor_documentos as PERMISSIVE for SELECT to authenticated using (true);
create policy public_read_conductores on public.conductores as PERMISSIVE for SELECT to public using (true);
create policy customer_access_manage_internal_only on public.customer_operation_access as PERMISSIVE for ALL to authenticated using (user_has_org_role(organization_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text])) with check ((user_has_org_role(organization_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text]) AND (organization_id IS NOT NULL) AND (customer_id IS NOT NULL) AND ((route_id IS NOT NULL) OR (trip_id IS NOT NULL))));
create policy customer_access_read_internal_only on public.customer_operation_access as PERMISSIVE for SELECT to authenticated using (user_has_org_role(organization_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text, 'viewer'::text]));
create policy customer_users_manage_internal_only on public.customer_users as PERMISSIVE for ALL to authenticated using (user_has_org_role(organization_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text])) with check ((user_has_org_role(organization_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text]) AND (organization_id IS NOT NULL) AND (role = 'customer'::text)));
create policy customer_users_read_internal_only on public.customer_users as PERMISSIVE for SELECT to authenticated using (user_has_org_role(organization_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text, 'viewer'::text]));
create policy customer_visibility_audit_internal_read on public.customer_visibility_audit as PERMISSIVE for SELECT to authenticated using (user_has_org_role(organization_id, ARRAY['owner'::text, 'admin'::text]));
create policy customers_manage_internal_only on public.customers as PERMISSIVE for ALL to authenticated using (user_has_org_role(organization_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text])) with check ((user_has_org_role(organization_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text]) AND (organization_id IS NOT NULL)));
create policy customers_read_internal_only on public.customers as PERMISSIVE for SELECT to authenticated using (user_has_org_role(organization_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text, 'viewer'::text]));
create policy organization_admins_read_driver_invites on public.organization_driver_invites as PERMISSIVE for SELECT to authenticated using (can_manage_membership(organization_id, auth.uid()));
create policy organization_members_read_drivers on public.organization_drivers as PERMISSIVE for SELECT to authenticated using (user_has_org_role(organization_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text, 'viewer'::text]));
create policy organization_admins_read_member_invites on public.organization_member_invites as PERMISSIVE for SELECT to authenticated using (can_read_membership(organization_id, auth.uid()));
create policy members_read_memberships on public.organization_members as PERMISSIVE for SELECT to authenticated using (((user_id = auth.uid()) OR can_read_membership(organization_id, auth.uid())));
create policy organization_admins_manage_memberships on public.organization_members as PERMISSIVE for ALL to authenticated using (can_manage_membership(organization_id, auth.uid())) with check ((can_manage_membership(organization_id, auth.uid()) AND ((role IS DISTINCT FROM 'owner'::text) OR (EXISTS ( SELECT 1
   FROM organizations o
  WHERE ((o.id = organization_members.organization_id) AND (o.owner_id = auth.uid())))))));
create policy organization_members_read_subscription on public.organization_subscriptions as PERMISSIVE for SELECT to authenticated using (user_has_org_role(organization_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text, 'viewer'::text]));
create policy org_members_read_organizations on public.organizations as PERMISSIVE for SELECT to authenticated using (((owner_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = organizations.id) AND (om.user_id = auth.uid()))))));
create policy org_owner_manage_organizations on public.organizations as PERMISSIVE for ALL to authenticated using ((owner_id = auth.uid())) with check ((owner_id = auth.uid()));
create policy users_create_organizations on public.organizations as PERMISSIVE for INSERT to authenticated with check ((owner_id = auth.uid()));
create policy "FleetOps permitir inserciones" on public.reportes as PERMISSIVE for INSERT to anon with check (true);
create policy "FleetOps permitir lectura" on public.reportes as PERMISSIVE for SELECT to anon using (true);
create policy anon_insert_reportes on public.reportes as PERMISSIVE for INSERT to anon with check (true);
create policy authenticated_insert_reportes on public.reportes as PERMISSIVE for INSERT to authenticated with check (true);
create policy authenticated_read_reportes on public.reportes as PERMISSIVE for SELECT to authenticated using (true);
create policy reportes_customer_visible on public.reportes as PERMISSIVE for SELECT to authenticated using ((EXISTS ( SELECT 1
   FROM viajes v
  WHERE ((v.id = reportes.viaje_id) AND (user_has_org_role(v.empresa_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text, 'viewer'::text]) OR (EXISTS ( SELECT 1
           FROM routes r
          WHERE ((r.id = v.route_id) AND user_has_org_role(r.organization_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text, 'viewer'::text])))) OR customer_has_trip_access(v.id, auth.uid()))))));
create policy routes_manage_by_admin_owner on public.routes as PERMISSIVE for ALL to authenticated using (user_has_org_role(organization_id, ARRAY['owner'::text, 'admin'::text])) with check (user_has_org_role(organization_id, ARRAY['owner'::text, 'admin'::text]));
create policy routes_select_by_org on public.routes as PERMISSIVE for SELECT to authenticated using (user_has_org_role(organization_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text, 'viewer'::text]));
create policy authenticated_manage_tracto_documentos on public.tracto_documentos as PERMISSIVE for ALL to authenticated using (true) with check (true);
create policy authenticated_read_tracto_documentos on public.tracto_documentos as PERMISSIVE for SELECT to authenticated using (true);
create policy authenticated_manage_tractos on public.tractos as PERMISSIVE for ALL to authenticated using (true) with check (true);
create policy authenticated_read_tractos on public.tractos as PERMISSIVE for SELECT to authenticated using (true);
create policy viajes_customer_visible on public.viajes as PERMISSIVE for SELECT to authenticated using ((user_has_org_role(empresa_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text, 'viewer'::text]) OR customer_has_trip_access(id, auth.uid()) OR (EXISTS ( SELECT 1
   FROM routes r
  WHERE ((r.id = viajes.route_id) AND user_has_org_role(r.organization_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text, 'viewer'::text]))))));
create policy viajes_delete_org_roles on public.viajes as PERMISSIVE for DELETE to authenticated using ((user_has_org_role(empresa_id, ARRAY['owner'::text, 'admin'::text]) OR (EXISTS ( SELECT 1
   FROM routes r
  WHERE ((r.id = viajes.route_id) AND user_has_org_role(r.organization_id, ARRAY['owner'::text, 'admin'::text]))))));
create policy viajes_insert_org_roles on public.viajes as PERMISSIVE for INSERT to authenticated with check ((((empresa_id IS NOT NULL) AND user_has_org_role(empresa_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text])) OR ((route_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM routes r
  WHERE ((r.id = viajes.route_id) AND user_has_org_role(r.organization_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text])))))));
create policy viajes_read_org_members on public.viajes as PERMISSIVE for SELECT to authenticated using ((user_has_org_role(empresa_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text, 'viewer'::text]) OR (EXISTS ( SELECT 1
   FROM routes r
  WHERE ((r.id = viajes.route_id) AND user_has_org_role(r.organization_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text, 'viewer'::text]))))));
create policy viajes_update_org_roles on public.viajes as PERMISSIVE for UPDATE to authenticated using ((user_has_org_role(empresa_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text]) OR (EXISTS ( SELECT 1
   FROM routes r
  WHERE ((r.id = viajes.route_id) AND user_has_org_role(r.organization_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text])))))) with check ((((empresa_id IS NOT NULL) AND user_has_org_role(empresa_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text])) OR ((route_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM routes r
  WHERE ((r.id = viajes.route_id) AND user_has_org_role(r.organization_id, ARRAY['owner'::text, 'admin'::text, 'operator'::text])))))));

-- ===== GRANTS TABLAS =====
grant TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT, INSERT on public.conductor_documentos to anon;
grant TRIGGER, REFERENCES, INSERT, TRUNCATE, DELETE, UPDATE, SELECT on public.conductor_documentos to authenticated;
grant INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER on public.conductores to anon;
grant TRIGGER, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, INSERT on public.conductores to authenticated;
grant TRUNCATE, TRIGGER, REFERENCES, DELETE, UPDATE, SELECT, INSERT on public.customer_operation_access to authenticated;
grant TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT, INSERT on public.customer_users to authenticated;
grant SELECT on public.customer_visibility_audit to authenticated;
grant TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT, INSERT on public.customers to authenticated;
grant SELECT on public.organization_driver_invites to authenticated;
grant SELECT on public.organization_drivers to authenticated;
grant REFERENCES, TRUNCATE, INSERT, SELECT, UPDATE, DELETE, TRIGGER on public.organization_member_invites to anon;
grant INSERT, TRUNCATE, REFERENCES, TRIGGER, SELECT, DELETE, UPDATE on public.organization_member_invites to authenticated;
grant INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER on public.organization_members to anon;
grant INSERT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT on public.organization_members to authenticated;
grant SELECT on public.organization_plan_limits to authenticated;
grant TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, INSERT, SELECT on public.organization_subscriptions to anon;
grant UPDATE, INSERT, SELECT, DELETE, TRUNCATE, REFERENCES, TRIGGER on public.organization_subscriptions to authenticated;
grant SELECT, UPDATE, TRIGGER, REFERENCES, TRUNCATE, DELETE, INSERT on public.organizations to anon;
grant REFERENCES, DELETE, TRUNCATE, TRIGGER, INSERT, UPDATE, SELECT on public.organizations to authenticated;
grant TRUNCATE, TRIGGER, REFERENCES, DELETE, INSERT, SELECT, UPDATE on public.reportes to anon;
grant REFERENCES, INSERT, SELECT, TRIGGER, UPDATE, DELETE, TRUNCATE on public.reportes to authenticated;
grant TRIGGER, INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES on public.routes to anon;
grant INSERT, TRIGGER, REFERENCES, UPDATE, TRUNCATE, DELETE, SELECT on public.routes to authenticated;
grant TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT, INSERT on public.tracto_documentos to anon;
grant TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT, INSERT on public.tracto_documentos to authenticated;
grant DELETE, TRIGGER, REFERENCES, TRUNCATE, UPDATE, SELECT, INSERT on public.tractos to anon;
grant SELECT, INSERT, UPDATE, DELETE, TRIGGER, REFERENCES, TRUNCATE on public.tractos to authenticated;
grant TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT, INSERT on public.viajes to authenticated;

-- ===== GRANTS EXECUTE =====
grant execute on function accept_member_invite(text) to anon;
grant execute on function accept_member_invite(text) to authenticated;
grant execute on function approve_organization_driver(uuid,uuid) to anon;
grant execute on function approve_organization_driver(uuid,uuid) to authenticated;
grant execute on function audit_customer_visibility_change() to anon;
grant execute on function audit_customer_visibility_change() to authenticated;
grant execute on function can_manage_membership(uuid,uuid) to anon;
grant execute on function can_manage_membership(uuid,uuid) to authenticated;
grant execute on function can_read_membership(uuid,uuid) to anon;
grant execute on function can_read_membership(uuid,uuid) to authenticated;
grant execute on function complete_organization_driver_onboarding(text,text,text,text,text,text,text,date,text,jsonb,jsonb) to anon;
grant execute on function complete_organization_driver_onboarding(text,text,text,text,text,text,text,date,text,jsonb,jsonb) to authenticated;
grant execute on function consume_organization_driver_invite(text,text,text,text,text,text,text) to anon;
grant execute on function consume_organization_driver_invite(text,text,text,text,text,text,text) to authenticated;
grant execute on function create_customer_for_organization(uuid,text,text,text,text) to anon;
grant execute on function create_customer_for_organization(uuid,text,text,text,text) to authenticated;
grant execute on function create_customer_member_invite(text,uuid) to anon;
grant execute on function create_customer_member_invite(text,uuid) to authenticated;
grant execute on function create_customer(text,text,text,text) to anon;
grant execute on function create_customer(text,text,text,text) to authenticated;
grant execute on function create_member_invite(text,text) to anon;
grant execute on function create_member_invite(text,text) to authenticated;
grant execute on function create_organization_driver_invite(uuid) to anon;
grant execute on function create_organization_driver_invite(uuid) to authenticated;
grant execute on function create_organization_for_current_user(text) to anon;
grant execute on function create_organization_for_current_user(text) to authenticated;
grant execute on function create_platform_organization_invite(text,text) to anon;
grant execute on function create_platform_organization_invite(text,text) to authenticated;
grant execute on function customer_has_trip_access(uuid,uuid) to anon;
grant execute on function customer_has_trip_access(uuid,uuid) to authenticated;
grant execute on function finalizar_viaje(uuid) to anon;
grant execute on function finalizar_viaje(uuid) to authenticated;
grant execute on function get_customer_context_for_org(uuid) to anon;
grant execute on function get_customer_context_for_org(uuid) to authenticated;
grant execute on function get_customer_context(uuid) to anon;
grant execute on function get_customer_context(uuid) to authenticated;
grant execute on function get_customer_dashboard_summary(uuid) to anon;
grant execute on function get_customer_dashboard_summary(uuid) to authenticated;
grant execute on function get_customer_member_invite_context(text) to anon;
grant execute on function get_customer_member_invite_context(text) to authenticated;
grant execute on function get_customer_visible_operations_for_org(uuid) to anon;
grant execute on function get_customer_visible_operations_for_org(uuid) to authenticated;
grant execute on function get_customer_visible_operations(uuid) to anon;
grant execute on function get_customer_visible_operations(uuid) to authenticated;
grant execute on function get_member_invite_context(text) to anon;
grant execute on function get_member_invite_context(text) to authenticated;
grant execute on function is_fleetops_platform_owner() to anon;
grant execute on function is_fleetops_platform_owner() to authenticated;
grant execute on function list_current_user_organization_team() to anon;
grant execute on function list_current_user_organization_team() to authenticated;
grant execute on function list_fleetops_platform_organizations() to anon;
grant execute on function list_fleetops_platform_organizations() to authenticated;
grant execute on function normalize_plate(text) to anon;
grant execute on function normalize_plate(text) to authenticated;
grant execute on function reject_organization_driver(uuid,uuid) to anon;
grant execute on function reject_organization_driver(uuid,uuid) to authenticated;
grant execute on function resolve_organization_driver_invite(text) to anon;
grant execute on function resolve_organization_driver_invite(text) to authenticated;
grant execute on function resolve_viaje_public(uuid) to anon;
grant execute on function resolve_viaje_public(uuid) to authenticated;
grant execute on function set_report_operational_metadata() to anon;
grant execute on function set_report_operational_metadata() to authenticated;
grant execute on function user_has_org_role(uuid,text[]) to anon;
grant execute on function user_has_org_role(uuid,text[]) to authenticated;
grant execute on function validate_customer_operation_access() to anon;
grant execute on function validate_customer_operation_access() to authenticated;
alter sequence public.reportes_id_seq owned by public.reportes.id;
