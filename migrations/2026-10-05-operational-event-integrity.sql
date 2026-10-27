-- Preserve the server receipt time and attribution for new operational reports.
-- Existing report timestamps remain unchanged because their original receipt
-- time cannot be reconstructed reliably.

alter table public.reportes
    add column if not exists actor_type text,
    add column if not exists actor_conductor_id uuid
        references public.conductores(id) on delete set null,
    add column if not exists actor_user_id uuid
        references auth.users(id) on delete set null,
    add column if not exists incident_category text;

update public.reportes
   set actor_type = 'legacy'
 where actor_type is null;

alter table public.reportes
    alter column actor_type set default 'legacy';

alter table public.reportes
    drop constraint if exists reportes_actor_type_check,
    add constraint reportes_actor_type_check
        check (actor_type in ('driver_attributed', 'operator', 'legacy')) not valid,
    drop constraint if exists reportes_incident_category_check,
    add constraint reportes_incident_category_check
        check (
            incident_category is null
            or incident_category in (
                'Falla mecánica',
                'Accidente',
                'Falta de conductor',
                'Puerto',
                'Cliente',
                'Clima',
                'Aduana',
                'Operación interna',
                'Otro'
            )
        ) not valid,
    drop constraint if exists reportes_incident_category_required_check,
    add constraint reportes_incident_category_required_check
        check (estado is distinct from 'Incidente' or incident_category is not null) not valid;

create or replace function public.set_report_operational_metadata()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_catalog
as $$
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
$$;

drop trigger if exists set_report_operational_metadata on public.reportes;
create trigger set_report_operational_metadata
before insert or update on public.reportes
for each row
execute function public.set_report_operational_metadata();
