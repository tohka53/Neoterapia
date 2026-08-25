-- ============================================================================
-- NeoTerapia · 03 · Personal de la clinica, configuracion y catalogos
-- ----------------------------------------------------------------------------
-- IMPORTANTE: `auth.users` es EXCLUSIVO del personal. El paciente jamas tiene
-- cuenta, jamas inicia sesion y no existe fila suya en auth.*
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Perfiles del personal (1:1 con auth.users)
-- ----------------------------------------------------------------------------

-- Resuelve pgcrypto / pg_trgm / unaccent vivan donde vivan (Supabase las pone
-- en `extensions`; un Postgres normal las deja en `public`).
set search_path = public, extensions;

create table if not exists public.perfiles (
  id                  uuid primary key references auth.users(id) on delete cascade,
  nombre_completo     text        not null check (length(btrim(nombre_completo)) >= 3),
  rol                 public.rol_usuario not null default 'recepcion',
  email               text,
  telefono            text,
  colegiado           text,               -- numero de colegiado del fisioterapeuta
  especialidad        text,
  color_agenda        text default '#0d9488' check (color_agenda ~ '^#[0-9a-fA-F]{6}$'),
  activo              boolean     not null default true,
  creado_en           timestamptz not null default now(),
  actualizado_en      timestamptz not null default now()
);

comment on table public.perfiles is 'Personal de la clinica. Unicos usuarios con sesion en el sistema.';

create index if not exists ix_perfiles_rol    on public.perfiles (rol) where activo;
create index if not exists ix_perfiles_activo on public.perfiles (activo);

drop trigger if exists tg_perfiles_actualizado on public.perfiles;
create trigger tg_perfiles_actualizado before update on public.perfiles
  for each row execute function public.tg_actualizar_timestamp();

-- ----------------------------------------------------------------------------
-- Configuracion de la clinica (clave / valor tipado)
-- ----------------------------------------------------------------------------

create table if not exists public.configuracion (
  clave           text primary key,
  valor           jsonb       not null,
  descripcion     text,
  editable_por    public.rol_usuario not null default 'admin',
  actualizado_en  timestamptz not null default now(),
  actualizado_por uuid references public.perfiles(id)
);

drop trigger if exists tg_configuracion_actualizado on public.configuracion;
create trigger tg_configuracion_actualizado before update on public.configuracion
  for each row execute function public.tg_actualizar_timestamp();

create or replace function public.config(p_clave text, p_default jsonb default null)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select valor from public.configuracion where clave = p_clave), p_default)
$$;

create or replace function public.config_int(p_clave text, p_default int)
returns int
language sql
stable
set search_path = public
as $$
  select coalesce((public.config(p_clave) #>> '{}')::int, p_default)
$$;

-- ----------------------------------------------------------------------------
-- Catalogo de areas del cuerpo (mapa corporal)
-- ----------------------------------------------------------------------------

create table if not exists public.areas_cuerpo (
  id          uuid primary key default gen_random_uuid(),
  codigo      text not null unique check (codigo ~ '^[a-z0-9_]+$'),
  nombre      text not null,
  region      public.region_cuerpo not null,
  lado        public.lado_cuerpo   not null default 'central',
  vista       public.vista_cuerpo  not null default 'anterior',
  -- Ancla para pintar el punto sobre la silueta SVG (viewBox 0 0 200 420)
  svg_x       numeric(6,2),
  svg_y       numeric(6,2),
  orden       int  not null default 0,
  activo      boolean not null default true,
  creado_en   timestamptz not null default now()
);

comment on table public.areas_cuerpo is
  'Catalogo cerrado de zonas seleccionables en el mapa corporal publico e interno.';

create index if not exists ix_areas_cuerpo_orden on public.areas_cuerpo (vista, orden) where activo;

-- ----------------------------------------------------------------------------
-- Catalogo de tratamientos / procedimientos
-- ----------------------------------------------------------------------------

create table if not exists public.tratamientos (
  id             uuid primary key default gen_random_uuid(),
  codigo         text not null unique,
  nombre         text not null,
  descripcion    text,
  duracion_min   int  not null default 30 check (duracion_min between 5 and 480),
  precio         numeric(10,2) not null default 0 check (precio >= 0),
  requiere_nota  boolean not null default false,
  activo         boolean not null default true,
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

drop trigger if exists tg_tratamientos_actualizado on public.tratamientos;
create trigger tg_tratamientos_actualizado before update on public.tratamientos
  for each row execute function public.tg_actualizar_timestamp();

-- ----------------------------------------------------------------------------
-- Horarios de atencion y bloqueos de agenda
-- ----------------------------------------------------------------------------

create table if not exists public.horarios_atencion (
  id                uuid primary key default gen_random_uuid(),
  fisioterapeuta_id uuid references public.perfiles(id) on delete cascade,  -- null = horario de clinica
  dia_semana        int  not null check (dia_semana between 0 and 6),       -- 0 = domingo
  hora_inicio       time not null,
  hora_fin          time not null,
  cupos             int  not null default 1 check (cupos between 1 and 20),
  vigente_desde     date not null default current_date,
  vigente_hasta     date,
  activo            boolean not null default true,
  creado_en         timestamptz not null default now(),
  constraint ck_horario_rango check (hora_fin > hora_inicio),
  constraint ck_horario_vigencia check (vigente_hasta is null or vigente_hasta >= vigente_desde)
);

create index if not exists ix_horarios_dia on public.horarios_atencion (dia_semana) where activo;

create table if not exists public.bloqueos_agenda (
  id                uuid primary key default gen_random_uuid(),
  fisioterapeuta_id uuid references public.perfiles(id) on delete cascade,  -- null = toda la clinica
  inicio            timestamptz not null,
  fin               timestamptz not null,
  motivo            text not null,
  creado_por        uuid references public.perfiles(id),
  creado_en         timestamptz not null default now(),
  constraint ck_bloqueo_rango check (fin > inicio)
);

create index if not exists ix_bloqueos_rango on public.bloqueos_agenda using gist (tstzrange(inicio, fin));
