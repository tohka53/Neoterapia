-- ============================================================================
-- NeoTerapia · 05 · Citas y areas de molestia por cita
-- ============================================================================

-- Resuelve pgcrypto / pg_trgm / unaccent vivan donde vivan (Supabase las pone
-- en `extensions`; un Postgres normal las deja en `public`).
set search_path = public, extensions;

create table if not exists public.citas (
  id                     uuid primary key default gen_random_uuid(),
  codigo_referencia      text not null unique,
  paciente_id            uuid not null references public.pacientes(id) on delete cascade,

  estado                 public.estado_cita not null default 'solicitada',
  origen                 public.origen_cita not null default 'publico',

  -- Lo que pidio el paciente
  fecha_solicitada       date not null,
  hora_solicitada        time,
  franja_solicitada      text check (franja_solicitada in ('manana', 'tarde', 'indistinto')),

  -- Lo que agendo la clinica
  inicio_programado      timestamptz,
  fin_programado         timestamptz,
  fisioterapeuta_id      uuid references public.perfiles(id) on delete set null,
  consultorio            text,

  -- Snapshot de contacto tal como lo escribio el paciente en ESTA solicitud
  nombre_declarado       text not null,
  telefono_declarado     text,
  whatsapp_declarado     text,
  email_declarado        text,
  canal_preferido        public.canal_contacto not null default 'whatsapp',

  motivo_consulta        text,
  comentarios_paciente   text,
  es_primera_vez         boolean not null default false,

  -- Resolucion
  notas_internas         text,
  motivo_estado          text,            -- por que se rechazo / cancelo / reprogramo
  resuelta_por           uuid references public.perfiles(id),
  resuelta_en            timestamptz,
  reprogramada_desde_id  uuid references public.citas(id) on delete set null,

  recordatorio_enviado_en timestamptz,
  asistio_en             timestamptz,

  ip_solicitud           inet,
  user_agent_solicitud   text,

  creado_en              timestamptz not null default now(),
  creado_por             uuid references public.perfiles(id),   -- null = solicitud publica
  actualizado_en         timestamptz not null default now(),

  constraint ck_cita_rango check (
    (inicio_programado is null and fin_programado is null)
    or (inicio_programado is not null and fin_programado is not null and fin_programado > inicio_programado)
  ),
  constraint ck_cita_confirmada_agendada check (
    estado <> 'confirmada' or inicio_programado is not null
  )
);

comment on table public.citas is
  'Solicitudes y citas. Una solicitud publica entra en estado `solicitada` sin agenda asignada.';
comment on column public.citas.codigo_referencia is
  'Identificador legible para que el paciente se refiera a su cita. NO es contrasena ni da acceso a nada.';

create index if not exists ix_citas_paciente   on public.citas (paciente_id, fecha_solicitada desc);
create index if not exists ix_citas_estado     on public.citas (estado, fecha_solicitada);
create index if not exists ix_citas_pendientes on public.citas (creado_en desc) where estado = 'solicitada';
create index if not exists ix_citas_agenda     on public.citas (inicio_programado) where estado in ('confirmada', 'atendida');
create index if not exists ix_citas_fisio      on public.citas (fisioterapeuta_id, inicio_programado);
create index if not exists ix_citas_codigo     on public.citas (upper(codigo_referencia));

-- Un fisioterapeuta no puede tener dos citas confirmadas superpuestas.
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'ex_citas_sin_traslape') then
    alter table public.citas
      add constraint ex_citas_sin_traslape
      exclude using gist (
        fisioterapeuta_id with =,
        tstzrange(inicio_programado, fin_programado) with &&
      ) where (estado = 'confirmada' and fisioterapeuta_id is not null);
  end if;
end $$;

drop trigger if exists tg_citas_actualizado on public.citas;
create trigger tg_citas_actualizado before update on public.citas
  for each row execute function public.tg_actualizar_timestamp();

-- FK diferida de alertas -> citas (alertas se creo antes que citas)
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'fk_alertas_cita') then
    alter table public.alertas
      add constraint fk_alertas_cita foreign key (cita_id)
      references public.citas(id) on delete cascade;
  end if;
end $$;

create index if not exists ix_alertas_cita on public.alertas (cita_id);

-- ----------------------------------------------------------------------------
-- Areas de molestia declaradas por el paciente en la solicitud
-- ----------------------------------------------------------------------------

create table if not exists public.cita_areas (
  cita_id      uuid not null references public.citas(id) on delete cascade,
  area_id      uuid not null references public.areas_cuerpo(id) on delete restrict,
  intensidad   int check (intensidad between 0 and 10),   -- escala EVA declarada por el paciente
  nota         text,
  creado_en    timestamptz not null default now(),
  primary key (cita_id, area_id)
);

comment on table public.cita_areas is
  'Zonas que el paciente marco en el mapa corporal al solicitar la cita.';

create index if not exists ix_cita_areas_area on public.cita_areas (area_id);

-- ----------------------------------------------------------------------------
-- Bitacora de cambios de estado de la cita
-- ----------------------------------------------------------------------------

create table if not exists public.citas_historial_estado (
  id             uuid primary key default gen_random_uuid(),
  cita_id        uuid not null references public.citas(id) on delete cascade,
  estado_anterior public.estado_cita,
  estado_nuevo   public.estado_cita not null,
  motivo         text,
  realizado_por  uuid references public.perfiles(id),
  realizado_en   timestamptz not null default now()
);

create index if not exists ix_citas_hist_cita on public.citas_historial_estado (cita_id, realizado_en desc);

create or replace function public.tg_citas_registrar_estado()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.citas_historial_estado (cita_id, estado_anterior, estado_nuevo, motivo, realizado_por)
    values (new.id, null, new.estado, new.motivo_estado, new.creado_por);
  elsif new.estado is distinct from old.estado then
    insert into public.citas_historial_estado (cita_id, estado_anterior, estado_nuevo, motivo, realizado_por)
    values (new.id, old.estado, new.estado, new.motivo_estado, coalesce(new.resuelta_por, auth.uid()));
  end if;
  return new;
end;
$$;

drop trigger if exists tg_citas_estado on public.citas;
create trigger tg_citas_estado after insert or update on public.citas
  for each row execute function public.tg_citas_registrar_estado();
