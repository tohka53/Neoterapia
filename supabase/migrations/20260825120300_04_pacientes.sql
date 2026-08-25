-- ============================================================================
-- NeoTerapia · 04 · Pacientes
-- ----------------------------------------------------------------------------
-- La ficha del paciente se crea SOLA cuando entra una solicitud de cita.
-- El DPI normalizado es el identificador principal; el nombre es solo dato de
-- comprobacion y nunca identifica de forma unica.
--
-- Seguridad de columnas:
--   `dpi` y `dpi_norm` quedan REVOCADAS para anon/authenticated (ver 09_rls).
--   La UI lee `dpi_mascara`; para ver el DPI completo hay que llamar a
--   `ver_dpi_paciente()`, que valida rol y deja rastro en auditoria.
-- ============================================================================

-- Resuelve pgcrypto / pg_trgm / unaccent vivan donde vivan (Supabase las pone
-- en `extensions`; un Postgres normal las deja en `public`).
set search_path = public, extensions;

create table if not exists public.pacientes (
  id                    uuid primary key default gen_random_uuid(),

  -- Identidad
  tipo_documento        public.tipo_documento not null default 'dpi',
  dpi                   text not null check (length(btrim(dpi)) >= 5),
  dpi_norm              text generated always as (public.normalizar_dpi(dpi)) stored,
  dpi_mascara           text generated always as (public.enmascarar_dpi(dpi)) stored,
  dpi_valido            boolean generated always as (public.dpi_es_valido(dpi)) stored,

  nombre_completo       text not null check (length(btrim(nombre_completo)) >= 3),
  nombre_norm           text generated always as (public.normalizar_nombre(nombre_completo)) stored,
  nombre_comparable     text generated always as (public.normalizar_nombre_comparable(nombre_completo)) stored,

  fecha_nacimiento      date check (fecha_nacimiento is null or fecha_nacimiento > '1900-01-01'),
  sexo                  text check (sexo in ('F', 'M', 'X')),

  -- Contacto (canonico; cada cita guarda ademas su propio snapshot)
  telefono              text,
  telefono_norm         text generated always as (public.normalizar_telefono(telefono)) stored,
  whatsapp              text,
  whatsapp_norm         text generated always as (public.normalizar_telefono(whatsapp)) stored,
  email                 text,
  email_norm            text generated always as (public.normalizar_email(email)) stored,
  canal_preferido       public.canal_contacto not null default 'whatsapp',

  direccion             text,
  contacto_emergencia   text,
  telefono_emergencia   text,

  -- Administrativo. Lo clinico (antecedentes, alergias) vive en
  -- `pacientes_clinico`, con su propio RLS: recepcion no debe verlo.
  fisioterapeuta_id     uuid references public.perfiles(id) on delete set null,
  notas_administrativas text,

  -- Estado y fusion
  estado                public.estado_paciente not null default 'activo',
  fusionado_en_id       uuid references public.pacientes(id) on delete set null,
  fusionado_en          timestamptz,
  fusionado_por         uuid references public.perfiles(id),

  creado_en             timestamptz not null default now(),
  creado_por            uuid references public.perfiles(id),   -- null = alta automatica desde el formulario publico
  actualizado_en        timestamptz not null default now(),

  constraint ck_paciente_fusion check (
    (estado = 'fusionado' and fusionado_en_id is not null and fusionado_en_id <> id)
    or (estado <> 'fusionado' and fusionado_en_id is null)
  )
);

comment on table public.pacientes is
  'Ficha interna del paciente. Se crea automaticamente al recibir una solicitud de cita. El paciente no tiene acceso a ella.';
comment on column public.pacientes.dpi_mascara is
  'Version enmascarada que se muestra en listados. La columna `dpi` esta revocada para roles de aplicacion.';

-- Un DPI activo solo puede pertenecer a una ficha. Las fichas fusionadas
-- conservan su DPI historico sin bloquear a la ficha superviviente.
create unique index if not exists ux_pacientes_documento
  on public.pacientes (tipo_documento, dpi_norm)
  where estado <> 'fusionado';

create index if not exists ix_pacientes_nombre_trgm
  on public.pacientes using gin (nombre_norm gin_trgm_ops);
create index if not exists ix_pacientes_comparable_trgm
  on public.pacientes using gin (nombre_comparable gin_trgm_ops);
create index if not exists ix_pacientes_telefono   on public.pacientes (telefono_norm) where telefono_norm is not null;
create index if not exists ix_pacientes_whatsapp   on public.pacientes (whatsapp_norm) where whatsapp_norm is not null;
create index if not exists ix_pacientes_email      on public.pacientes (email_norm)    where email_norm is not null;
create index if not exists ix_pacientes_fisio      on public.pacientes (fisioterapeuta_id) where estado = 'activo';
create index if not exists ix_pacientes_estado     on public.pacientes (estado);
create index if not exists ix_pacientes_dpi_prefix on public.pacientes (dpi_norm text_pattern_ops);

drop trigger if exists tg_pacientes_actualizado on public.pacientes;
create trigger tg_pacientes_actualizado before update on public.pacientes
  for each row execute function public.tg_actualizar_timestamp();

-- ----------------------------------------------------------------------------
-- Historial de cambios de identidad (DPI corregido, nombre corregido, fusiones)
-- ----------------------------------------------------------------------------

create table if not exists public.pacientes_historial_identidad (
  id            uuid primary key default gen_random_uuid(),
  paciente_id   uuid not null references public.pacientes(id) on delete cascade,
  campo         text not null check (campo in ('dpi', 'nombre_completo', 'tipo_documento', 'fusion')),
  valor_anterior text,
  valor_nuevo   text,
  motivo        text not null,
  realizado_por uuid references public.perfiles(id),
  realizado_en  timestamptz not null default now()
);

create index if not exists ix_hist_identidad_paciente
  on public.pacientes_historial_identidad (paciente_id, realizado_en desc);

-- ----------------------------------------------------------------------------
-- Alertas administrativas (nombre que no coincide, contacto cambiado, etc.)
-- ----------------------------------------------------------------------------

create table if not exists public.alertas (
  id           uuid primary key default gen_random_uuid(),
  tipo         public.tipo_alerta not null,
  severidad    int not null default 2 check (severidad between 1 and 3),  -- 1 info, 2 atencion, 3 critica
  paciente_id  uuid references public.pacientes(id) on delete cascade,
  cita_id      uuid,                                    -- FK se agrega en 05 (citas aun no existe)
  titulo       text not null,
  detalle      jsonb not null default '{}'::jsonb,
  estado       public.estado_alerta not null default 'pendiente',
  revisada_por uuid references public.perfiles(id),
  revisada_en  timestamptz,
  nota_revision text,
  creado_en    timestamptz not null default now()
);

create index if not exists ix_alertas_pendientes on public.alertas (creado_en desc) where estado = 'pendiente';
create index if not exists ix_alertas_paciente   on public.alertas (paciente_id, creado_en desc);

-- ----------------------------------------------------------------------------
-- Posibles duplicados
-- ----------------------------------------------------------------------------

create table if not exists public.posibles_duplicados (
  id            uuid primary key default gen_random_uuid(),
  paciente_a    uuid not null references public.pacientes(id) on delete cascade,
  paciente_b    uuid not null references public.pacientes(id) on delete cascade,
  motivo        text not null,          -- nombre_similar | telefono_igual | email_igual | dpi_similar
  puntaje       numeric(4,3) not null default 0 check (puntaje between 0 and 1),
  estado        public.estado_duplicado not null default 'pendiente',
  revisado_por  uuid references public.perfiles(id),
  revisado_en   timestamptz,
  nota          text,
  creado_en     timestamptz not null default now(),
  constraint ck_duplicado_distinto check (paciente_a <> paciente_b)
);

-- El par (a,b) se guarda siempre ordenado para no duplicar la deteccion.
create unique index if not exists ux_duplicados_par
  on public.posibles_duplicados (least(paciente_a::text, paciente_b::text),
                                 greatest(paciente_a::text, paciente_b::text),
                                 motivo);

create index if not exists ix_duplicados_pendientes
  on public.posibles_duplicados (puntaje desc, creado_en desc) where estado = 'pendiente';
