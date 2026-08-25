-- ============================================================================
--  NeoTerapia · INSTALACION COMPLETA
-- ----------------------------------------------------------------------------
--  Pegue TODO este archivo en:  Supabase → SQL Editor → New query → Run
--
--  Contiene, en orden, las 19 migraciones + los datos base (seed).
--  Es idempotente: si algo falla a medio camino, corrija y vuelva a correrlo
--  completo sin problema.
--
--  Despues de correrlo faltan solo dos cosas (estan al final del archivo,
--  comentadas): crear su usuario y ajustar la URL publica.
-- ============================================================================


-- ####################  20260825120000_01_extensiones_tipos.sql  ####################

-- ============================================================================
-- NeoTerapia · 01 · Extensiones, esquemas y tipos base
-- ----------------------------------------------------------------------------
-- Convenciones del proyecto:
--   * Todo el modelo vive en `public` (lo que PostgREST expone por defecto).
--   * Nada del paciente pasa por `auth.users`: el paciente NUNCA tiene cuenta.
--     `auth.users` se usa exclusivamente para el personal de la clinica.
--   * El DPI normalizado es el identificador natural del paciente.
-- ============================================================================

-- Resuelve pgcrypto / pg_trgm / unaccent vivan donde vivan (Supabase las pone
-- en `extensions`; un Postgres normal las deja en `public`).
set search_path = public, extensions;

create schema if not exists extensions;

create extension if not exists pgcrypto  with schema extensions;
create extension if not exists pg_trgm   with schema extensions;
create extension if not exists unaccent  with schema extensions;
create extension if not exists btree_gist with schema extensions;

-- ----------------------------------------------------------------------------
-- Tipos enumerados
-- ----------------------------------------------------------------------------

do $$ begin
  create type public.rol_usuario as enum (
    'superadmin',      -- control total, incluye configuracion y gestion de roles
    'admin',           -- administrador de la clinica
    'recepcion',       -- responsable de citas: coordina, no ve clinica ni notas
    'fisioterapeuta'   -- ve la clinica de SUS pacientes asignados
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.tipo_documento as enum ('dpi', 'pasaporte', 'otro');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.estado_paciente as enum ('activo', 'inactivo', 'fusionado');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.estado_cita as enum (
    'solicitada',    -- entro por el formulario publico, sin revisar
    'confirmada',    -- la clinica acepto y agendo
    'reprogramada',  -- se movio de fecha/hora (queda como estado terminal del registro previo)
    'rechazada',     -- la clinica no la acepto
    'cancelada',     -- cancelada por paciente o por la clinica
    'atendida',      -- el paciente asistio y hay sesion clinica
    'ausente'        -- no se presento
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.origen_cita as enum ('publico', 'telefono', 'whatsapp', 'presencial', 'interno');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.canal_contacto as enum ('email', 'whatsapp', 'telefono');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.lado_cuerpo as enum ('izquierdo', 'derecho', 'central');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.vista_cuerpo as enum ('anterior', 'posterior');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.region_cuerpo as enum ('cabeza_cuello', 'miembro_superior', 'tronco', 'columna', 'miembro_inferior');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.metodo_pago as enum ('efectivo', 'tarjeta', 'transferencia', 'deposito', 'otro');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.estado_pago as enum ('pendiente', 'pagado', 'anulado', 'reembolsado');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.tipo_enlace as enum ('confirmar', 'cancelar', 'evaluacion', 'calendario');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.canal_mensaje as enum ('email', 'whatsapp');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.tipo_mensaje as enum (
    'solicitud_recibida', 'confirmacion', 'rechazo', 'reprogramacion',
    'cancelacion', 'recordatorio', 'evaluacion'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.estado_mensaje as enum ('pendiente', 'enviado', 'fallido', 'omitido', 'cancelado');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.tipo_alerta as enum (
    'nombre_no_coincide',   -- el DPI ya existia con otro nombre
    'posible_duplicado',    -- dos fichas parecen la misma persona
    'dpi_sospechoso',       -- paso el formato pero fallo la validacion fuerte
    'contacto_cambiado',    -- el paciente reporto telefono/correo distinto
    'solicitud_sospechosa'  -- rate limit / patron de abuso
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.estado_alerta as enum ('pendiente', 'revisada', 'descartada');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.estado_duplicado as enum ('pendiente', 'descartado', 'fusionado');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.accion_auditoria as enum (
    'insertar', 'actualizar', 'eliminar',
    'consultar_sensible',   -- alguien destapo un DPI completo o un expediente
    'fusionar', 'corregir_dpi', 'cambiar_rol', 'exportar', 'acceso_publico'
  );
exception when duplicate_object then null; end $$;

-- ####################  20260825120100_02_funciones_base.sql  ####################

-- ============================================================================
-- NeoTerapia · 02 · Funciones base: normalizacion, validacion de DPI, mascaras
-- ----------------------------------------------------------------------------
-- Todas las funciones de este archivo son IMMUTABLE porque se usan en columnas
-- generadas e indices. No tocan tablas ni dependen de sesion.
-- ============================================================================

-- unaccent es STABLE por depender del diccionario; se envuelve para poder
-- indexarlo y usarlo en columnas generadas.
-- Resuelve pgcrypto / pg_trgm / unaccent vivan donde vivan (Supabase las pone
-- en `extensions`; un Postgres normal las deja en `public`).
set search_path = public, extensions;

create or replace function public.f_unaccent(p_txt text)
returns text
language sql
immutable
strict
parallel safe
set search_path = extensions, public
as $$
  select unaccent('unaccent', p_txt)
$$;

comment on function public.f_unaccent(text) is
  'unaccent envuelto como IMMUTABLE para poder usarlo en indices y columnas generadas.';

-- ----------------------------------------------------------------------------
-- Nombres
-- ----------------------------------------------------------------------------

create or replace function public.normalizar_nombre(p_nombre text)
returns text
language sql
immutable
parallel safe
set search_path = public
as $$
  select nullif(
    upper(
      btrim(
        regexp_replace(
          public.f_unaccent(coalesce(p_nombre, '')),
          '[^A-Za-z0-9ñÑ ]+', ' ', 'g'
        )
      )
    ),
    ''
  )
$$;

create or replace function public.normalizar_nombre_comparable(p_nombre text)
returns text
language sql
immutable
parallel safe
set search_path = public
as $$
  -- Colapsa espacios y ordena los tokens: "PEREZ JUAN" == "JUAN PEREZ".
  -- Sirve para detectar la misma persona con el nombre escrito al reves.
  select (
    select string_agg(t, ' ' order by t)
    from unnest(
      string_to_array(regexp_replace(public.normalizar_nombre(p_nombre), '\s+', ' ', 'g'), ' ')
    ) as t
    where length(t) > 1
  )
$$;

-- ----------------------------------------------------------------------------
-- Telefono / correo
-- ----------------------------------------------------------------------------

create or replace function public.normalizar_telefono(p_tel text)
returns text
language sql
immutable
parallel safe
set search_path = public
as $$
  -- Deja solo digitos. Si quedan 8 (formato local GT) antepone 502.
  select case
    when d is null or d = '' then null
    when length(d) = 8 then '502' || d
    when length(d) = 11 and left(d, 3) = '502' then d
    else d
  end
  from (select regexp_replace(coalesce(p_tel, ''), '\D', '', 'g') as d) s
$$;

create or replace function public.normalizar_email(p_email text)
returns text
language sql
immutable
parallel safe
set search_path = public
as $$
  select nullif(lower(btrim(coalesce(p_email, ''))), '')
$$;

-- ----------------------------------------------------------------------------
-- DPI / CUI de Guatemala
-- ----------------------------------------------------------------------------

create or replace function public.normalizar_dpi(p_dpi text)
returns text
language sql
immutable
parallel safe
set search_path = public
as $$
  select nullif(regexp_replace(coalesce(p_dpi, ''), '\D', '', 'g'), '')
$$;

comment on function public.normalizar_dpi(text) is
  'Quita espacios, guiones y cualquier separador. 2960 12345 0101 -> 2960123450101';

-- Cantidad de municipios por departamento (indice 1..22) con holgura para
-- municipios creados despues de la ultima actualizacion de la tabla oficial.
create or replace function public.municipios_por_departamento()
returns int[]
language sql
immutable
parallel safe
as $$
  select array[
    17,  --  1 Guatemala
    8,   --  2 El Progreso
    16,  --  3 Sacatepequez
    16,  --  4 Chimaltenango
    14,  --  5 Escuintla
    14,  --  6 Santa Rosa
    19,  --  7 Solola
    8,   --  8 Totonicapan
    24,  --  9 Quetzaltenango
    21,  -- 10 Suchitepequez
    9,   -- 11 Retalhuleu
    30,  -- 12 San Marcos
    33,  -- 13 Huehuetenango
    21,  -- 14 Quiche
    8,   -- 15 Baja Verapaz
    17,  -- 16 Alta Verapaz
    14,  -- 17 Peten
    5,   -- 18 Izabal
    11,  -- 19 Zacapa
    11,  -- 20 Chiquimula
    8,   -- 21 Jalapa
    17   -- 22 Jutiapa
  ]::int[]
$$;

create or replace function public.validar_dpi(p_dpi text)
returns jsonb
language plpgsql
immutable
parallel safe
set search_path = public
as $$
declare
  v_norm  text;
  v_suma  int := 0;
  v_i     int;
  v_dig   int;
  v_verif int;
  v_depto int;
  v_muni  int;
  v_max   int;
begin
  v_norm := public.normalizar_dpi(p_dpi);

  if v_norm is null then
    return jsonb_build_object('valido', false, 'normalizado', null, 'motivo', 'vacio');
  end if;

  if length(v_norm) <> 13 then
    return jsonb_build_object('valido', false, 'normalizado', v_norm, 'motivo', 'longitud');
  end if;

  -- Digito verificador: suma ponderada de los primeros 8 digitos (pesos 2..9) mod 11
  for v_i in 1..8 loop
    v_dig  := substr(v_norm, v_i, 1)::int;
    v_suma := v_suma + v_dig * (v_i + 1);
  end loop;

  v_verif := substr(v_norm, 9, 1)::int;
  if (v_suma % 11) <> v_verif then
    return jsonb_build_object('valido', false, 'normalizado', v_norm, 'motivo', 'digito_verificador');
  end if;

  -- Codigo geografico
  v_depto := substr(v_norm, 10, 2)::int;
  v_muni  := substr(v_norm, 12, 2)::int;

  if v_depto < 1 or v_depto > 22 then
    return jsonb_build_object('valido', false, 'normalizado', v_norm, 'motivo', 'departamento');
  end if;

  v_max := (public.municipios_por_departamento())[v_depto];
  if v_muni < 1 or v_muni > v_max + 3 then  -- +3 de holgura por municipios nuevos
    return jsonb_build_object('valido', false, 'normalizado', v_norm, 'motivo', 'municipio');
  end if;

  return jsonb_build_object(
    'valido', true,
    'normalizado', v_norm,
    'motivo', null,
    'departamento', v_depto,
    'municipio', v_muni
  );
end;
$$;

comment on function public.validar_dpi(text) is
  'Valida un CUI/DPI guatemalteco: 13 digitos, digito verificador (mod 11) y codigo geografico.';

create or replace function public.dpi_es_valido(p_dpi text)
returns boolean
language sql
immutable
parallel safe
set search_path = public
as $$
  select coalesce((public.validar_dpi(p_dpi) ->> 'valido')::boolean, false)
$$;

-- ----------------------------------------------------------------------------
-- Enmascarado de documentos
-- ----------------------------------------------------------------------------

create or replace function public.enmascarar_dpi(p_dpi text)
returns text
language sql
immutable
parallel safe
set search_path = public
as $$
  -- 2960123450101 -> 2960 ***** 0101
  select case
    when d is null then null
    when length(d) <= 4 then repeat('*', length(d))
    when length(d) < 8 then left(d, 2) || repeat('*', length(d) - 4) || right(d, 2)
    else left(d, 4) || ' ' || repeat('*', length(d) - 8) || ' ' || right(d, 4)
  end
  from (select public.normalizar_dpi(p_dpi) as d) s
$$;

create or replace function public.enmascarar_email(p_email text)
returns text
language sql
immutable
parallel safe
set search_path = public
as $$
  select case
    when e is null then null
    when position('@' in e) < 2 then '***'
    else left(e, 1)
       || repeat('*', greatest(position('@' in e) - 2, 1))
       || substr(e, position('@' in e))
  end
  from (select public.normalizar_email(p_email) as e) s
$$;

create or replace function public.enmascarar_telefono(p_tel text)
returns text
language sql
immutable
parallel safe
set search_path = public
as $$
  select case
    when t is null then null
    when length(t) <= 4 then repeat('*', length(t))
    else repeat('*', length(t) - 4) || right(t, 4)
  end
  from (select public.normalizar_telefono(p_tel) as t) s
$$;

-- ----------------------------------------------------------------------------
-- Codigo de referencia de cita
-- ----------------------------------------------------------------------------
-- Alfabeto sin caracteres ambiguos (0/O, 1/I/L) para que se pueda dictar por
-- telefono sin errores. NO es una contrasena: solo identifica la cita.

create or replace function public.generar_codigo_referencia()
returns text
language plpgsql
volatile
set search_path = public, extensions
as $$
declare
  v_alfabeto constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  v_bytes    bytea := gen_random_bytes(7);
  v_codigo   text := '';
  v_i        int;
begin
  for v_i in 1..7 loop
    v_codigo := v_codigo || substr(
      v_alfabeto,
      1 + (get_byte(v_bytes, v_i - 1) % length(v_alfabeto)),
      1
    );
  end loop;
  return 'NT-' || substr(v_codigo, 1, 3) || '-' || substr(v_codigo, 4, 4);
end;
$$;

comment on function public.generar_codigo_referencia() is
  'Codigo humano para identificar una cita por telefono o WhatsApp. No autentica nada.';

-- ----------------------------------------------------------------------------
-- Utilidad: timestamp de actualizacion
-- ----------------------------------------------------------------------------

create or replace function public.tg_actualizar_timestamp()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.actualizado_en := now();
  return new;
end;
$$;

-- ####################  20260825120200_03_personal_y_catalogos.sql  ####################

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

-- ####################  20260825120300_04_pacientes.sql  ####################

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

-- ####################  20260825120400_05_citas.sql  ####################

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

-- ####################  20260825120500_06_clinico.sql  ####################

-- ============================================================================
-- NeoTerapia · 06 · Registro clinico: sesiones, evolucion del mapa corporal,
--                    tratamientos aplicados y evaluacion del paciente
-- ----------------------------------------------------------------------------
-- Nada de esto es visible para el rol `recepcion` ni, por supuesto, para el
-- paciente (que no tiene sesion en el sistema).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Datos clinicos permanentes del paciente
-- ----------------------------------------------------------------------------
-- Tabla aparte de `pacientes` a proposito: asi el rol `recepcion` puede
-- coordinar citas sin tener ninguna via para leer informacion clinica.

-- Resuelve pgcrypto / pg_trgm / unaccent vivan donde vivan (Supabase las pone
-- en `extensions`; un Postgres normal las deja en `public`).
set search_path = public, extensions;

create table if not exists public.pacientes_clinico (
  paciente_id        uuid primary key references public.pacientes(id) on delete cascade,
  antecedentes       text,
  alergias           text,
  medicamentos       text,
  cirugias_previas   text,
  observaciones      text,
  actualizado_en     timestamptz not null default now(),
  actualizado_por    uuid references public.perfiles(id)
);

comment on table public.pacientes_clinico is
  'Antecedentes clinicos del paciente. Invisible para el rol recepcion.';

drop trigger if exists tg_pacientes_clinico_actualizado on public.pacientes_clinico;
create trigger tg_pacientes_clinico_actualizado before update on public.pacientes_clinico
  for each row execute function public.tg_actualizar_timestamp();

-- ----------------------------------------------------------------------------
-- Sesiones
-- ----------------------------------------------------------------------------

create table if not exists public.sesiones (
  id                 uuid primary key default gen_random_uuid(),
  cita_id            uuid not null unique references public.citas(id) on delete cascade,
  paciente_id        uuid not null references public.pacientes(id) on delete cascade,
  fisioterapeuta_id  uuid not null references public.perfiles(id) on delete restrict,

  inicio             timestamptz not null default now(),
  fin                timestamptz,

  -- Escala visual analoga del dolor al abrir y cerrar la sesion
  dolor_inicial      int check (dolor_inicial between 0 and 10),
  dolor_final        int check (dolor_final   between 0 and 10),

  -- Nota clinica (formato SOAP)
  subjetivo          text,   -- lo que refiere el paciente
  objetivo           text,   -- hallazgos de la exploracion
  analisis           text,   -- valoracion del fisioterapeuta
  plan               text,   -- plan de tratamiento

  recomendaciones    text,   -- ejercicios en casa, cuidados
  observaciones      text,

  requiere_seguimiento boolean not null default false,
  proxima_sugerida     date,

  firmada_en         timestamptz,   -- al firmar, la nota queda inmutable
  creado_en          timestamptz not null default now(),
  actualizado_en     timestamptz not null default now(),

  constraint ck_sesion_rango check (fin is null or fin >= inicio)
);

comment on table public.sesiones is
  'Nota clinica de una cita atendida. Una sesion por cita. Al firmarse queda bloqueada para edicion.';

create index if not exists ix_sesiones_paciente on public.sesiones (paciente_id, inicio desc);
create index if not exists ix_sesiones_fisio    on public.sesiones (fisioterapeuta_id, inicio desc);

drop trigger if exists tg_sesiones_actualizado on public.sesiones;
create trigger tg_sesiones_actualizado before update on public.sesiones
  for each row execute function public.tg_actualizar_timestamp();

-- Una nota firmada no se edita: se corrige con una adenda.
create or replace function public.tg_sesion_bloquear_firmada()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.firmada_en is not null
     and (new.firmada_en is not null)
     and (
       new.subjetivo       is distinct from old.subjetivo or
       new.objetivo        is distinct from old.objetivo  or
       new.analisis        is distinct from old.analisis  or
       new.plan            is distinct from old.plan      or
       new.recomendaciones is distinct from old.recomendaciones or
       new.dolor_inicial   is distinct from old.dolor_inicial   or
       new.dolor_final     is distinct from old.dolor_final
     )
  then
    raise exception 'La sesion % ya esta firmada; agregue una adenda en lugar de editarla.', old.id
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists tg_sesiones_firmada on public.sesiones;
create trigger tg_sesiones_firmada before update on public.sesiones
  for each row execute function public.tg_sesion_bloquear_firmada();

create table if not exists public.sesiones_adendas (
  id            uuid primary key default gen_random_uuid(),
  sesion_id     uuid not null references public.sesiones(id) on delete cascade,
  texto         text not null check (length(btrim(texto)) > 0),
  autor_id      uuid not null references public.perfiles(id),
  creado_en     timestamptz not null default now()
);

create index if not exists ix_adendas_sesion on public.sesiones_adendas (sesion_id, creado_en);

-- ----------------------------------------------------------------------------
-- Evolucion del mapa corporal por sesion
-- ----------------------------------------------------------------------------

create table if not exists public.sesion_areas (
  sesion_id    uuid not null references public.sesiones(id) on delete cascade,
  area_id      uuid not null references public.areas_cuerpo(id) on delete restrict,
  nivel_dolor  int not null check (nivel_dolor between 0 and 10),
  movilidad    text check (movilidad in ('normal', 'limitada', 'muy_limitada')),
  inflamacion  boolean not null default false,
  observacion  text,
  creado_en    timestamptz not null default now(),
  primary key (sesion_id, area_id)
);

comment on table public.sesion_areas is
  'Estado de cada zona en cada sesion. Es la fuente del mapa corporal de evolucion.';

create index if not exists ix_sesion_areas_area on public.sesion_areas (area_id);

-- ----------------------------------------------------------------------------
-- Tratamientos aplicados
-- ----------------------------------------------------------------------------

create table if not exists public.sesion_tratamientos (
  id             uuid primary key default gen_random_uuid(),
  sesion_id      uuid not null references public.sesiones(id) on delete cascade,
  tratamiento_id uuid not null references public.tratamientos(id) on delete restrict,
  cantidad       int not null default 1 check (cantidad between 1 and 50),
  precio_aplicado numeric(10,2) not null default 0 check (precio_aplicado >= 0),
  area_id        uuid references public.areas_cuerpo(id) on delete set null,
  notas          text,
  creado_en      timestamptz not null default now()
);

create index if not exists ix_sesion_trat_sesion on public.sesion_tratamientos (sesion_id);
create index if not exists ix_sesion_trat_trat   on public.sesion_tratamientos (tratamiento_id);

-- Al insertar, hereda el precio vigente del catalogo si no se especifico.
create or replace function public.tg_heredar_precio_tratamiento()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.precio_aplicado is null or new.precio_aplicado = 0 then
    select t.precio into new.precio_aplicado from public.tratamientos t where t.id = new.tratamiento_id;
  end if;
  return new;
end;
$$;

drop trigger if exists tg_sesion_trat_precio on public.sesion_tratamientos;
create trigger tg_sesion_trat_precio before insert on public.sesion_tratamientos
  for each row execute function public.tg_heredar_precio_tratamiento();

-- ----------------------------------------------------------------------------
-- Evaluacion posterior (la responde el paciente desde un enlace de un solo uso)
-- ----------------------------------------------------------------------------

create table if not exists public.evaluaciones (
  id             uuid primary key default gen_random_uuid(),
  cita_id        uuid not null unique references public.citas(id) on delete cascade,
  paciente_id    uuid not null references public.pacientes(id) on delete cascade,
  puntuacion     int not null check (puntuacion between 1 and 5),
  dolor_reportado int check (dolor_reportado between 0 and 10),
  comentario     text,
  recomendaria   boolean,
  respondida_en  timestamptz not null default now(),
  ip             inet
);

create index if not exists ix_evaluaciones_paciente on public.evaluaciones (paciente_id, respondida_en desc);

-- ####################  20260825120600_07_pagos.sql  ####################

-- ============================================================================
-- NeoTerapia · 07 · Pagos y comprobantes
-- ----------------------------------------------------------------------------
-- Lo maneja recepcion y administracion. El fisioterapeuta no ve pagos.
-- ============================================================================

-- Resuelve pgcrypto / pg_trgm / unaccent vivan donde vivan (Supabase las pone
-- en `extensions`; un Postgres normal las deja en `public`).
set search_path = public, extensions;

create table if not exists public.pagos (
  id              uuid primary key default gen_random_uuid(),
  paciente_id     uuid not null references public.pacientes(id) on delete cascade,
  cita_id         uuid references public.citas(id) on delete set null,
  sesion_id       uuid references public.sesiones(id) on delete set null,

  monto           numeric(10,2) not null check (monto > 0),
  moneda          text not null default 'GTQ' check (moneda ~ '^[A-Z]{3}$'),
  metodo          public.metodo_pago not null default 'efectivo',
  estado          public.estado_pago  not null default 'pagado',

  referencia      text,                    -- boleta, autorizacion, no. de transferencia
  comprobante_path text,                   -- ruta en Storage (bucket `comprobantes`)
  descripcion     text,

  fecha           timestamptz not null default now(),
  registrado_por  uuid references public.perfiles(id),

  anulado_en      timestamptz,
  anulado_por     uuid references public.perfiles(id),
  motivo_anulacion text,

  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),

  constraint ck_pago_anulacion check (
    (estado = 'anulado') = (anulado_en is not null)
  )
);

create index if not exists ix_pagos_paciente on public.pagos (paciente_id, fecha desc);
create index if not exists ix_pagos_cita     on public.pagos (cita_id);
create index if not exists ix_pagos_fecha    on public.pagos (fecha desc) where estado = 'pagado';

drop trigger if exists tg_pagos_actualizado on public.pagos;
create trigger tg_pagos_actualizado before update on public.pagos
  for each row execute function public.tg_actualizar_timestamp();

-- Un pago pagado no se edita en monto/metodo: se anula y se registra otro.
create or replace function public.tg_pago_inmutable()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.estado = 'pagado' and new.estado = 'pagado'
     and (new.monto is distinct from old.monto or new.metodo is distinct from old.metodo)
  then
    raise exception 'Un pago aplicado no puede modificarse. Anulelo y registre uno nuevo.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists tg_pagos_inmutable on public.pagos;
create trigger tg_pagos_inmutable before update on public.pagos
  for each row execute function public.tg_pago_inmutable();

-- ----------------------------------------------------------------------------
-- Saldo por paciente (tratamientos aplicados vs. pagos aplicados)
-- ----------------------------------------------------------------------------

-- security_invoker: la vista respeta las politicas RLS de quien consulta,
-- no las del dueno de la vista (postgres). Sin esto, cualquier vista seria
-- un agujero para saltarse RLS.
create or replace view public.v_saldos_paciente
with (security_invoker = true) as
select
  p.id                                      as paciente_id,
  coalesce(cargos.total, 0)                 as total_cargos,
  coalesce(abonos.total, 0)                 as total_pagado,
  coalesce(cargos.total, 0) - coalesce(abonos.total, 0) as saldo
from public.pacientes p
left join lateral (
  select sum(st.precio_aplicado * st.cantidad) as total
  from public.sesion_tratamientos st
  join public.sesiones s on s.id = st.sesion_id
  where s.paciente_id = p.id
) cargos on true
left join lateral (
  select sum(pg.monto) as total
  from public.pagos pg
  where pg.paciente_id = p.id and pg.estado = 'pagado'
) abonos on true;

-- ####################  20260825120700_08_auditoria_enlaces_mensajes.sql  ####################

-- ============================================================================
-- NeoTerapia · 08 · Auditoria, enlaces de accion sin portal y bandeja de salida
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Auditoria
-- ----------------------------------------------------------------------------

-- Resuelve pgcrypto / pg_trgm / unaccent vivan donde vivan (Supabase las pone
-- en `extensions`; un Postgres normal las deja en `public`).
set search_path = public, extensions;

create table if not exists public.auditoria (
  id            bigserial primary key,
  ocurrido_en   timestamptz not null default now(),
  actor_id      uuid references public.perfiles(id) on delete set null,
  actor_rol     public.rol_usuario,
  actor_email   text,
  accion        public.accion_auditoria not null,
  entidad       text not null,
  entidad_id    text,
  paciente_id   uuid references public.pacientes(id) on delete set null,
  descripcion   text,
  datos_antes   jsonb,
  datos_despues jsonb,
  ip            inet,
  user_agent    text
);

comment on table public.auditoria is
  'Bitacora inmutable. Solo se escribe por funciones SECURITY DEFINER y triggers; nadie puede UPDATE/DELETE.';

create index if not exists ix_auditoria_fecha    on public.auditoria (ocurrido_en desc);
create index if not exists ix_auditoria_actor    on public.auditoria (actor_id, ocurrido_en desc);
create index if not exists ix_auditoria_paciente on public.auditoria (paciente_id, ocurrido_en desc);
create index if not exists ix_auditoria_entidad  on public.auditoria (entidad, entidad_id);
create index if not exists ix_auditoria_sensible on public.auditoria (ocurrido_en desc)
  where accion = 'consultar_sensible';

-- Cabeceras de la peticion (PostgREST las inyecta en request.headers)
create or replace function public.request_ip()
returns inet
language plpgsql
stable
set search_path = public
as $$
declare v_raw text;
begin
  begin
    v_raw := current_setting('request.headers', true)::json ->> 'x-forwarded-for';
  exception when others then
    return null;
  end;
  if v_raw is null or btrim(v_raw) = '' then return null; end if;
  -- x-forwarded-for puede traer una cadena "cliente, proxy1, proxy2"
  begin
    return btrim(split_part(v_raw, ',', 1))::inet;
  exception when others then
    return null;
  end;
end;
$$;

create or replace function public.request_user_agent()
returns text
language plpgsql
stable
set search_path = public
as $$
begin
  return left(coalesce(current_setting('request.headers', true)::json ->> 'user-agent', ''), 400);
exception when others then
  return null;
end;
$$;

create or replace function public.registrar_auditoria(
  p_accion        public.accion_auditoria,
  p_entidad       text,
  p_entidad_id    text     default null,
  p_paciente_id   uuid     default null,
  p_descripcion   text     default null,
  p_datos_antes   jsonb    default null,
  p_datos_despues jsonb    default null
) returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id  bigint;
  v_uid uuid := auth.uid();
  v_rol public.rol_usuario;
  v_email text;
begin
  select rol, email into v_rol, v_email from public.perfiles where id = v_uid;

  insert into public.auditoria (
    actor_id, actor_rol, actor_email, accion, entidad, entidad_id,
    paciente_id, descripcion, datos_antes, datos_despues, ip, user_agent
  ) values (
    v_uid, v_rol, v_email, p_accion, p_entidad, p_entidad_id,
    p_paciente_id, p_descripcion, p_datos_antes, p_datos_despues,
    public.request_ip(), public.request_user_agent()
  )
  returning id into v_id;

  return v_id;
end;
$$;

-- Trigger generico de auditoria para tablas sensibles
create or replace function public.tg_auditar_cambios()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pac uuid;
begin
  v_pac := case
    when tg_table_name = 'pacientes' then coalesce(new.id, old.id)
    else null
  end;

  if tg_op = 'INSERT' then
    perform public.registrar_auditoria('insertar', tg_table_name, coalesce(new.id::text, ''), v_pac,
                                        null, null, to_jsonb(new));
  elsif tg_op = 'UPDATE' then
    perform public.registrar_auditoria('actualizar', tg_table_name, coalesce(new.id::text, ''), v_pac,
                                        null, to_jsonb(old), to_jsonb(new));
  elsif tg_op = 'DELETE' then
    perform public.registrar_auditoria('eliminar', tg_table_name, coalesce(old.id::text, ''), v_pac,
                                        null, to_jsonb(old), null);
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists tg_auditar_pacientes on public.pacientes;
create trigger tg_auditar_pacientes after insert or update or delete on public.pacientes
  for each row execute function public.tg_auditar_cambios();

drop trigger if exists tg_auditar_sesiones on public.sesiones;
create trigger tg_auditar_sesiones after insert or update or delete on public.sesiones
  for each row execute function public.tg_auditar_cambios();

drop trigger if exists tg_auditar_pagos on public.pagos;
create trigger tg_auditar_pagos after insert or update or delete on public.pagos
  for each row execute function public.tg_auditar_cambios();

drop trigger if exists tg_auditar_perfiles on public.perfiles;
create trigger tg_auditar_perfiles after insert or update or delete on public.perfiles
  for each row execute function public.tg_auditar_cambios();

-- Nadie modifica ni borra la bitacora.
create or replace function public.tg_auditoria_inmutable()
returns trigger
language plpgsql
as $$
begin
  raise exception 'La bitacora de auditoria es inmutable.' using errcode = 'insufficient_privilege';
end;
$$;

drop trigger if exists tg_auditoria_sin_cambios on public.auditoria;
create trigger tg_auditoria_sin_cambios before update or delete on public.auditoria
  for each row execute function public.tg_auditoria_inmutable();

-- ----------------------------------------------------------------------------
-- Enlaces de accion (sustituyen al portal del paciente)
-- ----------------------------------------------------------------------------
-- Se envia al paciente una URL con un token aleatorio. En la base SOLO queda el
-- hash. El enlace vence, tiene usos limitados y no revela historial: unicamente
-- permite la accion concreta para la que se emitio.

create table if not exists public.enlaces_accion (
  id           uuid primary key default gen_random_uuid(),
  cita_id      uuid not null references public.citas(id) on delete cascade,
  tipo         public.tipo_enlace not null,
  token_hash   bytea not null unique,
  expira_en    timestamptz not null,
  max_usos     int not null default 1 check (max_usos between 1 and 10),
  usos         int not null default 0 check (usos >= 0),
  usado_en     timestamptz,
  ip_uso       inet,
  revocado_en  timestamptz,
  creado_en    timestamptz not null default now()
);

create index if not exists ix_enlaces_cita on public.enlaces_accion (cita_id, tipo);
create index if not exists ix_enlaces_vigentes on public.enlaces_accion (expira_en)
  where revocado_en is null;

create or replace function public.hash_token(p_token text)
returns bytea
language sql
immutable
strict
set search_path = extensions, public
as $$
  select digest(p_token, 'sha256')
$$;

-- Emite un enlace y devuelve el token EN CLARO una sola vez (para el mensaje).
create or replace function public.emitir_enlace_accion(
  p_cita_id  uuid,
  p_tipo     public.tipo_enlace,
  p_horas    int default 168,      -- 7 dias
  p_max_usos int default 1
) returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_token text;
begin
  v_token := encode(gen_random_bytes(32), 'hex');

  insert into public.enlaces_accion (cita_id, tipo, token_hash, expira_en, max_usos)
  values (p_cita_id, p_tipo, public.hash_token(v_token), now() + make_interval(hours => p_horas), p_max_usos);

  return v_token;
end;
$$;

-- ----------------------------------------------------------------------------
-- Bandeja de salida de mensajes (correo / WhatsApp)
-- ----------------------------------------------------------------------------
-- El envio real esta DESACTIVADO por ahora: los mensajes se encolan y quedan en
-- `pendiente`. Cuando se conecte un proveedor, un worker drena esta tabla.
-- El contenido se guarda ya renderizado para poder auditar que se dijo.

create table if not exists public.mensajes (
  id             uuid primary key default gen_random_uuid(),
  cita_id        uuid references public.citas(id) on delete cascade,
  paciente_id    uuid references public.pacientes(id) on delete cascade,
  canal          public.canal_mensaje  not null,
  tipo           public.tipo_mensaje   not null,
  destinatario   text not null,
  asunto         text,
  cuerpo         text not null,
  variables      jsonb not null default '{}'::jsonb,
  estado         public.estado_mensaje not null default 'pendiente',
  programado_para timestamptz not null default now(),
  intentos       int not null default 0,
  ultimo_error   text,
  proveedor      text,
  proveedor_id   text,
  enviado_en     timestamptz,
  creado_en      timestamptz not null default now()
);

comment on table public.mensajes is
  'Bandeja de salida. Hoy solo encola: no hay proveedor conectado. Sirve tambien de bitacora de comunicacion.';

create index if not exists ix_mensajes_pendientes
  on public.mensajes (programado_para) where estado = 'pendiente';
create index if not exists ix_mensajes_cita on public.mensajes (cita_id, creado_en desc);
create index if not exists ix_mensajes_paciente on public.mensajes (paciente_id, creado_en desc);

-- ----------------------------------------------------------------------------
-- Control de abuso del formulario publico
-- ----------------------------------------------------------------------------

create table if not exists public.control_solicitudes (
  clave        text not null,            -- 'ip:1.2.3.4' | 'dpi:2960...' | 'email:...'
  ventana      timestamptz not null,     -- inicio de la ventana (truncado a hora)
  conteo       int not null default 1,
  ultimo_en    timestamptz not null default now(),
  primary key (clave, ventana)
);

create index if not exists ix_control_ventana on public.control_solicitudes (ventana);

create or replace function public.limpiar_control_solicitudes()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.control_solicitudes where ventana < now() - interval '7 days';
$$;

-- ----------------------------------------------------------------------------
-- Encolado de mensajes
-- ----------------------------------------------------------------------------
-- Renderiza el texto y lo deja en `pendiente`. Hoy NO se envia nada: cuando se
-- conecte un proveedor basta con drenar la tabla desde una Edge Function.

create or replace function public.encolar_mensaje(
  p_cita_id  uuid,
  p_tipo     public.tipo_mensaje,
  p_extra    jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c        record;
  v_canal    public.canal_mensaje;
  v_destino  text;
  v_cuerpo   text;
  v_asunto   text;
  v_saludo   text;
  v_cuando   text;
  v_base     text := coalesce(public.config('url_publica') #>> '{}', 'https://neoterapia.vercel.app');
  v_id       uuid;
  v_tz       text := coalesce(public.config('zona_horaria') #>> '{}', 'America/Guatemala');
begin
  select c.*, p.email as p_email, p.whatsapp as p_wa, p.telefono as p_tel
    into v_c
  from public.citas c
  join public.pacientes p on p.id = c.paciente_id
  where c.id = p_cita_id;

  if not found then return null; end if;

  -- Canal: lo que pidio el paciente, con respaldo al dato que si tenemos.
  if v_c.canal_preferido = 'email' and coalesce(v_c.email_declarado, v_c.p_email) is not null then
    v_canal := 'email';
    v_destino := coalesce(v_c.email_declarado, v_c.p_email);
  elsif coalesce(v_c.whatsapp_declarado, v_c.p_wa, v_c.telefono_declarado, v_c.p_tel) is not null then
    v_canal := 'whatsapp';
    v_destino := public.normalizar_telefono(
      coalesce(v_c.whatsapp_declarado, v_c.p_wa, v_c.telefono_declarado, v_c.p_tel));
  elsif coalesce(v_c.email_declarado, v_c.p_email) is not null then
    v_canal := 'email';
    v_destino := coalesce(v_c.email_declarado, v_c.p_email);
  else
    return null;   -- sin forma de contactar: no se encola nada
  end if;

  v_saludo := split_part(btrim(v_c.nombre_declarado), ' ', 1);
  v_cuando := coalesce(
    to_char(v_c.inicio_programado at time zone v_tz, 'DD/MM/YYYY HH24:MI'),
    to_char(v_c.fecha_solicitada, 'DD/MM/YYYY')
  );

  v_asunto := case p_tipo
    when 'solicitud_recibida' then 'Recibimos su solicitud de cita ' || v_c.codigo_referencia
    when 'confirmacion'       then 'Cita confirmada ' || v_c.codigo_referencia
    when 'rechazo'            then 'Sobre su solicitud ' || v_c.codigo_referencia
    when 'reprogramacion'     then 'Su cita fue reprogramada ' || v_c.codigo_referencia
    when 'cancelacion'        then 'Cita cancelada ' || v_c.codigo_referencia
    when 'recordatorio'       then 'Recordatorio de su cita ' || v_c.codigo_referencia
    when 'evaluacion'         then '¿Como le fue en su sesion?'
  end;

  v_cuerpo := case p_tipo
    when 'solicitud_recibida' then format(
      E'Hola %s:\n\nRecibimos su solicitud de cita para el %s.\nSu codigo de referencia es %s.\n\n'
      'Le confirmaremos por este medio. Si necesita comunicarse, mencione ese codigo.\n\nNeoTerapia',
      v_saludo, v_cuando, v_c.codigo_referencia)
    when 'confirmacion' then format(
      E'Hola %s:\n\nSu cita quedo CONFIRMADA para el %s.\nCodigo de referencia: %s.\n\n'
      '%s\n\nSi no puede asistir, avisenos con anticipacion.\n\nNeoTerapia',
      v_saludo, v_cuando, v_c.codigo_referencia,
      coalesce(p_extra ->> 'enlaces', ''))
    when 'rechazo' then format(
      E'Hola %s:\n\nLamentablemente no podemos atender su solicitud %s para el %s.\nMotivo: %s\n\n'
      'Puede solicitar una nueva cita cuando guste.\n\nNeoTerapia',
      v_saludo, v_c.codigo_referencia, v_cuando, coalesce(v_c.motivo_estado, 'sin disponibilidad'))
    when 'reprogramacion' then format(
      E'Hola %s:\n\nSu cita %s fue reprogramada para el %s.\n%s\n\nNeoTerapia',
      v_saludo, v_c.codigo_referencia, v_cuando, coalesce(p_extra ->> 'enlaces', ''))
    when 'cancelacion' then format(
      E'Hola %s:\n\nSu cita %s del %s fue cancelada.\nMotivo: %s\n\nNeoTerapia',
      v_saludo, v_c.codigo_referencia, v_cuando, coalesce(v_c.motivo_estado, 'no indicado'))
    when 'recordatorio' then format(
      E'Hola %s:\n\nLe recordamos su cita del %s (codigo %s).\n%s\n\nNeoTerapia',
      v_saludo, v_cuando, v_c.codigo_referencia, coalesce(p_extra ->> 'enlaces', ''))
    when 'evaluacion' then format(
      E'Hola %s:\n\nGracias por visitarnos. Nos ayudaria mucho su opinion sobre la sesion del %s.\n%s\n\nNeoTerapia',
      v_saludo, v_cuando, coalesce(p_extra ->> 'enlaces', ''))
  end;

  insert into public.mensajes (
    cita_id, paciente_id, canal, tipo, destinatario, asunto, cuerpo, variables, estado
  ) values (
    p_cita_id, v_c.paciente_id, v_canal, p_tipo, v_destino, v_asunto, v_cuerpo,
    jsonb_build_object('codigo', v_c.codigo_referencia, 'cuando', v_cuando, 'base', v_base) || p_extra,
    'pendiente'
  )
  returning id into v_id;

  return v_id;
end;
$$;

comment on function public.encolar_mensaje(uuid, public.tipo_mensaje, jsonb) is
  'Encola el mensaje ya renderizado. El envio esta desactivado: no hay proveedor conectado todavia.';

-- ####################  20260825120800_09_rls.sql  ####################

-- ============================================================================
-- NeoTerapia · 09 · Seguridad: roles, RLS y privilegios de columna
-- ----------------------------------------------------------------------------
-- Principios:
--   1. `anon` no toca ninguna tabla directamente. Solo RPCs SECURITY DEFINER.
--   2. `recepcion` coordina: ve pacientes y citas, NUNCA notas clinicas.
--   3. `fisioterapeuta` ve la clinica SOLO de los pacientes que atiende.
--   4. El DPI en claro no se puede leer por SQL directo desde la app: hay que
--      pasar por `ver_dpi_paciente()`, que audita.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Helpers de rol (SECURITY DEFINER: los ejecuta el dueno, que salta RLS,
-- evitando la recursion infinita al consultar `perfiles` desde su propia RLS)
-- ----------------------------------------------------------------------------

-- Resuelve pgcrypto / pg_trgm / unaccent vivan donde vivan (Supabase las pone
-- en `extensions`; un Postgres normal las deja en `public`).
set search_path = public, extensions;

create or replace function public.mi_rol()
returns public.rol_usuario
language sql
stable
security definer
set search_path = public
as $$
  select p.rol from public.perfiles p where p.id = auth.uid() and p.activo
$$;

create or replace function public.es_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select public.mi_rol() is not null
$$;

create or replace function public.es_superadmin()
returns boolean language sql stable security definer set search_path = public as $$
  select public.mi_rol() = 'superadmin'
$$;

create or replace function public.es_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select public.mi_rol() in ('admin', 'superadmin')
$$;

create or replace function public.es_recepcion()
returns boolean language sql stable security definer set search_path = public as $$
  select public.mi_rol() = 'recepcion'
$$;

create or replace function public.es_fisio()
returns boolean language sql stable security definer set search_path = public as $$
  select public.mi_rol() = 'fisioterapeuta'
$$;

-- ¿El fisioterapeuta autenticado atiende a este paciente?
create or replace function public.atiendo_paciente(p_paciente_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.pacientes p
    where p.id = p_paciente_id and p.fisioterapeuta_id = auth.uid()
  ) or exists (
    select 1 from public.citas c
    where c.paciente_id = p_paciente_id and c.fisioterapeuta_id = auth.uid()
  )
$$;

-- ¿Puede el usuario actual ver la ficha de este paciente?
create or replace function public.puedo_ver_paciente(p_paciente_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when public.mi_rol() in ('superadmin', 'admin', 'recepcion') then true
    when public.mi_rol() = 'fisioterapeuta' then public.atiendo_paciente(p_paciente_id)
    else false
  end
$$;

-- ¿Puede ver el contenido clinico (notas, antecedentes, evolucion)?
create or replace function public.puedo_ver_clinico(p_paciente_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when public.mi_rol() in ('superadmin', 'admin') then true
    when public.mi_rol() = 'fisioterapeuta' then public.atiendo_paciente(p_paciente_id)
    else false   -- recepcion NO
  end
$$;

-- ============================================================================
-- Activar RLS en absolutamente todo
-- ============================================================================

do $$
declare t text;
begin
  foreach t in array array[
    'perfiles', 'configuracion', 'areas_cuerpo', 'tratamientos',
    'horarios_atencion', 'bloqueos_agenda',
    'pacientes', 'pacientes_clinico', 'pacientes_historial_identidad',
    'alertas', 'posibles_duplicados',
    'citas', 'cita_areas', 'citas_historial_estado',
    'sesiones', 'sesiones_adendas', 'sesion_areas', 'sesion_tratamientos',
    'evaluaciones', 'pagos',
    'auditoria', 'enlaces_accion', 'mensajes', 'control_solicitudes'
  ] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- Deliberadamente NO se usa FORCE ROW LEVEL SECURITY: el dueno de las tablas
-- (postgres) debe poder saltarse RLS para que funcionen las RPC SECURITY
-- DEFINER que sostienen el flujo publico. `anon` y `authenticated` no son
-- dueños de nada, asi que para ellos RLS aplica siempre.

-- ============================================================================
-- Privilegios base: `anon` no ve nada; `authenticated` parte de cero
-- ============================================================================

revoke all on all tables    in schema public from anon, authenticated;
revoke all on all functions in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

grant usage on schema public to anon, authenticated;

-- ----------------------------------------------------------------------------
-- perfiles
-- ----------------------------------------------------------------------------
grant select, update on public.perfiles to authenticated;

drop policy if exists perfiles_select_staff on public.perfiles;
create policy perfiles_select_staff on public.perfiles
  for select to authenticated
  using (public.es_staff());

drop policy if exists perfiles_update_propio on public.perfiles;
create policy perfiles_update_propio on public.perfiles
  for update to authenticated
  using (id = auth.uid() or public.es_superadmin())
  with check (id = auth.uid() or public.es_superadmin());

-- Solo el superadmin cambia roles o reactiva usuarios.
create or replace function public.tg_perfiles_control_rol()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (new.rol is distinct from old.rol or new.activo is distinct from old.activo)
     and not public.es_superadmin()
  then
    raise exception 'Solo un superadministrador puede cambiar el rol o el estado de un usuario.'
      using errcode = 'insufficient_privilege';
  end if;
  if new.rol is distinct from old.rol then
    perform public.registrar_auditoria(
      'cambiar_rol', 'perfiles', new.id::text, null,
      format('Rol %s -> %s', old.rol, new.rol),
      jsonb_build_object('rol', old.rol), jsonb_build_object('rol', new.rol));
  end if;
  return new;
end;
$$;

drop trigger if exists tg_perfiles_rol on public.perfiles;
create trigger tg_perfiles_rol before update on public.perfiles
  for each row execute function public.tg_perfiles_control_rol();

-- ----------------------------------------------------------------------------
-- configuracion
-- ----------------------------------------------------------------------------
grant select on public.configuracion to authenticated;
grant insert, update on public.configuracion to authenticated;

drop policy if exists config_select on public.configuracion;
create policy config_select on public.configuracion
  for select to authenticated using (public.es_staff());
drop policy if exists config_write on public.configuracion;
create policy config_write on public.configuracion
  for all to authenticated using (public.es_admin()) with check (public.es_admin());

-- ----------------------------------------------------------------------------
-- areas_cuerpo: catalogo publico (lo necesita el mapa corporal del formulario)
-- ----------------------------------------------------------------------------
grant select on public.areas_cuerpo to anon, authenticated;
grant insert, update, delete on public.areas_cuerpo to authenticated;

drop policy if exists areas_select_publico on public.areas_cuerpo;
create policy areas_select_publico on public.areas_cuerpo
  for select to anon using (activo);
drop policy if exists areas_select_staff on public.areas_cuerpo;
create policy areas_select_staff on public.areas_cuerpo
  for select to authenticated using (public.es_staff());
drop policy if exists areas_write_admin on public.areas_cuerpo;
create policy areas_write_admin on public.areas_cuerpo
  for all to authenticated using (public.es_admin()) with check (public.es_admin());

-- ----------------------------------------------------------------------------
-- tratamientos / horarios / bloqueos
-- ----------------------------------------------------------------------------
grant select, insert, update, delete on public.tratamientos      to authenticated;
grant select, insert, update, delete on public.horarios_atencion to authenticated;
grant select, insert, update, delete on public.bloqueos_agenda   to authenticated;

drop policy if exists tratamientos_select on public.tratamientos;
create policy tratamientos_select on public.tratamientos
  for select to authenticated using (public.es_staff());
drop policy if exists tratamientos_write on public.tratamientos;
create policy tratamientos_write on public.tratamientos
  for all to authenticated using (public.es_admin()) with check (public.es_admin());

drop policy if exists horarios_select on public.horarios_atencion;
create policy horarios_select on public.horarios_atencion
  for select to authenticated using (public.es_staff());
drop policy if exists horarios_write on public.horarios_atencion;
create policy horarios_write on public.horarios_atencion
  for all to authenticated using (public.es_admin()) with check (public.es_admin());

drop policy if exists bloqueos_select on public.bloqueos_agenda;
create policy bloqueos_select on public.bloqueos_agenda
  for select to authenticated using (public.es_staff());
drop policy if exists bloqueos_write on public.bloqueos_agenda;
create policy bloqueos_write on public.bloqueos_agenda
  for all to authenticated
  using (public.es_admin() or fisioterapeuta_id = auth.uid())
  with check (public.es_admin() or fisioterapeuta_id = auth.uid());

-- ----------------------------------------------------------------------------
-- pacientes: el DPI en claro queda fuera del alcance de la app
-- ----------------------------------------------------------------------------
do $$
declare
  v_lectura   text;
  v_escritura text;
  v_ocultas   text[] := array['dpi', 'dpi_norm'];
begin
  select string_agg(quote_ident(c.column_name), ', ' order by c.ordinal_position)
    into v_lectura
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = 'pacientes'
    and c.column_name <> all (v_ocultas);

  select string_agg(quote_ident(c.column_name), ', ' order by c.ordinal_position)
    into v_escritura
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = 'pacientes'
    and c.column_name <> all (v_ocultas || array['id', 'creado_en', 'creado_por'])
    and c.is_generated = 'NEVER'
    and c.is_updatable = 'YES';

  execute format('grant select (%s) on public.pacientes to authenticated', v_lectura);
  execute format('grant insert (%s) on public.pacientes to authenticated', v_escritura);
  execute format('grant update (%s) on public.pacientes to authenticated', v_escritura);
end $$;

comment on column public.pacientes.dpi is
  'REVOCADO para anon/authenticated. Se lee unicamente con ver_dpi_paciente(), que deja rastro en auditoria.';

drop policy if exists pacientes_select on public.pacientes;
create policy pacientes_select on public.pacientes
  for select to authenticated
  using (public.puedo_ver_paciente(id));

drop policy if exists pacientes_insert on public.pacientes;
create policy pacientes_insert on public.pacientes
  for insert to authenticated
  with check (public.mi_rol() in ('superadmin', 'admin', 'recepcion'));

drop policy if exists pacientes_update on public.pacientes;
create policy pacientes_update on public.pacientes
  for update to authenticated
  using (public.mi_rol() in ('superadmin', 'admin', 'recepcion')
         or (public.es_fisio() and public.atiendo_paciente(id)))
  with check (public.mi_rol() in ('superadmin', 'admin', 'recepcion')
         or (public.es_fisio() and public.atiendo_paciente(id)));

-- El estado de fusion solo se toca desde fusionar_pacientes().
create or replace function public.tg_pacientes_control_edicion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_setting('neoterapia.operacion_interna', true) = 'on' then
    return new;
  end if;

  if new.estado is distinct from old.estado and new.estado = 'fusionado' then
    raise exception 'La fusion de fichas se realiza con fusionar_pacientes().'
      using errcode = 'insufficient_privilege';
  end if;

  if new.fusionado_en_id is distinct from old.fusionado_en_id then
    raise exception 'fusionado_en_id lo administra fusionar_pacientes().'
      using errcode = 'insufficient_privilege';
  end if;

  -- El fisioterapeuta no administra datos de contacto ni asignaciones.
  if public.es_fisio() and (
       new.telefono          is distinct from old.telefono or
       new.whatsapp          is distinct from old.whatsapp or
       new.email             is distinct from old.email    or
       new.nombre_completo   is distinct from old.nombre_completo or
       new.fisioterapeuta_id is distinct from old.fisioterapeuta_id)
  then
    raise exception 'Un fisioterapeuta no modifica identidad, contacto ni asignacion del paciente.'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

drop trigger if exists tg_pacientes_edicion on public.pacientes;
create trigger tg_pacientes_edicion before update on public.pacientes
  for each row execute function public.tg_pacientes_control_edicion();

-- ----------------------------------------------------------------------------
-- pacientes_clinico
-- ----------------------------------------------------------------------------
grant select, insert, update on public.pacientes_clinico to authenticated;

drop policy if exists clinico_select on public.pacientes_clinico;
create policy clinico_select on public.pacientes_clinico
  for select to authenticated using (public.puedo_ver_clinico(paciente_id));
drop policy if exists clinico_write on public.pacientes_clinico;
create policy clinico_write on public.pacientes_clinico
  for all to authenticated
  using (public.puedo_ver_clinico(paciente_id))
  with check (public.puedo_ver_clinico(paciente_id));

-- ----------------------------------------------------------------------------
-- historial de identidad / alertas / duplicados
-- ----------------------------------------------------------------------------
grant select on public.pacientes_historial_identidad to authenticated;
grant select, update on public.alertas             to authenticated;
grant select, update on public.posibles_duplicados to authenticated;

drop policy if exists hist_identidad_select on public.pacientes_historial_identidad;
create policy hist_identidad_select on public.pacientes_historial_identidad
  for select to authenticated using (public.es_admin());

drop policy if exists alertas_select on public.alertas;
create policy alertas_select on public.alertas
  for select to authenticated
  using (public.es_admin() or public.es_recepcion());
drop policy if exists alertas_update on public.alertas;
create policy alertas_update on public.alertas
  for update to authenticated
  using (public.es_admin() or public.es_recepcion())
  with check (public.es_admin() or public.es_recepcion());

drop policy if exists duplicados_select on public.posibles_duplicados;
create policy duplicados_select on public.posibles_duplicados
  for select to authenticated using (public.es_admin());
drop policy if exists duplicados_update on public.posibles_duplicados;
create policy duplicados_update on public.posibles_duplicados
  for update to authenticated using (public.es_admin()) with check (public.es_admin());

-- ----------------------------------------------------------------------------
-- citas
-- ----------------------------------------------------------------------------
grant select, insert, update on public.citas to authenticated;
grant select, insert, update, delete on public.cita_areas to authenticated;
grant select on public.citas_historial_estado to authenticated;

drop policy if exists citas_select on public.citas;
create policy citas_select on public.citas
  for select to authenticated
  using (
    public.mi_rol() in ('superadmin', 'admin', 'recepcion')
    or (public.es_fisio() and (fisioterapeuta_id = auth.uid() or public.atiendo_paciente(paciente_id)))
  );

drop policy if exists citas_insert on public.citas;
create policy citas_insert on public.citas
  for insert to authenticated
  with check (public.mi_rol() in ('superadmin', 'admin', 'recepcion'));

drop policy if exists citas_update on public.citas;
create policy citas_update on public.citas
  for update to authenticated
  using (
    public.mi_rol() in ('superadmin', 'admin', 'recepcion')
    or (public.es_fisio() and fisioterapeuta_id = auth.uid())
  )
  with check (
    public.mi_rol() in ('superadmin', 'admin', 'recepcion')
    or (public.es_fisio() and fisioterapeuta_id = auth.uid())
  );

drop policy if exists cita_areas_select on public.cita_areas;
create policy cita_areas_select on public.cita_areas
  for select to authenticated
  using (exists (select 1 from public.citas c where c.id = cita_id));
drop policy if exists cita_areas_write on public.cita_areas;
create policy cita_areas_write on public.cita_areas
  for all to authenticated
  using (exists (select 1 from public.citas c where c.id = cita_id))
  with check (exists (select 1 from public.citas c where c.id = cita_id));

drop policy if exists citas_hist_select on public.citas_historial_estado;
create policy citas_hist_select on public.citas_historial_estado
  for select to authenticated
  using (exists (select 1 from public.citas c where c.id = cita_id));

-- ----------------------------------------------------------------------------
-- sesiones y todo lo clinico: recepcion queda fuera
-- ----------------------------------------------------------------------------
grant select, insert, update on public.sesiones            to authenticated;
grant select, insert          on public.sesiones_adendas   to authenticated;
grant select, insert, update, delete on public.sesion_areas        to authenticated;
grant select, insert, update, delete on public.sesion_tratamientos to authenticated;

drop policy if exists sesiones_select on public.sesiones;
create policy sesiones_select on public.sesiones
  for select to authenticated using (public.puedo_ver_clinico(paciente_id));
drop policy if exists sesiones_insert on public.sesiones;
create policy sesiones_insert on public.sesiones
  for insert to authenticated
  with check (public.es_admin() or (public.es_fisio() and fisioterapeuta_id = auth.uid()));
drop policy if exists sesiones_update on public.sesiones;
create policy sesiones_update on public.sesiones
  for update to authenticated
  using (public.es_admin() or (public.es_fisio() and fisioterapeuta_id = auth.uid()))
  with check (public.es_admin() or (public.es_fisio() and fisioterapeuta_id = auth.uid()));

drop policy if exists adendas_select on public.sesiones_adendas;
create policy adendas_select on public.sesiones_adendas
  for select to authenticated
  using (exists (select 1 from public.sesiones s where s.id = sesion_id));
drop policy if exists adendas_insert on public.sesiones_adendas;
create policy adendas_insert on public.sesiones_adendas
  for insert to authenticated
  with check (autor_id = auth.uid()
              and exists (select 1 from public.sesiones s where s.id = sesion_id));

drop policy if exists sesion_areas_all on public.sesion_areas;
create policy sesion_areas_all on public.sesion_areas
  for all to authenticated
  using (exists (select 1 from public.sesiones s where s.id = sesion_id))
  with check (exists (select 1 from public.sesiones s where s.id = sesion_id));

drop policy if exists sesion_trat_all on public.sesion_tratamientos;
create policy sesion_trat_all on public.sesion_tratamientos
  for all to authenticated
  using (exists (select 1 from public.sesiones s where s.id = sesion_id))
  with check (exists (select 1 from public.sesiones s where s.id = sesion_id));

-- ----------------------------------------------------------------------------
-- evaluaciones
-- ----------------------------------------------------------------------------
grant select on public.evaluaciones to authenticated;

drop policy if exists evaluaciones_select on public.evaluaciones;
create policy evaluaciones_select on public.evaluaciones
  for select to authenticated
  using (public.puedo_ver_paciente(paciente_id));

-- ----------------------------------------------------------------------------
-- pagos: administracion y recepcion. El fisioterapeuta no.
-- ----------------------------------------------------------------------------
grant select, insert, update on public.pagos to authenticated;

drop policy if exists pagos_select on public.pagos;
create policy pagos_select on public.pagos
  for select to authenticated
  using (public.mi_rol() in ('superadmin', 'admin', 'recepcion'));
drop policy if exists pagos_insert on public.pagos;
create policy pagos_insert on public.pagos
  for insert to authenticated
  with check (public.mi_rol() in ('superadmin', 'admin', 'recepcion'));
drop policy if exists pagos_update on public.pagos;
create policy pagos_update on public.pagos
  for update to authenticated
  using (public.mi_rol() in ('superadmin', 'admin', 'recepcion'))
  with check (public.mi_rol() in ('superadmin', 'admin', 'recepcion'));

-- ----------------------------------------------------------------------------
-- auditoria: solo lectura y solo administracion
-- ----------------------------------------------------------------------------
grant select on public.auditoria to authenticated;

drop policy if exists auditoria_select on public.auditoria;
create policy auditoria_select on public.auditoria
  for select to authenticated using (public.es_admin());

-- ----------------------------------------------------------------------------
-- mensajes: bitacora de comunicacion, sin acceso del fisioterapeuta
-- ----------------------------------------------------------------------------
grant select on public.mensajes to authenticated;

drop policy if exists mensajes_select on public.mensajes;
create policy mensajes_select on public.mensajes
  for select to authenticated
  using (public.mi_rol() in ('superadmin', 'admin', 'recepcion'));

-- ----------------------------------------------------------------------------
-- enlaces_accion y control_solicitudes: ningun cliente los toca.
-- Se manipulan exclusivamente desde funciones SECURITY DEFINER.
-- ----------------------------------------------------------------------------
-- (sin GRANT y sin policies para anon/authenticated: acceso cero)

-- ----------------------------------------------------------------------------
-- Vistas
-- ----------------------------------------------------------------------------
grant select on public.v_saldos_paciente to authenticated;

-- ----------------------------------------------------------------------------
-- Defaults para objetos futuros: nada se expone por accidente
-- ----------------------------------------------------------------------------
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on functions from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;

-- ####################  20260825120900_10_rpc_publicas.sql  ####################

-- ============================================================================
-- NeoTerapia · 10 · RPCs publicas (rol `anon`)
-- ----------------------------------------------------------------------------
-- Estas son las UNICAS puertas que tiene el mundo exterior. El paciente no
-- crea cuenta, no inicia sesion y no puede leer ninguna tabla directamente.
-- Ninguna de estas funciones devuelve historial clinico.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Control de abuso
-- ----------------------------------------------------------------------------

-- Resuelve pgcrypto / pg_trgm / unaccent vivan donde vivan (Supabase las pone
-- en `extensions`; un Postgres normal las deja en `public`).
set search_path = public, extensions;

create or replace function public.control_intento(
  p_clave   text,
  p_max     int,
  p_ventana interval default interval '1 hour'
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seg      bigint := greatest(extract(epoch from p_ventana)::bigint, 1);
  v_ventana  timestamptz := to_timestamp(floor(extract(epoch from now()) / v_seg) * v_seg);
  v_conteo   int;
begin
  insert into public.control_solicitudes (clave, ventana, conteo, ultimo_en)
  values (p_clave, v_ventana, 1, now())
  on conflict (clave, ventana)
    do update set conteo = public.control_solicitudes.conteo + 1, ultimo_en = now()
  returning conteo into v_conteo;

  return v_conteo <= p_max;
end;
$$;

-- ----------------------------------------------------------------------------
-- Catalogo del mapa corporal (lo consume el formulario publico)
-- ----------------------------------------------------------------------------

create or replace function public.areas_mapa()
returns table (
  codigo text,
  nombre text,
  region public.region_cuerpo,
  lado   public.lado_cuerpo,
  vista  public.vista_cuerpo,
  svg_x  numeric,
  svg_y  numeric,
  orden  int
)
language sql
stable
security definer
set search_path = public
as $$
  select a.codigo, a.nombre, a.region, a.lado, a.vista, a.svg_x, a.svg_y, a.orden
  from public.areas_cuerpo a
  where a.activo
  order by a.vista, a.orden, a.nombre
$$;

-- ----------------------------------------------------------------------------
-- Disponibilidad
-- ----------------------------------------------------------------------------
-- Devuelve unicamente horas y cupos. Jamas nombres de pacientes ni motivos.

create or replace function public.slots_disponibles(
  p_fecha date,
  p_fisioterapeuta_id uuid default null
) returns table (
  hora            time,
  inicio          timestamptz,
  cupos_totales   int,
  cupos_ocupados  int,
  disponible      boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz            text := coalesce(public.config('zona_horaria') #>> '{}', 'America/Guatemala');
  v_dur           int  := public.config_int('duracion_cita_min', 45);
  v_max_dias      int  := public.config_int('dias_anticipacion_max', 60);
  v_min_horas     int  := public.config_int('horas_anticipacion_min', 12);
  v_dow           int;
begin
  if p_fecha is null
     or p_fecha < current_date
     or p_fecha > current_date + v_max_dias then
    return;
  end if;

  v_dow := extract(dow from p_fecha)::int;

  return query
  with rangos as (
    select h.hora_inicio, h.hora_fin, h.cupos, h.fisioterapeuta_id
    from public.horarios_atencion h
    where h.activo
      and h.dia_semana = v_dow
      and h.vigente_desde <= p_fecha
      and (h.vigente_hasta is null or h.vigente_hasta >= p_fecha)
      and (p_fisioterapeuta_id is null
           or h.fisioterapeuta_id is null
           or h.fisioterapeuta_id = p_fisioterapeuta_id)
  ),
  puntos as (
    select
      (gs)::time                                            as hora,
      (gs at time zone v_tz)                                as inicio_tz,
      sum(r.cupos)::int                                     as cupos
    from rangos r
    cross join lateral generate_series(
      (p_fecha + r.hora_inicio)::timestamp,
      (p_fecha + r.hora_fin)::timestamp - make_interval(mins => v_dur),
      make_interval(mins => v_dur)
    ) gs
    group by 1, 2
  )
  select
    p.hora,
    p.inicio_tz,
    p.cupos,
    coalesce(oc.n, 0)::int,
    (p.inicio_tz >= now() + make_interval(hours => v_min_horas))
      and coalesce(oc.n, 0) < p.cupos
      and not exists (
        select 1 from public.bloqueos_agenda b
        where (p_fisioterapeuta_id is null or b.fisioterapeuta_id is null
               or b.fisioterapeuta_id = p_fisioterapeuta_id)
          and tstzrange(b.inicio, b.fin) && tstzrange(p.inicio_tz, p.inicio_tz + make_interval(mins => v_dur))
      )
  from puntos p
  left join lateral (
    select count(*)::int as n
    from public.citas c
    where c.estado in ('solicitada', 'confirmada')
      and (
        (c.inicio_programado is not null
         and tstzrange(c.inicio_programado, c.fin_programado)
             && tstzrange(p.inicio_tz, p.inicio_tz + make_interval(mins => v_dur)))
        or (c.inicio_programado is null
            and c.fecha_solicitada = p_fecha
            and c.hora_solicitada = p.hora)
      )
      and (p_fisioterapeuta_id is null or c.fisioterapeuta_id is null
           or c.fisioterapeuta_id = p_fisioterapeuta_id)
  ) oc on true
  order by p.hora;
end;
$$;

-- ----------------------------------------------------------------------------
-- Solicitud de cita  ·  el corazon del flujo publico
-- ----------------------------------------------------------------------------
-- Crea o reutiliza la ficha del paciente usando el DPI normalizado como
-- identificador principal, y deja alerta si el nombre no cuadra.
-- Devuelve UNICAMENTE el codigo de referencia: nada del historial.

create or replace function public.solicitar_cita(p_datos jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_tipo_doc     public.tipo_documento;
  v_dpi_raw      text;
  v_dpi          text;
  v_validacion   jsonb;
  v_nombre       text;
  v_tel          text;
  v_wa           text;
  v_email        text;
  v_canal        public.canal_contacto;
  v_fecha        date;
  v_hora         time;
  v_franja       text;
  v_areas        jsonb;
  v_area         jsonb;
  v_area_id      uuid;
  v_paciente     public.pacientes%rowtype;
  v_paciente_id  uuid;
  v_nuevo        boolean := false;
  v_similitud    real;
  v_codigo       text;
  v_cita_id      uuid;
  v_ip           inet := public.request_ip();
  v_max_dias     int  := public.config_int('dias_anticipacion_max', 60);
  v_min_horas    int  := public.config_int('horas_anticipacion_min', 12);
  v_umbral       real := coalesce((public.config('umbral_similitud_nombre') #>> '{}')::real, 0.55);
  v_existente    record;
  v_intentos     int := 0;
begin
  -- ---------- 1. Lectura y normalizacion --------------------------------
  v_tipo_doc := coalesce((p_datos ->> 'tipo_documento')::public.tipo_documento, 'dpi');
  v_dpi_raw  := btrim(coalesce(p_datos ->> 'dpi', ''));
  v_nombre   := btrim(coalesce(p_datos ->> 'nombre_completo', ''));
  v_tel      := nullif(btrim(coalesce(p_datos ->> 'telefono', '')), '');
  v_wa       := nullif(btrim(coalesce(p_datos ->> 'whatsapp', '')), '');
  v_email    := public.normalizar_email(p_datos ->> 'email');
  v_canal    := coalesce((p_datos ->> 'canal_preferido')::public.canal_contacto, 'whatsapp');
  v_fecha    := (p_datos ->> 'fecha')::date;
  v_hora     := nullif(p_datos ->> 'hora', '')::time;
  v_franja   := nullif(p_datos ->> 'franja', '');
  v_areas    := coalesce(p_datos -> 'areas', '[]'::jsonb);

  -- ---------- 2. Validaciones de entrada --------------------------------
  if coalesce((p_datos ->> 'acepta_politica')::boolean, false) is not true then
    return jsonb_build_object('ok', false, 'error', 'politica_no_aceptada',
      'mensaje', 'Debe aceptar la politica de tratamiento de datos.');
  end if;

  if length(v_nombre) < 5 or array_length(string_to_array(v_nombre, ' '), 1) < 2 then
    return jsonb_build_object('ok', false, 'error', 'nombre_invalido',
      'mensaje', 'Escriba su nombre completo (al menos nombre y apellido).');
  end if;

  if v_tel is null and v_wa is null and v_email is null then
    return jsonb_build_object('ok', false, 'error', 'sin_contacto',
      'mensaje', 'Necesitamos al menos un telefono, WhatsApp o correo para responderle.');
  end if;

  if v_canal = 'email' and v_email is null then
    return jsonb_build_object('ok', false, 'error', 'sin_correo',
      'mensaje', 'Eligio correo como canal preferido pero no lo proporciono.');
  end if;

  if v_canal = 'whatsapp' and v_wa is null and v_tel is null then
    return jsonb_build_object('ok', false, 'error', 'sin_whatsapp',
      'mensaje', 'Eligio WhatsApp como canal preferido pero no proporciono numero.');
  end if;

  if v_tipo_doc = 'dpi' then
    v_validacion := public.validar_dpi(v_dpi_raw);
    if not (v_validacion ->> 'valido')::boolean then
      return jsonb_build_object('ok', false, 'error', 'dpi_invalido',
        'motivo', v_validacion ->> 'motivo',
        'mensaje', case v_validacion ->> 'motivo'
          when 'longitud'           then 'El DPI debe tener 13 digitos.'
          when 'digito_verificador' then 'El DPI no es valido; revise los digitos.'
          when 'departamento'       then 'El codigo de departamento del DPI no es valido.'
          when 'municipio'          then 'El codigo de municipio del DPI no es valido.'
          else 'Ingrese un DPI valido.'
        end);
    end if;
    v_dpi := v_validacion ->> 'normalizado';
  else
    v_dpi := nullif(upper(regexp_replace(v_dpi_raw, '[^A-Za-z0-9]', '', 'g')), '');
    if v_dpi is null or length(v_dpi) < 5 then
      return jsonb_build_object('ok', false, 'error', 'documento_invalido',
        'mensaje', 'Ingrese un numero de documento valido.');
    end if;
  end if;

  if v_fecha is null or v_fecha < current_date then
    return jsonb_build_object('ok', false, 'error', 'fecha_invalida',
      'mensaje', 'Elija una fecha a partir de hoy.');
  end if;

  if v_fecha > current_date + v_max_dias then
    return jsonb_build_object('ok', false, 'error', 'fecha_lejana',
      'mensaje', format('Solo se aceptan solicitudes hasta %s dias de anticipacion.', v_max_dias));
  end if;

  if v_hora is not null
     and (v_fecha + v_hora) at time zone coalesce(public.config('zona_horaria') #>> '{}', 'America/Guatemala')
         < now() + make_interval(hours => v_min_horas) then
    return jsonb_build_object('ok', false, 'error', 'horario_muy_proximo',
      'mensaje', format('Las solicitudes requieren al menos %s horas de anticipacion.', v_min_horas));
  end if;

  if jsonb_array_length(v_areas) = 0 then
    return jsonb_build_object('ok', false, 'error', 'sin_areas',
      'mensaje', 'Indique al menos un area de molestia.');
  end if;

  if jsonb_array_length(v_areas) > 12 then
    return jsonb_build_object('ok', false, 'error', 'demasiadas_areas',
      'mensaje', 'Seleccione como maximo 12 areas.');
  end if;

  -- ---------- 3. Control de abuso ---------------------------------------
  if v_ip is not null and not public.control_intento('ip:' || host(v_ip), 10, interval '1 hour') then
    return jsonb_build_object('ok', false, 'error', 'demasiadas_solicitudes',
      'mensaje', 'Se recibieron demasiadas solicitudes desde esta conexion. Intente mas tarde.');
  end if;

  if not public.control_intento('doc:' || v_tipo_doc::text || ':' || v_dpi, 5, interval '24 hours') then
    return jsonb_build_object('ok', false, 'error', 'demasiadas_solicitudes',
      'mensaje', 'Ya se registraron varias solicitudes con este documento hoy. Comuniquese con la clinica.');
  end if;

  -- ---------- 4. Ficha del paciente: buscar por DPI ---------------------
  select * into v_paciente
  from public.pacientes p
  where p.tipo_documento = v_tipo_doc
    and p.dpi_norm = v_dpi
    and p.estado <> 'fusionado'
  limit 1;

  if found then
    v_paciente_id := v_paciente.id;

    -- Comprobacion de nombre: NO identifica, solo verifica.
    v_similitud := similarity(
      coalesce(v_paciente.nombre_comparable, ''),
      coalesce(public.normalizar_nombre_comparable(v_nombre), '')
    );

    if v_similitud < v_umbral then
      insert into public.alertas (tipo, severidad, paciente_id, titulo, detalle)
      values ('nombre_no_coincide', 3, v_paciente_id,
        'El nombre declarado no coincide con la ficha existente',
        jsonb_build_object(
          'nombre_en_ficha', v_paciente.nombre_completo,
          'nombre_declarado', v_nombre,
          'similitud', round(v_similitud::numeric, 3),
          'documento_enmascarado', v_paciente.dpi_mascara
        ));
    end if;

    -- Completar contacto faltante; si difiere, avisar en lugar de sobrescribir.
    if v_paciente.telefono is null and v_tel is not null then
      update public.pacientes set telefono = v_tel where id = v_paciente_id;
    elsif v_tel is not null
          and public.normalizar_telefono(v_tel) is distinct from v_paciente.telefono_norm then
      insert into public.alertas (tipo, severidad, paciente_id, titulo, detalle)
      values ('contacto_cambiado', 1, v_paciente_id, 'El paciente reporto un telefono distinto',
        jsonb_build_object('en_ficha', v_paciente.telefono, 'declarado', v_tel));
    end if;

    if v_paciente.email is null and v_email is not null then
      update public.pacientes set email = v_email where id = v_paciente_id;
    elsif v_email is not null and v_email is distinct from v_paciente.email_norm then
      insert into public.alertas (tipo, severidad, paciente_id, titulo, detalle)
      values ('contacto_cambiado', 1, v_paciente_id, 'El paciente reporto un correo distinto',
        jsonb_build_object('en_ficha', v_paciente.email, 'declarado', v_email));
    end if;

    if v_paciente.whatsapp is null and v_wa is not null then
      update public.pacientes set whatsapp = v_wa where id = v_paciente_id;
    end if;

  else
    -- Alta automatica de la ficha interna.
    insert into public.pacientes (
      tipo_documento, dpi, nombre_completo, telefono, whatsapp, email,
      canal_preferido, creado_por
    ) values (
      v_tipo_doc, v_dpi, v_nombre, v_tel, v_wa, v_email, v_canal, null
    )
    returning id into v_paciente_id;

    v_nuevo := true;
  end if;

  -- ---------- 5. Evitar solicitudes repetidas el mismo dia --------------
  select c.id, c.codigo_referencia, c.estado into v_existente
  from public.citas c
  where c.paciente_id = v_paciente_id
    and c.fecha_solicitada = v_fecha
    and c.estado in ('solicitada', 'confirmada')
  limit 1;

  if found then
    return jsonb_build_object(
      'ok', true,
      'duplicada', true,
      'codigo_referencia', v_existente.codigo_referencia,
      'estado', v_existente.estado,
      'fecha_solicitada', v_fecha,
      'mensaje', 'Ya existe una solicitud para esa fecha con este documento.'
    );
  end if;

  -- ---------- 6. Crear la cita ------------------------------------------
  loop
    v_intentos := v_intentos + 1;
    v_codigo := public.generar_codigo_referencia();
    exit when not exists (select 1 from public.citas c where c.codigo_referencia = v_codigo);
    if v_intentos > 12 then
      raise exception 'No se pudo generar un codigo de referencia unico.';
    end if;
  end loop;

  insert into public.citas (
    codigo_referencia, paciente_id, estado, origen,
    fecha_solicitada, hora_solicitada, franja_solicitada,
    nombre_declarado, telefono_declarado, whatsapp_declarado, email_declarado,
    canal_preferido, motivo_consulta, comentarios_paciente, es_primera_vez,
    ip_solicitud, user_agent_solicitud
  ) values (
    v_codigo, v_paciente_id, 'solicitada', 'publico',
    v_fecha, v_hora, coalesce(v_franja, 'indistinto'),
    v_nombre, v_tel, v_wa, v_email,
    v_canal,
    nullif(btrim(coalesce(p_datos ->> 'motivo_consulta', '')), ''),
    nullif(btrim(coalesce(p_datos ->> 'comentarios', '')), ''),
    coalesce((p_datos ->> 'es_primera_vez')::boolean, v_nuevo),
    v_ip, public.request_user_agent()
  )
  returning id into v_cita_id;

  -- ---------- 7. Areas de molestia --------------------------------------
  for v_area in select * from jsonb_array_elements(v_areas) loop
    select a.id into v_area_id
    from public.areas_cuerpo a
    where a.codigo = (v_area ->> 'codigo') and a.activo;

    if v_area_id is null then
      raise exception 'Area de molestia desconocida: %', (v_area ->> 'codigo')
        using errcode = 'foreign_key_violation';
    end if;

    insert into public.cita_areas (cita_id, area_id, intensidad, nota)
    values (
      v_cita_id, v_area_id,
      least(greatest(coalesce((v_area ->> 'intensidad')::int, 0), 0), 10),
      nullif(btrim(coalesce(v_area ->> 'nota', '')), '')
    )
    on conflict (cita_id, area_id) do nothing;

    v_area_id := null;
  end loop;

  -- ---------- 8. Encolar acuse (sin envio: no hay proveedor conectado) ---
  perform public.encolar_mensaje(v_cita_id, 'solicitud_recibida');

  -- ---------- 9. Auditoria ----------------------------------------------
  perform public.registrar_auditoria(
    'acceso_publico', 'citas', v_cita_id::text, v_paciente_id,
    format('Solicitud publica de cita (%s)', v_codigo),
    null,
    jsonb_build_object('codigo', v_codigo, 'paciente_nuevo', v_nuevo, 'fecha', v_fecha)
  );

  return jsonb_build_object(
    'ok', true,
    'duplicada', false,
    'codigo_referencia', v_codigo,
    'estado', 'solicitada',
    'fecha_solicitada', v_fecha,
    'canal', v_canal,
    'mensaje', 'Su solicitud fue recibida. La clinica le confirmara por su canal preferido.'
  );
end;
$$;

comment on function public.solicitar_cita(jsonb) is
  'Unica via publica para pedir cita. Crea o reutiliza la ficha por DPI. No expone historial.';

-- ----------------------------------------------------------------------------
-- Enlaces de accion: confirmar / cancelar / evaluar sin portal
-- ----------------------------------------------------------------------------

create or replace function public.usar_enlace_accion(p_token text, p_datos jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_enlace public.enlaces_accion%rowtype;
  v_cita   public.citas%rowtype;
  v_ip     inet := public.request_ip();
begin
  if p_token is null or length(p_token) < 32 then
    return jsonb_build_object('ok', false, 'error', 'token_invalido');
  end if;

  if v_ip is not null and not public.control_intento('enlace:' || host(v_ip), 30, interval '1 hour') then
    return jsonb_build_object('ok', false, 'error', 'demasiados_intentos');
  end if;

  select * into v_enlace
  from public.enlaces_accion e
  where e.token_hash = public.hash_token(p_token)
  limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'token_invalido');
  end if;
  if v_enlace.revocado_en is not null then
    return jsonb_build_object('ok', false, 'error', 'enlace_revocado');
  end if;
  if v_enlace.expira_en < now() then
    return jsonb_build_object('ok', false, 'error', 'enlace_vencido');
  end if;
  if v_enlace.usos >= v_enlace.max_usos then
    return jsonb_build_object('ok', false, 'error', 'enlace_agotado');
  end if;

  select * into v_cita from public.citas c where c.id = v_enlace.cita_id;

  -- Efecto segun el tipo de enlace
  if v_enlace.tipo = 'confirmar' then
    if v_cita.estado not in ('solicitada', 'confirmada') then
      return jsonb_build_object('ok', false, 'error', 'estado_no_permite',
        'estado', v_cita.estado);
    end if;
    update public.citas
       set notas_internas = coalesce(notas_internas, '') || E'\n[paciente confirmo asistencia ' || now()::date || ']'
     where id = v_cita.id;

  elsif v_enlace.tipo = 'cancelar' then
    if v_cita.estado not in ('solicitada', 'confirmada') then
      return jsonb_build_object('ok', false, 'error', 'estado_no_permite',
        'estado', v_cita.estado);
    end if;
    update public.citas
       set estado = 'cancelada',
           motivo_estado = coalesce(nullif(btrim(p_datos ->> 'motivo'), ''), 'Cancelada por el paciente desde el enlace'),
           resuelta_en = now()
     where id = v_cita.id;
    perform public.encolar_mensaje(v_cita.id, 'cancelacion');

  elsif v_enlace.tipo = 'evaluacion' then
    if v_cita.estado <> 'atendida' then
      return jsonb_build_object('ok', false, 'error', 'estado_no_permite', 'estado', v_cita.estado);
    end if;
    if (p_datos ->> 'puntuacion') is null then
      -- Primera visita al enlace: solo se valida y se devuelve contexto minimo.
      return jsonb_build_object(
        'ok', true, 'accion', 'evaluacion', 'requiere', 'puntuacion',
        'codigo_referencia', v_cita.codigo_referencia,
        'fecha', v_cita.inicio_programado
      );
    end if;
    insert into public.evaluaciones (cita_id, paciente_id, puntuacion, dolor_reportado, comentario, recomendaria, ip)
    values (
      v_cita.id, v_cita.paciente_id,
      least(greatest((p_datos ->> 'puntuacion')::int, 1), 5),
      nullif(p_datos ->> 'dolor_reportado', '')::int,
      nullif(btrim(coalesce(p_datos ->> 'comentario', '')), ''),
      nullif(p_datos ->> 'recomendaria', '')::boolean,
      v_ip
    )
    on conflict (cita_id) do nothing;
  end if;

  update public.enlaces_accion
     set usos = usos + 1,
         usado_en = coalesce(usado_en, now()),
         ip_uso = coalesce(ip_uso, v_ip)
   where id = v_enlace.id;

  perform public.registrar_auditoria(
    'acceso_publico', 'enlaces_accion', v_enlace.id::text, v_cita.paciente_id,
    format('Enlace %s usado para la cita %s', v_enlace.tipo, v_cita.codigo_referencia)
  );

  -- Se devuelve lo minimo indispensable: nunca historial ni datos de otras citas.
  return jsonb_build_object(
    'ok', true,
    'accion', v_enlace.tipo,
    'codigo_referencia', v_cita.codigo_referencia,
    'fecha', coalesce(v_cita.inicio_programado::text, v_cita.fecha_solicitada::text),
    'mensaje', case v_enlace.tipo
      when 'confirmar'  then 'Gracias, su asistencia quedo confirmada.'
      when 'cancelar'   then 'Su cita fue cancelada. Puede solicitar una nueva cuando guste.'
      when 'evaluacion' then 'Gracias por su evaluacion.'
      else 'Listo.'
    end
  );
end;
$$;

comment on function public.usar_enlace_accion(text, jsonb) is
  'Ejecuta la accion asociada a un enlace de un solo uso. No expone el expediente del paciente.';

-- Datos minimos de una cita para pintar la pantalla del enlace o generar el ICS.
create or replace function public.cita_publica_por_token(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_enlace public.enlaces_accion%rowtype;
  v_cita   public.citas%rowtype;
begin
  select * into v_enlace from public.enlaces_accion e where e.token_hash = public.hash_token(p_token);
  if not found or v_enlace.revocado_en is not null or v_enlace.expira_en < now() then
    return jsonb_build_object('ok', false, 'error', 'token_invalido');
  end if;

  select * into v_cita from public.citas c where c.id = v_enlace.cita_id;

  return jsonb_build_object(
    'ok', true,
    'tipo', v_enlace.tipo,
    'codigo_referencia', v_cita.codigo_referencia,
    'estado', v_cita.estado,
    'inicio', v_cita.inicio_programado,
    'fin', v_cita.fin_programado,
    'fecha_solicitada', v_cita.fecha_solicitada,
    -- Solo el primer nombre: suficiente para saludar, insuficiente para identificar.
    'saludo', split_part(btrim(v_cita.nombre_declarado), ' ', 1)
  );
end;
$$;

-- ####################  20260825121000_11_rpc_internas.sql  ####################

-- ============================================================================
-- NeoTerapia · 11 · RPCs internas (personal autenticado)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Acceso auditado al DPI completo
-- ----------------------------------------------------------------------------

-- Resuelve pgcrypto / pg_trgm / unaccent vivan donde vivan (Supabase las pone
-- en `extensions`; un Postgres normal las deja en `public`).
set search_path = public, extensions;

create or replace function public.ver_dpi_paciente(p_paciente_id uuid, p_motivo text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dpi   text;
  v_tipo  public.tipo_documento;
  v_rol   public.rol_usuario := public.mi_rol();
begin
  if v_rol is null then
    raise exception 'No autenticado.' using errcode = 'insufficient_privilege';
  end if;

  -- Recepcion coordina citas: no necesita el documento completo.
  if v_rol not in ('superadmin', 'admin')
     and not (v_rol = 'fisioterapeuta' and public.atiendo_paciente(p_paciente_id)) then
    raise exception 'Su rol no permite ver el documento completo del paciente.'
      using errcode = 'insufficient_privilege';
  end if;

  select p.dpi, p.tipo_documento into v_dpi, v_tipo
  from public.pacientes p where p.id = p_paciente_id;

  if v_dpi is null then
    raise exception 'Paciente no encontrado.' using errcode = 'no_data_found';
  end if;

  perform public.registrar_auditoria(
    'consultar_sensible', 'pacientes', p_paciente_id::text, p_paciente_id,
    coalesce(nullif(btrim(p_motivo), ''), 'Consulta de documento completo')
  );

  return jsonb_build_object('documento', v_dpi, 'tipo', v_tipo);
end;
$$;

comment on function public.ver_dpi_paciente(uuid, text) is
  'Unica via para destapar el DPI. Valida rol y deja registro en auditoria.';

-- ----------------------------------------------------------------------------
-- Busqueda de pacientes
-- ----------------------------------------------------------------------------

create or replace function public.buscar_pacientes(p_texto text, p_limite int default 25)
returns table (
  id                uuid,
  nombre_completo   text,
  dpi_mascara       text,
  telefono          text,
  email             text,
  estado            public.estado_paciente,
  fisioterapeuta_id uuid,
  ultima_cita       timestamptz,
  citas_totales     bigint,
  coincidencia      real
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_texto  text := btrim(coalesce(p_texto, ''));
  v_digits text := regexp_replace(v_texto, '\D', '', 'g');
  v_nombre text := public.normalizar_nombre_comparable(v_texto);
  v_rol    public.rol_usuario := public.mi_rol();
begin
  if v_rol is null then
    raise exception 'No autenticado.' using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    p.id, p.nombre_completo, p.dpi_mascara, p.telefono, p.email, p.estado, p.fisioterapeuta_id,
    ult.ultima, coalesce(ult.total, 0),
    greatest(
      case when v_nombre is null then 0
           else similarity(coalesce(p.nombre_comparable, ''), v_nombre) end,
      case when length(v_digits) >= 4 and p.dpi_norm like '%' || v_digits || '%' then 1.0 else 0 end
    )::real as coincidencia
  from public.pacientes p
  left join lateral (
    select max(c.creado_en) as ultima, count(*) as total
    from public.citas c where c.paciente_id = p.id
  ) ult on true
  where public.puedo_ver_paciente(p.id)
    and (
      v_texto = ''
      or (length(v_digits) >= 4 and p.dpi_norm like '%' || v_digits || '%')
      or (length(v_digits) >= 4 and coalesce(p.telefono_norm, '') like '%' || v_digits || '%')
      or (length(v_digits) >= 4 and coalesce(p.whatsapp_norm, '') like '%' || v_digits || '%')
      or (v_nombre is not null and similarity(coalesce(p.nombre_comparable, ''), v_nombre) > 0.25)
      or (v_texto <> '' and coalesce(p.email_norm, '') like '%' || lower(v_texto) || '%')
    )
  order by coincidencia desc nulls last, ult.ultima desc nulls last
  limit least(greatest(coalesce(p_limite, 25), 1), 100);
end;
$$;

-- ----------------------------------------------------------------------------
-- Alta interna de paciente (telefono / mostrador)
-- ----------------------------------------------------------------------------

create or replace function public.registrar_paciente(p_datos jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tipo   public.tipo_documento := coalesce((p_datos ->> 'tipo_documento')::public.tipo_documento, 'dpi');
  v_dpi    text;
  v_val    jsonb;
  v_id     uuid;
  v_exist  uuid;
begin
  if public.mi_rol() not in ('superadmin', 'admin', 'recepcion') then
    raise exception 'Su rol no permite registrar pacientes.' using errcode = 'insufficient_privilege';
  end if;

  if v_tipo = 'dpi' then
    v_val := public.validar_dpi(p_datos ->> 'dpi');
    if not (v_val ->> 'valido')::boolean then
      return jsonb_build_object('ok', false, 'error', 'dpi_invalido', 'motivo', v_val ->> 'motivo');
    end if;
    v_dpi := v_val ->> 'normalizado';
  else
    v_dpi := nullif(upper(regexp_replace(coalesce(p_datos ->> 'dpi', ''), '[^A-Za-z0-9]', '', 'g')), '');
  end if;

  select p.id into v_exist
  from public.pacientes p
  where p.tipo_documento = v_tipo and p.dpi_norm = v_dpi and p.estado <> 'fusionado';

  if v_exist is not null then
    return jsonb_build_object('ok', false, 'error', 'documento_existente', 'paciente_id', v_exist);
  end if;

  insert into public.pacientes (
    tipo_documento, dpi, nombre_completo, fecha_nacimiento, sexo,
    telefono, whatsapp, email, canal_preferido, direccion,
    contacto_emergencia, telefono_emergencia, fisioterapeuta_id,
    notas_administrativas, creado_por
  ) values (
    v_tipo, v_dpi,
    btrim(p_datos ->> 'nombre_completo'),
    nullif(p_datos ->> 'fecha_nacimiento', '')::date,
    nullif(p_datos ->> 'sexo', ''),
    nullif(btrim(coalesce(p_datos ->> 'telefono', '')), ''),
    nullif(btrim(coalesce(p_datos ->> 'whatsapp', '')), ''),
    public.normalizar_email(p_datos ->> 'email'),
    coalesce((p_datos ->> 'canal_preferido')::public.canal_contacto, 'whatsapp'),
    nullif(btrim(coalesce(p_datos ->> 'direccion', '')), ''),
    nullif(btrim(coalesce(p_datos ->> 'contacto_emergencia', '')), ''),
    nullif(btrim(coalesce(p_datos ->> 'telefono_emergencia', '')), ''),
    nullif(p_datos ->> 'fisioterapeuta_id', '')::uuid,
    nullif(btrim(coalesce(p_datos ->> 'notas_administrativas', '')), ''),
    auth.uid()
  )
  returning id into v_id;

  return jsonb_build_object('ok', true, 'paciente_id', v_id);
end;
$$;

-- ----------------------------------------------------------------------------
-- Gestion de citas
-- ----------------------------------------------------------------------------

-- Devuelve los enlaces de accion listos para pegar en WhatsApp o correo.
create or replace function public.emitir_enlaces_cita(p_cita_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_base   text := coalesce(public.config('url_publica') #>> '{}', 'https://neoterapia.vercel.app');
  v_conf   text;
  v_canc   text;
begin
  if public.mi_rol() not in ('superadmin', 'admin', 'recepcion') then
    raise exception 'Su rol no permite emitir enlaces.' using errcode = 'insufficient_privilege';
  end if;

  -- Se revocan los enlaces previos del mismo tipo: siempre hay uno vigente.
  update public.enlaces_accion
     set revocado_en = now()
   where cita_id = p_cita_id and tipo in ('confirmar', 'cancelar') and revocado_en is null;

  v_conf := public.emitir_enlace_accion(p_cita_id, 'confirmar', 168, 3);
  v_canc := public.emitir_enlace_accion(p_cita_id, 'cancelar', 168, 1);

  return jsonb_build_object(
    'confirmar', v_base || '/cita/confirmar?t=' || v_conf,
    'cancelar',  v_base || '/cita/cancelar?t='  || v_canc,
    'calendario', v_base || '/cita/calendario?t=' || v_conf
  );
end;
$$;

drop function if exists public.confirmar_cita(uuid, timestamptz, uuid, int, text, text);

create or replace function public.confirmar_cita(
  p_cita_id           uuid,
  p_inicio            timestamptz,
  p_fisioterapeuta_id uuid,
  p_duracion_min      int default null,
  p_consultorio       text default null,
  p_nota              text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dur     int := coalesce(p_duracion_min, public.config_int('duracion_cita_min', 45));
  v_cita    public.citas%rowtype;
  v_enlaces jsonb;
begin
  if public.mi_rol() not in ('superadmin', 'admin', 'recepcion') then
    raise exception 'Su rol no permite confirmar citas.' using errcode = 'insufficient_privilege';
  end if;

  select * into v_cita from public.citas where id = p_cita_id for update;
  if not found then
    raise exception 'Cita no encontrada.' using errcode = 'no_data_found';
  end if;
  if v_cita.estado not in ('solicitada', 'confirmada') then
    return jsonb_build_object('ok', false, 'error', 'estado_no_permite', 'estado', v_cita.estado);
  end if;

  update public.citas
     set estado            = 'confirmada',
         inicio_programado = p_inicio,
         fin_programado    = p_inicio + make_interval(mins => v_dur),
         fisioterapeuta_id = p_fisioterapeuta_id,
         consultorio       = coalesce(p_consultorio, consultorio),
         notas_internas    = coalesce(p_nota, notas_internas),
         motivo_estado     = null,
         resuelta_por      = auth.uid(),
         resuelta_en       = now()
   where id = p_cita_id;

  -- Si el paciente no tiene fisioterapeuta principal, este pasa a serlo.
  update public.pacientes
     set fisioterapeuta_id = p_fisioterapeuta_id
   where id = v_cita.paciente_id and fisioterapeuta_id is null;

  v_enlaces := public.emitir_enlaces_cita(p_cita_id);
  perform public.encolar_mensaje(p_cita_id, 'confirmacion', jsonb_build_object(
    'enlaces', format(E'Confirmar asistencia: %s\nCancelar: %s',
                      v_enlaces ->> 'confirmar', v_enlaces ->> 'cancelar')
  ));

  return jsonb_build_object('ok', true, 'estado', 'confirmada', 'enlaces', v_enlaces);
exception
  when exclusion_violation then
    return jsonb_build_object('ok', false, 'error', 'traslape',
      'mensaje', 'Ese fisioterapeuta ya tiene una cita confirmada en ese horario.');
end;
$$;

create or replace function public.rechazar_cita(p_cita_id uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.mi_rol() not in ('superadmin', 'admin', 'recepcion') then
    raise exception 'Su rol no permite rechazar citas.' using errcode = 'insufficient_privilege';
  end if;
  if length(btrim(coalesce(p_motivo, ''))) < 3 then
    return jsonb_build_object('ok', false, 'error', 'motivo_requerido');
  end if;

  update public.citas
     set estado = 'rechazada', motivo_estado = btrim(p_motivo),
         resuelta_por = auth.uid(), resuelta_en = now()
   where id = p_cita_id and estado = 'solicitada';

  if not found then
    return jsonb_build_object('ok', false, 'error', 'estado_no_permite');
  end if;

  perform public.encolar_mensaje(p_cita_id, 'rechazo');
  return jsonb_build_object('ok', true, 'estado', 'rechazada');
end;
$$;

create or replace function public.cancelar_cita(p_cita_id uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.mi_rol() not in ('superadmin', 'admin', 'recepcion') then
    raise exception 'Su rol no permite cancelar citas.' using errcode = 'insufficient_privilege';
  end if;

  update public.citas
     set estado = 'cancelada', motivo_estado = nullif(btrim(coalesce(p_motivo, '')), ''),
         resuelta_por = auth.uid(), resuelta_en = now()
   where id = p_cita_id and estado in ('solicitada', 'confirmada');

  if not found then
    return jsonb_build_object('ok', false, 'error', 'estado_no_permite');
  end if;

  update public.enlaces_accion set revocado_en = now()
   where cita_id = p_cita_id and revocado_en is null;

  perform public.encolar_mensaje(p_cita_id, 'cancelacion');
  return jsonb_build_object('ok', true, 'estado', 'cancelada');
end;
$$;

-- Reprogramar crea una cita nueva encadenada y cierra la anterior.
create or replace function public.reprogramar_cita(
  p_cita_id           uuid,
  p_nuevo_inicio      timestamptz,
  p_fisioterapeuta_id uuid default null,
  p_motivo            text default null,
  p_duracion_min      int  default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old     public.citas%rowtype;
  v_nueva   uuid;
  v_codigo  text;
  v_dur     int := coalesce(p_duracion_min, public.config_int('duracion_cita_min', 45));
  v_tz      text := coalesce(public.config('zona_horaria') #>> '{}', 'America/Guatemala');
  v_enlaces jsonb;
  v_i       int := 0;
begin
  if public.mi_rol() not in ('superadmin', 'admin', 'recepcion') then
    raise exception 'Su rol no permite reprogramar citas.' using errcode = 'insufficient_privilege';
  end if;

  select * into v_old from public.citas where id = p_cita_id for update;
  if not found or v_old.estado not in ('solicitada', 'confirmada') then
    return jsonb_build_object('ok', false, 'error', 'estado_no_permite');
  end if;

  loop
    v_i := v_i + 1;
    v_codigo := public.generar_codigo_referencia();
    exit when not exists (select 1 from public.citas where codigo_referencia = v_codigo);
    if v_i > 12 then raise exception 'No se pudo generar codigo de referencia.'; end if;
  end loop;

  insert into public.citas (
    codigo_referencia, paciente_id, estado, origen,
    fecha_solicitada, hora_solicitada, franja_solicitada,
    inicio_programado, fin_programado, fisioterapeuta_id, consultorio,
    nombre_declarado, telefono_declarado, whatsapp_declarado, email_declarado,
    canal_preferido, motivo_consulta, comentarios_paciente,
    reprogramada_desde_id, creado_por, resuelta_por, resuelta_en
  ) values (
    v_codigo, v_old.paciente_id, 'confirmada', 'interno',
    (p_nuevo_inicio at time zone v_tz)::date,
    (p_nuevo_inicio at time zone v_tz)::time,
    'indistinto',
    p_nuevo_inicio, p_nuevo_inicio + make_interval(mins => v_dur),
    coalesce(p_fisioterapeuta_id, v_old.fisioterapeuta_id), v_old.consultorio,
    v_old.nombre_declarado, v_old.telefono_declarado, v_old.whatsapp_declarado, v_old.email_declarado,
    v_old.canal_preferido, v_old.motivo_consulta, v_old.comentarios_paciente,
    p_cita_id, auth.uid(), auth.uid(), now()
  )
  returning id into v_nueva;

  -- Se arrastran las areas de molestia declaradas.
  insert into public.cita_areas (cita_id, area_id, intensidad, nota)
  select v_nueva, ca.area_id, ca.intensidad, ca.nota
  from public.cita_areas ca where ca.cita_id = p_cita_id;

  update public.citas
     set estado = 'reprogramada',
         motivo_estado = nullif(btrim(coalesce(p_motivo, '')), ''),
         resuelta_por = auth.uid(), resuelta_en = now()
   where id = p_cita_id;

  update public.enlaces_accion set revocado_en = now()
   where cita_id = p_cita_id and revocado_en is null;

  v_enlaces := public.emitir_enlaces_cita(v_nueva);
  perform public.encolar_mensaje(v_nueva, 'reprogramacion', jsonb_build_object(
    'enlaces', format(E'Confirmar asistencia: %s\nCancelar: %s',
                      v_enlaces ->> 'confirmar', v_enlaces ->> 'cancelar')));

  return jsonb_build_object('ok', true, 'cita_id', v_nueva,
                            'codigo_referencia', v_codigo, 'enlaces', v_enlaces);
exception
  when exclusion_violation then
    return jsonb_build_object('ok', false, 'error', 'traslape',
      'mensaje', 'Ese fisioterapeuta ya tiene una cita confirmada en ese horario.');
end;
$$;

-- Asistencia: al marcar `atendida` se abre automaticamente la sesion clinica.
create or replace function public.marcar_asistencia(p_cita_id uuid, p_asistio boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cita   public.citas%rowtype;
  v_sesion uuid;
  v_rol    public.rol_usuario := public.mi_rol();
begin
  select * into v_cita from public.citas where id = p_cita_id;
  if not found then
    raise exception 'Cita no encontrada.' using errcode = 'no_data_found';
  end if;

  if v_rol not in ('superadmin', 'admin', 'recepcion')
     and not (v_rol = 'fisioterapeuta' and v_cita.fisioterapeuta_id = auth.uid()) then
    raise exception 'Su rol no permite registrar asistencia en esta cita.'
      using errcode = 'insufficient_privilege';
  end if;

  if p_asistio then
    update public.citas
       set estado = 'atendida', asistio_en = now(), resuelta_por = auth.uid(), resuelta_en = now()
     where id = p_cita_id;

    insert into public.sesiones (cita_id, paciente_id, fisioterapeuta_id, inicio)
    values (p_cita_id, v_cita.paciente_id,
            coalesce(v_cita.fisioterapeuta_id, auth.uid()),
            coalesce(v_cita.inicio_programado, now()))
    on conflict (cita_id) do nothing
    returning id into v_sesion;

    if v_sesion is null then
      select id into v_sesion from public.sesiones where cita_id = p_cita_id;
    end if;

    -- Se precargan las areas que el paciente declaro, para que el
    -- fisioterapeuta parta del mapa corporal que el mismo marco.
    insert into public.sesion_areas (sesion_id, area_id, nivel_dolor)
    select v_sesion, ca.area_id, coalesce(ca.intensidad, 0)
    from public.cita_areas ca where ca.cita_id = p_cita_id
    on conflict (sesion_id, area_id) do nothing;

    return jsonb_build_object('ok', true, 'estado', 'atendida', 'sesion_id', v_sesion);
  else
    update public.citas
       set estado = 'ausente', resuelta_por = auth.uid(), resuelta_en = now()
     where id = p_cita_id;
    return jsonb_build_object('ok', true, 'estado', 'ausente');
  end if;
end;
$$;

-- Cierra la sesion, la firma y encola la invitacion a evaluar.
create or replace function public.firmar_sesion(p_sesion_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_s     public.sesiones%rowtype;
  v_token text;
  v_base  text := coalesce(public.config('url_publica') #>> '{}', 'https://neoterapia.vercel.app');
begin
  select * into v_s from public.sesiones where id = p_sesion_id;
  if not found then
    raise exception 'Sesion no encontrada.' using errcode = 'no_data_found';
  end if;
  if not (public.es_admin() or v_s.fisioterapeuta_id = auth.uid()) then
    raise exception 'Solo el fisioterapeuta responsable puede firmar la sesion.'
      using errcode = 'insufficient_privilege';
  end if;
  if v_s.firmada_en is not null then
    return jsonb_build_object('ok', false, 'error', 'ya_firmada');
  end if;

  -- `inicio` es la hora agendada: si se firma antes de esa hora, el cierre no
  -- puede quedar antes del inicio (lo impide ck_sesion_rango).
  update public.sesiones
     set firmada_en = now(), fin = coalesce(fin, greatest(inicio, now()))
   where id = p_sesion_id;

  v_token := public.emitir_enlace_accion(v_s.cita_id, 'evaluacion', 336, 2);
  perform public.encolar_mensaje(v_s.cita_id, 'evaluacion', jsonb_build_object(
    'enlaces', v_base || '/cita/evaluacion?t=' || v_token));

  return jsonb_build_object('ok', true, 'firmada_en', now());
end;
$$;

-- ----------------------------------------------------------------------------
-- Correccion de DPI
-- ----------------------------------------------------------------------------

create or replace function public.corregir_dpi(
  p_paciente_id uuid,
  p_nuevo_dpi   text,
  p_motivo      text,
  p_tipo        public.tipo_documento default 'dpi'
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_anterior text;
  v_nuevo    text;
  v_val      jsonb;
  v_choque   uuid;
begin
  if not public.es_admin() then
    raise exception 'Solo administracion puede corregir el documento de un paciente.'
      using errcode = 'insufficient_privilege';
  end if;
  if length(btrim(coalesce(p_motivo, ''))) < 5 then
    return jsonb_build_object('ok', false, 'error', 'motivo_requerido',
      'mensaje', 'Describa por que se corrige el documento.');
  end if;

  if p_tipo = 'dpi' then
    v_val := public.validar_dpi(p_nuevo_dpi);
    if not (v_val ->> 'valido')::boolean then
      return jsonb_build_object('ok', false, 'error', 'dpi_invalido', 'motivo', v_val ->> 'motivo');
    end if;
    v_nuevo := v_val ->> 'normalizado';
  else
    v_nuevo := nullif(upper(regexp_replace(coalesce(p_nuevo_dpi, ''), '[^A-Za-z0-9]', '', 'g')), '');
  end if;

  select dpi into v_anterior from public.pacientes where id = p_paciente_id;
  if v_anterior is null then
    raise exception 'Paciente no encontrado.' using errcode = 'no_data_found';
  end if;

  select id into v_choque
  from public.pacientes
  where tipo_documento = p_tipo and dpi_norm = v_nuevo
    and estado <> 'fusionado' and id <> p_paciente_id;

  if v_choque is not null then
    return jsonb_build_object('ok', false, 'error', 'documento_en_uso',
      'paciente_id', v_choque,
      'mensaje', 'Ese documento ya pertenece a otra ficha. Considere fusionarlas.');
  end if;

  update public.pacientes
     set dpi = v_nuevo, tipo_documento = p_tipo
   where id = p_paciente_id;

  insert into public.pacientes_historial_identidad
    (paciente_id, campo, valor_anterior, valor_nuevo, motivo, realizado_por)
  values
    (p_paciente_id, 'dpi', public.enmascarar_dpi(v_anterior), public.enmascarar_dpi(v_nuevo),
     btrim(p_motivo), auth.uid());

  perform public.registrar_auditoria(
    'corregir_dpi', 'pacientes', p_paciente_id::text, p_paciente_id, btrim(p_motivo),
    jsonb_build_object('dpi', public.enmascarar_dpi(v_anterior)),
    jsonb_build_object('dpi', public.enmascarar_dpi(v_nuevo)));

  return jsonb_build_object('ok', true, 'dpi_mascara', public.enmascarar_dpi(v_nuevo));
end;
$$;

-- ----------------------------------------------------------------------------
-- Deteccion y fusion de duplicados
-- ----------------------------------------------------------------------------

create or replace function public.detectar_duplicados(p_paciente_id uuid)
returns int
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_p       public.pacientes%rowtype;
  v_umbral  real := coalesce((public.config('umbral_duplicado') #>> '{}')::real, 0.62);
  v_n       int := 0;
begin
  select * into v_p from public.pacientes where id = p_paciente_id;
  if not found then return 0; end if;

  insert into public.posibles_duplicados (paciente_a, paciente_b, motivo, puntaje)
  select v_p.id, o.id, m.motivo, m.puntaje
  from public.pacientes o
  cross join lateral (
    select
      case
        when o.telefono_norm is not null and o.telefono_norm = v_p.telefono_norm then 'telefono_igual'
        when o.email_norm    is not null and o.email_norm    = v_p.email_norm    then 'email_igual'
        else 'nombre_similar'
      end as motivo,
      greatest(
        similarity(coalesce(o.nombre_comparable, ''), coalesce(v_p.nombre_comparable, '')),
        case when o.telefono_norm is not null and o.telefono_norm = v_p.telefono_norm then 0.8 else 0 end,
        case when o.email_norm    is not null and o.email_norm    = v_p.email_norm    then 0.8 else 0 end
      )::numeric(4,3) as puntaje
  ) m
  where o.id <> v_p.id
    and o.estado <> 'fusionado'
    and m.puntaje >= v_umbral
  on conflict do nothing;

  get diagnostics v_n = row_count;

  if v_n > 0 then
    insert into public.alertas (tipo, severidad, paciente_id, titulo, detalle)
    values ('posible_duplicado', 2, v_p.id,
            'Se detectaron fichas parecidas a este paciente',
            jsonb_build_object('candidatos', v_n));
  end if;

  return v_n;
end;
$$;

create or replace function public.tg_detectar_duplicados()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.detectar_duplicados(new.id);
  return new;
end;
$$;

drop trigger if exists tg_pacientes_duplicados on public.pacientes;
create trigger tg_pacientes_duplicados after insert on public.pacientes
  for each row execute function public.tg_detectar_duplicados();

create or replace function public.fusionar_pacientes(
  p_origen_id  uuid,     -- ficha que desaparece
  p_destino_id uuid,     -- ficha que sobrevive
  p_motivo     text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_o public.pacientes%rowtype;
  v_d public.pacientes%rowtype;
  v_movidas jsonb;
begin
  if not public.es_admin() then
    raise exception 'Solo administracion puede fusionar fichas.' using errcode = 'insufficient_privilege';
  end if;
  if p_origen_id = p_destino_id then
    return jsonb_build_object('ok', false, 'error', 'misma_ficha');
  end if;
  if length(btrim(coalesce(p_motivo, ''))) < 5 then
    return jsonb_build_object('ok', false, 'error', 'motivo_requerido');
  end if;

  select * into v_o from public.pacientes where id = p_origen_id  for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'origen_no_existe'); end if;
  select * into v_d from public.pacientes where id = p_destino_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'destino_no_existe'); end if;
  if v_o.estado = 'fusionado' or v_d.estado = 'fusionado' then
    return jsonb_build_object('ok', false, 'error', 'ficha_ya_fusionada');
  end if;

  perform set_config('neoterapia.operacion_interna', 'on', true);

  -- Todo el historial se conserva: se repunta a la ficha superviviente.
  update public.citas        set paciente_id = p_destino_id where paciente_id = p_origen_id;
  update public.sesiones     set paciente_id = p_destino_id where paciente_id = p_origen_id;
  update public.evaluaciones set paciente_id = p_destino_id where paciente_id = p_origen_id;
  update public.pagos        set paciente_id = p_destino_id where paciente_id = p_origen_id;
  update public.mensajes     set paciente_id = p_destino_id where paciente_id = p_origen_id;
  update public.alertas      set paciente_id = p_destino_id where paciente_id = p_origen_id;
  update public.pacientes_historial_identidad
     set paciente_id = p_destino_id where paciente_id = p_origen_id;

  v_movidas := jsonb_build_object(
    'citas',    (select count(*) from public.citas    where paciente_id = p_destino_id),
    'sesiones', (select count(*) from public.sesiones where paciente_id = p_destino_id),
    'pagos',    (select count(*) from public.pagos    where paciente_id = p_destino_id));

  -- Datos clinicos: se concatenan, nunca se pierden.
  insert into public.pacientes_clinico as d (paciente_id, antecedentes, alergias, medicamentos, cirugias_previas, observaciones)
  select p_destino_id, o.antecedentes, o.alergias, o.medicamentos, o.cirugias_previas, o.observaciones
  from public.pacientes_clinico o where o.paciente_id = p_origen_id
  on conflict (paciente_id) do update set
    antecedentes     = concat_ws(E'\n---\n', d.antecedentes,     excluded.antecedentes),
    alergias         = concat_ws(E'\n---\n', d.alergias,         excluded.alergias),
    medicamentos     = concat_ws(E'\n---\n', d.medicamentos,     excluded.medicamentos),
    cirugias_previas = concat_ws(E'\n---\n', d.cirugias_previas, excluded.cirugias_previas),
    observaciones    = concat_ws(E'\n---\n', d.observaciones,    excluded.observaciones);

  delete from public.pacientes_clinico where paciente_id = p_origen_id;

  -- La ficha superviviente adopta los datos que le faltaban.
  update public.pacientes d set
    telefono            = coalesce(d.telefono, v_o.telefono),
    whatsapp            = coalesce(d.whatsapp, v_o.whatsapp),
    email               = coalesce(d.email, v_o.email),
    fecha_nacimiento    = coalesce(d.fecha_nacimiento, v_o.fecha_nacimiento),
    sexo                = coalesce(d.sexo, v_o.sexo),
    direccion           = coalesce(d.direccion, v_o.direccion),
    contacto_emergencia = coalesce(d.contacto_emergencia, v_o.contacto_emergencia),
    telefono_emergencia = coalesce(d.telefono_emergencia, v_o.telefono_emergencia),
    fisioterapeuta_id   = coalesce(d.fisioterapeuta_id, v_o.fisioterapeuta_id),
    notas_administrativas = concat_ws(E'\n---\n', d.notas_administrativas, v_o.notas_administrativas)
  where d.id = p_destino_id;

  update public.pacientes set
    estado          = 'fusionado',
    fusionado_en_id = p_destino_id,
    fusionado_en    = now(),
    fusionado_por   = auth.uid()
  where id = p_origen_id;

  update public.posibles_duplicados
     set estado = 'fusionado', revisado_por = auth.uid(), revisado_en = now()
   where (paciente_a = p_origen_id and paciente_b = p_destino_id)
      or (paciente_a = p_destino_id and paciente_b = p_origen_id);

  insert into public.pacientes_historial_identidad
    (paciente_id, campo, valor_anterior, valor_nuevo, motivo, realizado_por)
  values
    (p_destino_id, 'fusion', p_origen_id::text, p_destino_id::text, btrim(p_motivo), auth.uid());

  perform public.registrar_auditoria(
    'fusionar', 'pacientes', p_destino_id::text, p_destino_id,
    format('Fusion de %s hacia %s. %s', p_origen_id, p_destino_id, btrim(p_motivo)),
    jsonb_build_object('origen', to_jsonb(v_o) - 'dpi' - 'dpi_norm'),
    v_movidas);

  perform set_config('neoterapia.operacion_interna', 'off', true);

  return jsonb_build_object('ok', true, 'destino_id', p_destino_id, 'movido', v_movidas);
end;
$$;

-- ----------------------------------------------------------------------------
-- Consultas de apoyo para el panel
-- ----------------------------------------------------------------------------

-- Evolucion del mapa corporal: nivel de dolor por area a lo largo del tiempo.
create or replace function public.mapa_evolucion(p_paciente_id uuid)
returns table (
  area_codigo text,
  area_nombre text,
  vista       public.vista_cuerpo,
  svg_x       numeric,
  svg_y       numeric,
  fecha       timestamptz,
  nivel_dolor int,
  origen      text
)
language sql
stable
security definer
set search_path = public
as $$
  select a.codigo, a.nombre, a.vista, a.svg_x, a.svg_y,
         s.inicio, sa.nivel_dolor, 'sesion'::text
  from public.sesion_areas sa
  join public.sesiones s   on s.id = sa.sesion_id
  join public.areas_cuerpo a on a.id = sa.area_id
  where s.paciente_id = p_paciente_id
    and public.puedo_ver_clinico(p_paciente_id)
  union all
  select a.codigo, a.nombre, a.vista, a.svg_x, a.svg_y,
         c.creado_en, ca.intensidad, 'solicitud'::text
  from public.cita_areas ca
  join public.citas c        on c.id = ca.cita_id
  join public.areas_cuerpo a on a.id = ca.area_id
  where c.paciente_id = p_paciente_id
    and ca.intensidad is not null
    and public.puedo_ver_paciente(p_paciente_id)
  order by 6
$$;

create or replace function public.metricas_tablero()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'solicitudes_pendientes', (select count(*) from public.citas where estado = 'solicitada'),
    'citas_hoy',              (select count(*) from public.citas
                                where estado = 'confirmada'
                                  and inicio_programado::date = current_date),
    'citas_semana',           (select count(*) from public.citas
                                where estado in ('confirmada', 'atendida')
                                  and inicio_programado >= date_trunc('week', now())
                                  and inicio_programado <  date_trunc('week', now()) + interval '7 days'),
    'alertas_pendientes',     (select count(*) from public.alertas where estado = 'pendiente'),
    'duplicados_pendientes',  (select count(*) from public.posibles_duplicados where estado = 'pendiente'),
    'pacientes_activos',      (select count(*) from public.pacientes where estado = 'activo'),
    'sesiones_sin_firmar',    (select count(*) from public.sesiones where firmada_en is null),
    'mensajes_en_cola',       (select count(*) from public.mensajes where estado = 'pendiente')
  )
  where public.es_staff()
$$;

-- ####################  20260825121100_12_vistas_y_privilegios.sql  ####################

-- ============================================================================
-- NeoTerapia · 12 · Vistas del panel y privilegios de ejecucion
-- ============================================================================

-- Todas las vistas usan security_invoker: heredan el RLS de quien consulta.

-- Resuelve pgcrypto / pg_trgm / unaccent vivan donde vivan (Supabase las pone
-- en `extensions`; un Postgres normal las deja en `public`).
set search_path = public, extensions;

create or replace view public.v_solicitudes
with (security_invoker = true) as
select
  c.id,
  c.codigo_referencia,
  c.estado,
  c.origen,
  c.fecha_solicitada,
  c.hora_solicitada,
  c.franja_solicitada,
  c.inicio_programado,
  c.fin_programado,
  c.consultorio,
  c.motivo_consulta,
  c.comentarios_paciente,
  c.es_primera_vez,
  c.nombre_declarado,
  c.telefono_declarado,
  c.whatsapp_declarado,
  c.email_declarado,
  c.canal_preferido,
  c.motivo_estado,
  c.creado_en,
  p.id            as paciente_id,
  p.nombre_completo,
  p.dpi_mascara,
  p.estado        as estado_paciente,
  f.id            as fisioterapeuta_id,
  f.nombre_completo as fisioterapeuta,
  f.color_agenda,
  coalesce(ar.areas, '[]'::jsonb) as areas,
  coalesce(al.pendientes, 0)      as alertas_pendientes
from public.citas c
join public.pacientes p on p.id = c.paciente_id
left join public.perfiles f on f.id = c.fisioterapeuta_id
left join lateral (
  select jsonb_agg(jsonb_build_object(
           'codigo', a.codigo, 'nombre', a.nombre, 'vista', a.vista,
           'svg_x', a.svg_x, 'svg_y', a.svg_y, 'intensidad', ca.intensidad, 'nota', ca.nota)
         order by a.orden) as areas
  from public.cita_areas ca
  join public.areas_cuerpo a on a.id = ca.area_id
  where ca.cita_id = c.id
) ar on true
left join lateral (
  select count(*) as pendientes
  from public.alertas al2
  where al2.cita_id = c.id and al2.estado = 'pendiente'
) al on true;

comment on view public.v_solicitudes is
  'Bandeja de citas para el panel interno. El DPI viaja siempre enmascarado.';

create or replace view public.v_pacientes_listado
with (security_invoker = true) as
select
  p.id,
  p.nombre_completo,
  p.dpi_mascara,
  p.tipo_documento,
  p.dpi_valido,
  p.telefono,
  p.whatsapp,
  p.email,
  p.canal_preferido,
  p.estado,
  p.fecha_nacimiento,
  case when p.fecha_nacimiento is not null
       then extract(year from age(p.fecha_nacimiento))::int end as edad,
  p.fisioterapeuta_id,
  f.nombre_completo as fisioterapeuta,
  p.creado_en,
  p.creado_por is null as alta_automatica,
  st.citas_totales,
  st.ultima_visita,
  st.proxima_cita,
  st.ausencias,
  coalesce(al.pendientes, 0) as alertas_pendientes
from public.pacientes p
left join public.perfiles f on f.id = p.fisioterapeuta_id
left join lateral (
  select
    count(*)                                                              as citas_totales,
    max(c.inicio_programado) filter (where c.estado = 'atendida')          as ultima_visita,
    min(c.inicio_programado) filter (where c.estado = 'confirmada'
                                       and c.inicio_programado >= now())   as proxima_cita,
    count(*) filter (where c.estado = 'ausente')                           as ausencias
  from public.citas c where c.paciente_id = p.id
) st on true
left join lateral (
  select count(*) as pendientes
  from public.alertas a where a.paciente_id = p.id and a.estado = 'pendiente'
) al on true;

create or replace view public.v_agenda
with (security_invoker = true) as
select
  c.id,
  c.codigo_referencia,
  c.inicio_programado as inicio,
  c.fin_programado    as fin,
  c.estado,
  c.consultorio,
  c.paciente_id,
  p.nombre_completo   as paciente,
  p.dpi_mascara,
  p.telefono,
  c.fisioterapeuta_id,
  f.nombre_completo   as fisioterapeuta,
  coalesce(f.color_agenda, '#0d9488') as color,
  c.motivo_consulta,
  c.es_primera_vez,
  s.id                as sesion_id,
  s.firmada_en
from public.citas c
join public.pacientes p on p.id = c.paciente_id
left join public.perfiles f on f.id = c.fisioterapeuta_id
left join public.sesiones s on s.cita_id = c.id
where c.inicio_programado is not null
  and c.estado in ('confirmada', 'atendida', 'ausente');

create or replace view public.v_duplicados
with (security_invoker = true) as
select
  d.id, d.motivo, d.puntaje, d.estado, d.creado_en,
  a.id as a_id, a.nombre_completo as a_nombre, a.dpi_mascara as a_dpi,
  a.telefono as a_telefono, a.email as a_email, a.creado_en as a_creado,
  (select count(*) from public.citas c where c.paciente_id = a.id) as a_citas,
  b.id as b_id, b.nombre_completo as b_nombre, b.dpi_mascara as b_dpi,
  b.telefono as b_telefono, b.email as b_email, b.creado_en as b_creado,
  (select count(*) from public.citas c where c.paciente_id = b.id) as b_citas
from public.posibles_duplicados d
join public.pacientes a on a.id = d.paciente_a
join public.pacientes b on b.id = d.paciente_b;

create or replace view public.v_sesiones_detalle
with (security_invoker = true) as
select
  s.*,
  c.codigo_referencia,
  c.inicio_programado,
  p.nombre_completo as paciente,
  p.dpi_mascara,
  f.nombre_completo as fisioterapeuta,
  coalesce(tr.tratamientos, '[]'::jsonb) as tratamientos,
  coalesce(ar.areas, '[]'::jsonb)        as areas,
  coalesce(tr.total, 0)                  as total_tratamientos
from public.sesiones s
join public.citas c     on c.id = s.cita_id
join public.pacientes p on p.id = s.paciente_id
join public.perfiles f  on f.id = s.fisioterapeuta_id
left join lateral (
  select
    jsonb_agg(jsonb_build_object(
      'id', st.id, 'codigo', t.codigo, 'nombre', t.nombre,
      'cantidad', st.cantidad, 'precio', st.precio_aplicado, 'notas', st.notas)) as tratamientos,
    sum(st.precio_aplicado * st.cantidad) as total
  from public.sesion_tratamientos st
  join public.tratamientos t on t.id = st.tratamiento_id
  where st.sesion_id = s.id
) tr on true
left join lateral (
  select jsonb_agg(jsonb_build_object(
    'codigo', a.codigo, 'nombre', a.nombre, 'vista', a.vista,
    'svg_x', a.svg_x, 'svg_y', a.svg_y,
    'nivel_dolor', sa.nivel_dolor, 'movilidad', sa.movilidad,
    'inflamacion', sa.inflamacion, 'observacion', sa.observacion) order by a.orden) as areas
  from public.sesion_areas sa
  join public.areas_cuerpo a on a.id = sa.area_id
  where sa.sesion_id = s.id
) ar on true;

grant select on public.v_solicitudes       to authenticated;
grant select on public.v_pacientes_listado to authenticated;
grant select on public.v_agenda            to authenticated;
grant select on public.v_duplicados        to authenticated;
grant select on public.v_sesiones_detalle  to authenticated;

-- ============================================================================
-- Privilegios de ejecucion: se cierra todo y se abre solo lo necesario
-- ============================================================================

revoke execute on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke execute on functions from public;

-- --- Superficie publica (`anon`) --------------------------------------------
grant execute on function public.solicitar_cita(jsonb)                     to anon, authenticated;
grant execute on function public.slots_disponibles(date, uuid)             to anon, authenticated;
grant execute on function public.areas_mapa()                              to anon, authenticated;
grant execute on function public.usar_enlace_accion(text, jsonb)           to anon, authenticated;
grant execute on function public.cita_publica_por_token(text)              to anon, authenticated;
grant execute on function public.validar_dpi(text)                         to anon, authenticated;

-- --- Superficie interna (`authenticated`) -----------------------------------
grant execute on function public.mi_rol()                                  to authenticated;
grant execute on function public.es_staff()                                to authenticated;
grant execute on function public.es_admin()                                to authenticated;
grant execute on function public.es_superadmin()                           to authenticated;
grant execute on function public.es_recepcion()                            to authenticated;
grant execute on function public.es_fisio()                                to authenticated;
grant execute on function public.puedo_ver_paciente(uuid)                  to authenticated;
grant execute on function public.puedo_ver_clinico(uuid)                   to authenticated;
grant execute on function public.atiendo_paciente(uuid)                    to authenticated;
grant execute on function public.config(text, jsonb)                       to authenticated;
grant execute on function public.config_int(text, int)                     to authenticated;

grant execute on function public.ver_dpi_paciente(uuid, text)              to authenticated;
grant execute on function public.buscar_pacientes(text, int)               to authenticated;
grant execute on function public.registrar_paciente(jsonb)                 to authenticated;
grant execute on function public.emitir_enlaces_cita(uuid)                 to authenticated;
grant execute on function public.confirmar_cita(uuid, timestamptz, uuid, int, text, text) to authenticated;
grant execute on function public.rechazar_cita(uuid, text)                 to authenticated;
grant execute on function public.cancelar_cita(uuid, text)                 to authenticated;
grant execute on function public.reprogramar_cita(uuid, timestamptz, uuid, text, int) to authenticated;
grant execute on function public.marcar_asistencia(uuid, boolean)          to authenticated;
grant execute on function public.firmar_sesion(uuid)                       to authenticated;
grant execute on function public.corregir_dpi(uuid, text, text, public.tipo_documento) to authenticated;
grant execute on function public.fusionar_pacientes(uuid, uuid, text)      to authenticated;
grant execute on function public.detectar_duplicados(uuid)                 to authenticated;
grant execute on function public.mapa_evolucion(uuid)                      to authenticated;
grant execute on function public.metricas_tablero()                        to authenticated;
grant execute on function public.normalizar_dpi(text)                      to authenticated;
grant execute on function public.enmascarar_dpi(text)                      to authenticated;

-- `emitir_enlace_accion`, `encolar_mensaje`, `registrar_auditoria`,
-- `hash_token`, `control_intento` y `limpiar_control_solicitudes` quedan sin
-- GRANT a proposito: solo se invocan desde dentro de otras funciones DEFINER.

-- ####################  20260825121200_13_gestion_usuarios.sql  ####################

-- ============================================================================
-- NeoTerapia · 13 · Alta y gestion de usuarios del personal desde el panel
-- ----------------------------------------------------------------------------
-- Por que una RPC y no la Admin API de Supabase:
--   `auth.admin.createUser()` exige la service_role key, que JAMAS debe estar
--   en el cliente Angular. La alternativa seria una Edge Function; mientras no
--   haya uno desplegado, estas funciones SECURITY DEFINER hacen el trabajo sin
--   exponer ninguna credencial: el unico permiso lo da el JWT del que llama.
--
-- El candado: `es_superadmin()` lee auth.uid() del JWT, que no se puede
-- falsificar sin el secreto del proyecto. Sin ese rol, la funcion aborta antes
-- de tocar nada.
-- ============================================================================

set search_path = public, extensions;

-- La migracion 18 le agrega el parametro `p_atiende`. Si esa version ya existe
-- (reinstalacion sobre una base ya migrada), hay que quitarla antes: dos
-- sobrecargas del mismo nombre volverian ambigua cualquier llamada.
drop function if exists public.crear_usuario_personal(
  text, text, text, public.rol_usuario, text, text, text, text, boolean);

create or replace function public.crear_usuario_personal(
  p_email        text,
  p_clave        text,
  p_nombre       text,
  p_rol          public.rol_usuario,
  p_telefono     text default null,
  p_colegiado    text default null,
  p_especialidad text default null,
  p_color        text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_email  text := lower(btrim(coalesce(p_email, '')));
  v_nombre text := btrim(coalesce(p_nombre, ''));
  v_id     uuid;
begin
  -- ---------- Candado ----------------------------------------------------
  if not public.es_superadmin() then
    raise exception 'Solo un superadministrador puede crear usuarios.'
      using errcode = 'insufficient_privilege';
  end if;

  -- ---------- Validaciones ------------------------------------------------
  if v_email !~ '^[^\s@]+@[^\s@]+\.[a-zA-Z]{2,}$' then
    return jsonb_build_object('ok', false, 'error', 'correo_invalido',
      'mensaje', 'El correo no tiene un formato valido.');
  end if;

  if length(coalesce(p_clave, '')) < 10 then
    return jsonb_build_object('ok', false, 'error', 'clave_corta',
      'mensaje', 'La contrasena debe tener al menos 10 caracteres.');
  end if;

  if length(v_nombre) < 5 or array_length(string_to_array(v_nombre, ' '), 1) < 2 then
    return jsonb_build_object('ok', false, 'error', 'nombre_invalido',
      'mensaje', 'Escriba nombre y apellido.');
  end if;

  if p_color is not null and p_color !~ '^#[0-9a-fA-F]{6}$' then
    return jsonb_build_object('ok', false, 'error', 'color_invalido',
      'mensaje', 'El color debe ir en formato #rrggbb.');
  end if;

  if exists (select 1 from auth.users u where lower(u.email) = v_email) then
    return jsonb_build_object('ok', false, 'error', 'correo_existente',
      'mensaje', 'Ya existe un usuario con ese correo.');
  end if;

  -- ---------- Alta en Auth ------------------------------------------------
  -- El correo queda confirmado de una vez: lo esta dando de alta un
  -- superadministrador, no es un auto-registro que haya que verificar.
  v_id := gen_random_uuid();

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new
  ) values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
    v_email, crypt(p_clave, gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('nombre_completo', v_nombre),
    now(), now(), '', '', '', ''
  );

  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(), v_id, v_id::text,
    jsonb_build_object('sub', v_id::text, 'email', v_email,
                       'email_verified', true, 'phone_verified', false),
    'email', now(), now(), now()
  );

  -- ---------- Perfil ------------------------------------------------------
  insert into public.perfiles (
    id, nombre_completo, rol, email, telefono, colegiado, especialidad, color_agenda
  ) values (
    v_id, v_nombre, p_rol, v_email,
    nullif(btrim(coalesce(p_telefono, '')), ''),
    nullif(btrim(coalesce(p_colegiado, '')), ''),
    nullif(btrim(coalesce(p_especialidad, '')), ''),
    coalesce(p_color, '#0d9488')
  );

  perform public.registrar_auditoria(
    'cambiar_rol', 'perfiles', v_id::text, null,
    format('Alta de usuario %s con rol %s', v_email, p_rol),
    null, jsonb_build_object('email', v_email, 'rol', p_rol));

  return jsonb_build_object('ok', true, 'usuario_id', v_id, 'email', v_email);
end;
$$;

comment on function public.crear_usuario_personal is
  'Alta de personal desde el panel. Solo superadmin. El paciente NUNCA pasa por aqui.';

-- ----------------------------------------------------------------------------
-- Restablecer la contrasena de otro usuario
-- ----------------------------------------------------------------------------
-- Para la propia contrasena esta `/panel/clave`, que usa auth.updateUser().
-- Esta es para cuando alguien del equipo la olvida y no tiene acceso al correo.

create or replace function public.restablecer_contrasena(
  p_usuario_id uuid,
  p_clave      text
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_email text;
begin
  if not public.es_superadmin() then
    raise exception 'Solo un superadministrador puede restablecer contrasenas.'
      using errcode = 'insufficient_privilege';
  end if;

  if length(coalesce(p_clave, '')) < 10 then
    return jsonb_build_object('ok', false, 'error', 'clave_corta',
      'mensaje', 'La contrasena debe tener al menos 10 caracteres.');
  end if;

  select u.email into v_email from auth.users u where u.id = p_usuario_id;
  if v_email is null then
    return jsonb_build_object('ok', false, 'error', 'no_existe');
  end if;

  update auth.users
     set encrypted_password = crypt(p_clave, gen_salt('bf')),
         email_confirmed_at = coalesce(email_confirmed_at, now()),
         updated_at = now()
   where id = p_usuario_id;

  perform public.registrar_auditoria(
    'cambiar_rol', 'perfiles', p_usuario_id::text, null,
    format('Restablecimiento de contrasena de %s', v_email));

  return jsonb_build_object('ok', true, 'email', v_email);
end;
$$;

-- ----------------------------------------------------------------------------
-- Privilegios: nada de esto lo puede llamar `anon`
-- ----------------------------------------------------------------------------
revoke execute on function public.crear_usuario_personal(
  text, text, text, public.rol_usuario, text, text, text, text) from public, anon;
revoke execute on function public.restablecer_contrasena(uuid, text) from public, anon;

grant execute on function public.crear_usuario_personal(
  text, text, text, public.rol_usuario, text, text, text, text) to authenticated;
grant execute on function public.restablecer_contrasena(uuid, text) to authenticated;

-- ####################  20260825121300_14_inventario_y_precios.sql  ####################

-- ============================================================================
-- NeoTerapia · 14 · Inventario, y el precio fuera del catalogo de tratamientos
-- ============================================================================

set search_path = public, extensions;

-- ----------------------------------------------------------------------------
-- 1. El tratamiento deja de tener precio fijo
-- ----------------------------------------------------------------------------
-- El costo varia por caso (paciente, convenio, duracion real), asi que el
-- catalogo ya no lo dicta. `sesion_tratamientos.precio_aplicado` se conserva y
-- se escribe a mano al aplicarlo: de ahi sigue saliendo el saldo del paciente.

drop trigger if exists tg_sesion_trat_precio on public.sesion_tratamientos;
drop function if exists public.tg_heredar_precio_tratamiento();

alter table public.tratamientos drop column if exists precio;

comment on column public.sesion_tratamientos.precio_aplicado is
  'Monto cobrado por ESTA aplicacion. Se escribe en la sesion; el catalogo ya no sugiere precio.';

-- ----------------------------------------------------------------------------
-- 2. Tipos del inventario
-- ----------------------------------------------------------------------------

do $$ begin
  create type public.categoria_articulo as enum (
    'insumo',      -- electrodos, gel, kinesiotape, algodon
    'equipo',      -- ultrasonido, TENS, camillas
    'medicamento', -- topicos, analgesicos de uso en clinica
    'limpieza',
    'papeleria',
    'otro'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.tipo_movimiento as enum (
    'entrada',   -- compra, donacion, devolucion  -> suma
    'salida',    -- consumo, uso en terapia       -> resta
    'merma',     -- vencido, danado, extraviado   -> resta
    'ajuste'     -- conteo fisico                 -> FIJA la existencia
  );
exception when duplicate_object then null; end $$;

-- ----------------------------------------------------------------------------
-- 3. Articulos
-- ----------------------------------------------------------------------------

create table if not exists public.inventario_articulos (
  id             uuid primary key default gen_random_uuid(),
  codigo         text not null unique check (length(btrim(codigo)) >= 2),
  nombre         text not null check (length(btrim(nombre)) >= 3),
  descripcion    text,
  categoria      public.categoria_articulo not null default 'insumo',
  unidad         text not null default 'unidad',   -- unidad, caja, rollo, par, ml, g
  -- `existencia` NO se edita a mano: la mantiene el trigger de movimientos,
  -- para que el saldo siempre cuadre con la bitacora.
  existencia     numeric(12,2) not null default 0,
  minimo         numeric(12,2) not null default 0 check (minimo >= 0),
  ubicacion      text,
  activo         boolean not null default true,
  creado_en      timestamptz not null default now(),
  creado_por     uuid references public.perfiles(id),
  actualizado_en timestamptz not null default now()
);

comment on table public.inventario_articulos is
  'Existencias de la clinica. La columna `existencia` la calcula el trigger de movimientos.';

create index if not exists ix_inv_articulos_activos on public.inventario_articulos (nombre)
  where activo;
create index if not exists ix_inv_articulos_categoria on public.inventario_articulos (categoria)
  where activo;
create index if not exists ix_inv_articulos_bajos on public.inventario_articulos (existencia)
  where activo and existencia <= minimo;

drop trigger if exists tg_inv_articulos_actualizado on public.inventario_articulos;
create trigger tg_inv_articulos_actualizado before update on public.inventario_articulos
  for each row execute function public.tg_actualizar_timestamp();

-- ----------------------------------------------------------------------------
-- 4. Movimientos (bitacora inmutable)
-- ----------------------------------------------------------------------------

create table if not exists public.inventario_movimientos (
  id                    uuid primary key default gen_random_uuid(),
  articulo_id           uuid not null references public.inventario_articulos(id) on delete restrict,
  tipo                  public.tipo_movimiento not null,
  cantidad              numeric(12,2) not null check (cantidad >= 0),
  existencia_anterior   numeric(12,2) not null,
  existencia_resultante numeric(12,2) not null,
  motivo                text,
  referencia            text,          -- factura, orden de compra, no. de lote
  realizado_por         uuid references public.perfiles(id),
  creado_en             timestamptz not null default now()
);

create index if not exists ix_inv_mov_articulo on public.inventario_movimientos (articulo_id, creado_en desc);
create index if not exists ix_inv_mov_fecha    on public.inventario_movimientos (creado_en desc);

-- Aplica el movimiento y recalcula la existencia. Bloquea el articulo para que
-- dos movimientos simultaneos no dejen el saldo torcido.
create or replace function public.tg_inventario_aplicar_movimiento()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actual numeric(12,2);
  v_nueva  numeric(12,2);
  v_nombre text;
begin
  select a.existencia, a.nombre into v_actual, v_nombre
  from public.inventario_articulos a
  where a.id = new.articulo_id
  for update;

  if v_actual is null then
    raise exception 'Articulo de inventario no encontrado.' using errcode = 'no_data_found';
  end if;

  v_nueva := case new.tipo
    when 'entrada' then v_actual + new.cantidad
    when 'salida'  then v_actual - new.cantidad
    when 'merma'   then v_actual - new.cantidad
    when 'ajuste'  then new.cantidad        -- conteo fisico: fija el valor
  end;

  if v_nueva < 0 then
    raise exception
      'No hay existencia suficiente de "%": hay % y se intentan sacar %. Registre un ajuste por conteo fisico si el dato esta desfasado.',
      v_nombre, v_actual, new.cantidad
      using errcode = 'check_violation';
  end if;

  new.existencia_anterior   := v_actual;
  new.existencia_resultante := v_nueva;
  new.realizado_por         := coalesce(new.realizado_por, auth.uid());

  update public.inventario_articulos
     set existencia = v_nueva, actualizado_en = now()
   where id = new.articulo_id;

  return new;
end;
$$;

drop trigger if exists tg_inv_movimiento on public.inventario_movimientos;
create trigger tg_inv_movimiento before insert on public.inventario_movimientos
  for each row execute function public.tg_inventario_aplicar_movimiento();

-- La bitacora no se corrige: se registra un movimiento nuevo.
create or replace function public.tg_inventario_inmutable()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Los movimientos de inventario no se editan ni se borran. Registre un ajuste.'
    using errcode = 'insufficient_privilege';
end;
$$;

drop trigger if exists tg_inv_mov_sin_cambios on public.inventario_movimientos;
create trigger tg_inv_mov_sin_cambios before update or delete on public.inventario_movimientos
  for each row execute function public.tg_inventario_inmutable();

-- La existencia solo cambia por movimientos, nunca por un UPDATE directo.
create or replace function public.tg_inventario_existencia_protegida()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.existencia is distinct from old.existencia
     and current_setting('neoterapia.movimiento_inventario', true) is distinct from 'on' then
    raise exception 'La existencia se cambia registrando un movimiento, no editando el articulo.'
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. Vistas
-- ----------------------------------------------------------------------------

create or replace view public.v_inventario
with (security_invoker = true) as
select
  a.*,
  (a.activo and a.existencia <= a.minimo)                        as bajo_minimo,
  (a.activo and a.existencia = 0)                                as agotado,
  ult.ultimo_movimiento,
  ult.ultimo_tipo,
  p.nombre_completo                                              as creado_por_nombre
from public.inventario_articulos a
left join public.perfiles p on p.id = a.creado_por
left join lateral (
  select m.creado_en as ultimo_movimiento, m.tipo as ultimo_tipo
  from public.inventario_movimientos m
  where m.articulo_id = a.id
  order by m.creado_en desc limit 1
) ult on true;

create or replace view public.v_inventario_movimientos
with (security_invoker = true) as
select
  m.*,
  a.codigo   as articulo_codigo,
  a.nombre   as articulo_nombre,
  a.unidad,
  p.nombre_completo as responsable
from public.inventario_movimientos m
join public.inventario_articulos a on a.id = m.articulo_id
left join public.perfiles p on p.id = m.realizado_por;

-- ----------------------------------------------------------------------------
-- 6. Seguridad
-- ----------------------------------------------------------------------------

alter table public.inventario_articulos   enable row level security;
alter table public.inventario_movimientos enable row level security;

grant select                         on public.inventario_articulos   to authenticated;
grant insert, update, delete         on public.inventario_articulos   to authenticated;
grant select, insert                 on public.inventario_movimientos to authenticated;
grant select on public.v_inventario             to authenticated;
grant select on public.v_inventario_movimientos to authenticated;

-- Todo el personal consulta las existencias...
drop policy if exists inv_articulos_select on public.inventario_articulos;
create policy inv_articulos_select on public.inventario_articulos
  for select to authenticated using (public.es_staff());

-- ...pero solo administracion las administra.
drop policy if exists inv_articulos_write on public.inventario_articulos;
create policy inv_articulos_write on public.inventario_articulos
  for all to authenticated using (public.es_admin()) with check (public.es_admin());

drop policy if exists inv_mov_select on public.inventario_movimientos;
create policy inv_mov_select on public.inventario_movimientos
  for select to authenticated using (public.es_staff());

drop policy if exists inv_mov_insert on public.inventario_movimientos;
create policy inv_mov_insert on public.inventario_movimientos
  for insert to authenticated with check (public.es_admin());

-- El trigger que protege `existencia` se instala despues de las politicas para
-- que la funcion de movimientos pueda seguir escribiendola.
create or replace function public.registrar_movimiento_inventario(
  p_articulo_id uuid,
  p_tipo        public.tipo_movimiento,
  p_cantidad    numeric,
  p_motivo      text default null,
  p_referencia  text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id  uuid;
  v_res numeric(12,2);
begin
  if not public.es_admin() then
    raise exception 'Su rol no permite mover el inventario.' using errcode = 'insufficient_privilege';
  end if;
  if p_cantidad is null or p_cantidad < 0 then
    return jsonb_build_object('ok', false, 'error', 'cantidad_invalida',
      'mensaje', 'La cantidad debe ser un numero positivo.');
  end if;
  if p_tipo <> 'ajuste' and p_cantidad = 0 then
    return jsonb_build_object('ok', false, 'error', 'cantidad_invalida',
      'mensaje', 'La cantidad debe ser mayor que cero.');
  end if;

  perform set_config('neoterapia.movimiento_inventario', 'on', true);

  insert into public.inventario_movimientos
    (articulo_id, tipo, cantidad, motivo, referencia, realizado_por)
  values
    (p_articulo_id, p_tipo, p_cantidad,
     nullif(btrim(coalesce(p_motivo, '')), ''),
     nullif(btrim(coalesce(p_referencia, '')), ''),
     auth.uid())
  returning id, existencia_resultante into v_id, v_res;

  perform set_config('neoterapia.movimiento_inventario', 'off', true);

  return jsonb_build_object('ok', true, 'movimiento_id', v_id, 'existencia', v_res);
exception
  when check_violation then
    return jsonb_build_object('ok', false, 'error', 'sin_existencia', 'mensaje', sqlerrm);
end;
$$;

drop trigger if exists tg_inv_existencia_protegida on public.inventario_articulos;
create trigger tg_inv_existencia_protegida before update on public.inventario_articulos
  for each row execute function public.tg_inventario_existencia_protegida();

revoke execute on function public.registrar_movimiento_inventario(
  uuid, public.tipo_movimiento, numeric, text, text) from public, anon;
grant execute on function public.registrar_movimiento_inventario(
  uuid, public.tipo_movimiento, numeric, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 7. Resumen para el panel
-- ----------------------------------------------------------------------------

create or replace function public.resumen_inventario()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'articulos',    (select count(*) from public.inventario_articulos where activo),
    'bajo_minimo',  (select count(*) from public.inventario_articulos
                      where activo and existencia <= minimo),
    'agotados',     (select count(*) from public.inventario_articulos
                      where activo and existencia = 0),
    'movimientos_semana', (select count(*) from public.inventario_movimientos
                            where creado_en >= now() - interval '7 days')
  )
  where public.es_staff()
$$;

revoke execute on function public.resumen_inventario() from public, anon;
grant execute on function public.resumen_inventario() to authenticated;

-- ----------------------------------------------------------------------------
-- 8. El tablero y el menu lateral necesitan el contador de bajo minimo
-- ----------------------------------------------------------------------------

create or replace function public.metricas_tablero()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'solicitudes_pendientes', (select count(*) from public.citas where estado = 'solicitada'),
    'citas_hoy',              (select count(*) from public.citas
                                where estado = 'confirmada'
                                  and inicio_programado::date = current_date),
    'citas_semana',           (select count(*) from public.citas
                                where estado in ('confirmada', 'atendida')
                                  and inicio_programado >= date_trunc('week', now())
                                  and inicio_programado <  date_trunc('week', now()) + interval '7 days'),
    'alertas_pendientes',     (select count(*) from public.alertas where estado = 'pendiente'),
    'duplicados_pendientes',  (select count(*) from public.posibles_duplicados where estado = 'pendiente'),
    'pacientes_activos',      (select count(*) from public.pacientes where estado = 'activo'),
    'sesiones_sin_firmar',    (select count(*) from public.sesiones where firmada_en is null),
    'mensajes_en_cola',       (select count(*) from public.mensajes where estado = 'pendiente'),
    'inventario_bajo',        (select count(*) from public.inventario_articulos
                                where activo and existencia <= minimo)
  )
  where public.es_staff()
$$;

grant execute on function public.metricas_tablero() to authenticated;

-- ####################  20260825121400_15_fisioterapeuta_opcional.sql  ####################

-- ============================================================================
-- NeoTerapia · 15 · El fisioterapeuta deja de ser obligatorio al agendar
-- ----------------------------------------------------------------------------
-- Se puede confirmar una cita sin saber todavia quien la va a atender: la
-- clinica lo asigna despues, o el mismo fisioterapeuta queda registrado cuando
-- marca la asistencia.
--
-- Lo que SI sigue exigiendo fisioterapeuta es la nota clinica: un expediente
-- sin autor no sirve como registro. `sesiones.fisioterapeuta_id` se queda NOT
-- NULL a proposito.
-- ============================================================================

set search_path = public, extensions;

-- ----------------------------------------------------------------------------
-- Confirmar sin asignar
-- ----------------------------------------------------------------------------

drop function if exists public.confirmar_cita(uuid, timestamptz, uuid, int, text, text);

create or replace function public.confirmar_cita(
  p_cita_id           uuid,
  p_inicio            timestamptz,
  p_fisioterapeuta_id uuid default null,     -- <- ahora opcional
  p_duracion_min      int  default null,
  p_consultorio       text default null,
  p_nota              text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dur     int := coalesce(p_duracion_min, public.config_int('duracion_cita_min', 45));
  v_cita    public.citas%rowtype;
  v_enlaces jsonb;
begin
  if public.mi_rol() not in ('superadmin', 'admin', 'recepcion') then
    raise exception 'Su rol no permite confirmar citas.' using errcode = 'insufficient_privilege';
  end if;

  select * into v_cita from public.citas where id = p_cita_id for update;
  if not found then
    raise exception 'Cita no encontrada.' using errcode = 'no_data_found';
  end if;
  if v_cita.estado not in ('solicitada', 'confirmada') then
    return jsonb_build_object('ok', false, 'error', 'estado_no_permite', 'estado', v_cita.estado);
  end if;

  update public.citas
     set estado            = 'confirmada',
         inicio_programado = p_inicio,
         fin_programado    = p_inicio + make_interval(mins => v_dur),
         fisioterapeuta_id = p_fisioterapeuta_id,
         consultorio       = coalesce(p_consultorio, consultorio),
         notas_internas    = coalesce(p_nota, notas_internas),
         motivo_estado     = null,
         resuelta_por      = auth.uid(),
         resuelta_en       = now()
   where id = p_cita_id;

  -- Solo se adopta como fisioterapeuta principal si de verdad se asigno uno.
  if p_fisioterapeuta_id is not null then
    update public.pacientes
       set fisioterapeuta_id = p_fisioterapeuta_id
     where id = v_cita.paciente_id and fisioterapeuta_id is null;
  end if;

  v_enlaces := public.emitir_enlaces_cita(p_cita_id);
  perform public.encolar_mensaje(p_cita_id, 'confirmacion', jsonb_build_object(
    'enlaces', format(E'Confirmar asistencia: %s\nCancelar: %s',
                      v_enlaces ->> 'confirmar', v_enlaces ->> 'cancelar')
  ));

  return jsonb_build_object(
    'ok', true, 'estado', 'confirmada', 'enlaces', v_enlaces,
    'sin_fisioterapeuta', p_fisioterapeuta_id is null);
exception
  when exclusion_violation then
    return jsonb_build_object('ok', false, 'error', 'traslape',
      'mensaje', 'Ese fisioterapeuta ya tiene una cita confirmada en ese horario.');
end;
$$;

comment on function public.confirmar_cita is
  'Confirma y agenda. El fisioterapeuta es opcional: se puede asignar despues con asignar_fisioterapeuta().';

-- ----------------------------------------------------------------------------
-- Asignar (o cambiar) el fisioterapeuta de una cita ya confirmada
-- ----------------------------------------------------------------------------
-- Deliberadamente NO reenvia el mensaje de confirmacion ni reemite enlaces:
-- para el paciente no cambia nada, la cita sigue a la misma hora.

create or replace function public.asignar_fisioterapeuta(
  p_cita_id           uuid,
  p_fisioterapeuta_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cita public.citas%rowtype;
  v_rol  public.rol_usuario;
begin
  if public.mi_rol() not in ('superadmin', 'admin', 'recepcion') then
    raise exception 'Su rol no permite asignar fisioterapeutas.' using errcode = 'insufficient_privilege';
  end if;

  select * into v_cita from public.citas where id = p_cita_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'no_existe');
  end if;
  if v_cita.estado not in ('solicitada', 'confirmada') then
    return jsonb_build_object('ok', false, 'error', 'estado_no_permite', 'estado', v_cita.estado);
  end if;

  if p_fisioterapeuta_id is not null then
    select rol into v_rol from public.perfiles where id = p_fisioterapeuta_id and activo;
    if v_rol is distinct from 'fisioterapeuta' then
      return jsonb_build_object('ok', false, 'error', 'no_es_fisioterapeuta',
        'mensaje', 'El usuario seleccionado no es un fisioterapeuta activo.');
    end if;
  end if;

  update public.citas
     set fisioterapeuta_id = p_fisioterapeuta_id
   where id = p_cita_id;

  if p_fisioterapeuta_id is not null then
    update public.pacientes
       set fisioterapeuta_id = p_fisioterapeuta_id
     where id = v_cita.paciente_id and fisioterapeuta_id is null;
  end if;

  return jsonb_build_object('ok', true, 'fisioterapeuta_id', p_fisioterapeuta_id);
exception
  when exclusion_violation then
    return jsonb_build_object('ok', false, 'error', 'traslape',
      'mensaje', 'Ese fisioterapeuta ya tiene una cita confirmada en ese horario.');
end;
$$;

-- ----------------------------------------------------------------------------
-- Asistencia: el fisioterapeuta que atiende se registra solo
-- ----------------------------------------------------------------------------

create or replace function public.marcar_asistencia(p_cita_id uuid, p_asistio boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cita   public.citas%rowtype;
  v_sesion uuid;
  v_rol    public.rol_usuario := public.mi_rol();
  v_fisio  uuid;
begin
  select * into v_cita from public.citas where id = p_cita_id;
  if not found then
    raise exception 'Cita no encontrada.' using errcode = 'no_data_found';
  end if;

  if v_rol not in ('superadmin', 'admin', 'recepcion')
     and not (v_rol = 'fisioterapeuta' and (
       v_cita.fisioterapeuta_id = auth.uid() or v_cita.fisioterapeuta_id is null)) then
    raise exception 'Su rol no permite registrar asistencia en esta cita.'
      using errcode = 'insufficient_privilege';
  end if;

  if not p_asistio then
    update public.citas
       set estado = 'ausente', resuelta_por = auth.uid(), resuelta_en = now()
     where id = p_cita_id;
    return jsonb_build_object('ok', true, 'estado', 'ausente');
  end if;

  -- ¿Quien firma la nota? La cita si la trae; si no, quien marca la asistencia
  -- siempre que sea fisioterapeuta. Una nota clinica sin autor no sirve.
  v_fisio := v_cita.fisioterapeuta_id;
  if v_fisio is null and v_rol = 'fisioterapeuta' then
    v_fisio := auth.uid();
    update public.citas set fisioterapeuta_id = v_fisio where id = p_cita_id;
  end if;

  if v_fisio is null then
    return jsonb_build_object('ok', false, 'error', 'falta_fisioterapeuta',
      'mensaje', 'Asigne un fisioterapeuta a la cita antes de marcarla como atendida: la nota clinica necesita autor.');
  end if;

  update public.citas
     set estado = 'atendida', asistio_en = now(), resuelta_por = auth.uid(), resuelta_en = now()
   where id = p_cita_id;

  -- `tg_pacientes_control_edicion` impide que un fisioterapeuta toque la
  -- asignacion del paciente. Aqui no la esta editando a mano: la esta ganando
  -- por atender la cita, asi que se marca como operacion interna.
  perform set_config('neoterapia.operacion_interna', 'on', true);
  update public.pacientes
     set fisioterapeuta_id = v_fisio
   where id = v_cita.paciente_id and fisioterapeuta_id is null;
  perform set_config('neoterapia.operacion_interna', 'off', true);

  insert into public.sesiones (cita_id, paciente_id, fisioterapeuta_id, inicio)
  values (p_cita_id, v_cita.paciente_id, v_fisio, coalesce(v_cita.inicio_programado, now()))
  on conflict (cita_id) do nothing
  returning id into v_sesion;

  if v_sesion is null then
    select id into v_sesion from public.sesiones where cita_id = p_cita_id;
  end if;

  -- Se precargan las areas que el paciente declaro, para que el fisioterapeuta
  -- parta del mapa corporal que el mismo marco.
  insert into public.sesion_areas (sesion_id, area_id, nivel_dolor)
  select v_sesion, ca.area_id, coalesce(ca.intensidad, 0)
  from public.cita_areas ca where ca.cita_id = p_cita_id
  on conflict (sesion_id, area_id) do nothing;

  return jsonb_build_object('ok', true, 'estado', 'atendida', 'sesion_id', v_sesion);
end;
$$;

-- ----------------------------------------------------------------------------
-- Privilegios
-- ----------------------------------------------------------------------------

revoke execute on function public.asignar_fisioterapeuta(uuid, uuid) from public, anon;
grant execute on function public.asignar_fisioterapeuta(uuid, uuid) to authenticated;
grant execute on function public.confirmar_cita(uuid, timestamptz, uuid, int, text, text) to authenticated;
grant execute on function public.marcar_asistencia(uuid, boolean) to authenticated;

-- ####################  20260825121500_16_mapa_por_sesion.sql  ####################

-- ============================================================================
-- NeoTerapia · 16 · Historial del mapa corporal, momento por momento
-- ----------------------------------------------------------------------------
-- `sesion_areas` YA guardaba el mapa por sesion. Lo que faltaba era poder
-- recorrerlo: `mapa_evolucion()` devolvia puntos sueltos y la ficha terminaba
-- pintando un solo mapa "actual" mezclando todo.
--
-- Esta funcion devuelve un momento por fila (la solicitud del paciente y cada
-- sesion), con su mapa completo, para poder navegar el historial y comparar.
-- ============================================================================

set search_path = public, extensions;

create or replace function public.historial_mapa_corporal(p_paciente_id uuid)
returns table (
  momento_id       uuid,
  momento_tipo     text,          -- 'solicitud' | 'sesion'
  fecha            timestamptz,
  etiqueta         text,
  firmada          boolean,
  responsable      text,
  dolor_promedio   numeric(4,1),
  dolor_maximo     int,
  areas            jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  -- Lo que el paciente marco al pedir la cita
  select
    c.id,
    'solicitud'::text,
    c.creado_en,
    'Solicitud ' || c.codigo_referencia,
    null::boolean,
    null::text,
    round(avg(ca.intensidad)::numeric, 1),
    max(ca.intensidad),
    jsonb_agg(jsonb_build_object(
      'codigo', a.codigo, 'nombre', a.nombre, 'vista', a.vista,
      'svg_x', a.svg_x, 'svg_y', a.svg_y,
      'nivel_dolor', ca.intensidad, 'observacion', ca.nota
    ) order by a.orden)
  from public.cita_areas ca
  join public.citas c        on c.id = ca.cita_id
  join public.areas_cuerpo a on a.id = ca.area_id
  where c.paciente_id = p_paciente_id
    and ca.intensidad is not null
    and public.puedo_ver_paciente(p_paciente_id)
  group by c.id, c.creado_en, c.codigo_referencia

  union all

  -- Lo que el fisioterapeuta registro en cada sesion
  select
    s.id,
    'sesion'::text,
    s.inicio,
    'Sesión',
    s.firmada_en is not null,
    p.nombre_completo,
    round(avg(sa.nivel_dolor)::numeric, 1),
    max(sa.nivel_dolor),
    jsonb_agg(jsonb_build_object(
      'codigo', a.codigo, 'nombre', a.nombre, 'vista', a.vista,
      'svg_x', a.svg_x, 'svg_y', a.svg_y,
      'nivel_dolor', sa.nivel_dolor, 'movilidad', sa.movilidad,
      'inflamacion', sa.inflamacion, 'observacion', sa.observacion
    ) order by a.orden)
  from public.sesion_areas sa
  join public.sesiones s     on s.id = sa.sesion_id
  join public.areas_cuerpo a on a.id = sa.area_id
  left join public.perfiles p on p.id = s.fisioterapeuta_id
  where s.paciente_id = p_paciente_id
    and public.puedo_ver_clinico(p_paciente_id)
  group by s.id, s.inicio, s.firmada_en, p.nombre_completo

  order by 3
$$;

comment on function public.historial_mapa_corporal(uuid) is
  'Un mapa corporal por momento (solicitud o sesion), para recorrer el historial en vez de ver solo el ultimo estado.';

revoke execute on function public.historial_mapa_corporal(uuid) from public, anon;
grant execute on function public.historial_mapa_corporal(uuid) to authenticated;

-- ####################  20260825121600_17_indicadores.sql  ####################

-- ============================================================================
-- NeoTerapia · 17 · Indicadores (KPIs) de operacion y cobro
-- ----------------------------------------------------------------------------
-- Todo se cuenta por fecha LOCAL de la clinica, no UTC: una cita de las 7 p.m.
-- del lunes en Guatemala es UTC del martes, y contarla en el dia equivocado
-- desalinearia el corte diario con lo que ve la recepcion.
--
-- "Cobrada" = la cita atendida tiene al menos un pago aplicado ligado a ella
-- (`pagos.cita_id`). Por eso importa ligar el pago a la cita al registrarlo:
-- un pago suelto suma a los ingresos pero no marca la visita como cobrada.
-- ============================================================================

set search_path = public, extensions;

create or replace function public.tz_clinica()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.config('zona_horaria') #>> '{}', 'America/Guatemala')
$$;

-- ----------------------------------------------------------------------------
-- Resumen del periodo
-- ----------------------------------------------------------------------------

create or replace function public.kpis_resumen(p_desde date, p_hasta date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz   text := public.tz_clinica();
  v_c    record;
  v_p    record;
  v_cob  int;
begin
  if not (public.es_admin() or public.es_recepcion()) then
    raise exception 'Su rol no permite ver los indicadores.' using errcode = 'insufficient_privilege';
  end if;

  select
    count(*)                                                       as totales,
    count(*) filter (where estado = 'atendida')                    as atendidas,
    count(*) filter (where estado = 'cancelada')                   as canceladas,
    count(*) filter (where estado = 'rechazada')                   as rechazadas,
    count(*) filter (where estado = 'ausente')                     as ausentes,
    count(*) filter (where estado = 'confirmada')                  as confirmadas,
    count(*) filter (where estado = 'solicitada')                  as solicitadas,
    count(distinct paciente_id) filter (where estado = 'atendida') as pacientes_atendidos,
    count(distinct paciente_id) filter (where estado = 'cancelada') as pacientes_cancelados
  into v_c
  from public.citas c
  where coalesce((c.inicio_programado at time zone v_tz)::date, c.fecha_solicitada)
        between p_desde and p_hasta;

  select
    coalesce(sum(monto), 0)                                    as ingresos,
    count(*)                                                   as pagos,
    count(distinct paciente_id)                                as pacientes_cobrados,
    coalesce(jsonb_object_agg(metodo, total), '{}'::jsonb)     as por_metodo
  into v_p
  from (
    select pg.metodo, pg.monto, pg.paciente_id,
           sum(pg.monto) over (partition by pg.metodo) as total
    from public.pagos pg
    where pg.estado = 'pagado'
      and (pg.fecha at time zone v_tz)::date between p_desde and p_hasta
  ) x;

  -- Citas atendidas del periodo que tienen al menos un pago ligado
  select count(*) into v_cob
  from public.citas c
  where c.estado = 'atendida'
    and coalesce((c.inicio_programado at time zone v_tz)::date, c.fecha_solicitada)
        between p_desde and p_hasta
    and exists (
      select 1 from public.pagos pg
      where pg.cita_id = c.id and pg.estado = 'pagado');

  return jsonb_build_object(
    'desde', p_desde,
    'hasta', p_hasta,
    'citas_totales',        v_c.totales,
    'atendidas',            v_c.atendidas,
    'canceladas',           v_c.canceladas,
    'rechazadas',           v_c.rechazadas,
    'ausentes',             v_c.ausentes,
    'confirmadas',          v_c.confirmadas,
    'solicitadas',          v_c.solicitadas,
    'pacientes_atendidos',  v_c.pacientes_atendidos,
    'pacientes_cancelados', v_c.pacientes_cancelados,
    'pacientes_nuevos',     (select count(*) from public.pacientes p
                              where (p.creado_en at time zone v_tz)::date between p_desde and p_hasta
                                and p.estado <> 'fusionado'),
    'atendidas_cobradas',   v_cob,
    'atendidas_sin_cobrar', greatest(v_c.atendidas - v_cob, 0),
    'ingresos',             coalesce(v_p.ingresos, 0),
    'pagos_registrados',    coalesce(v_p.pagos, 0),
    'pacientes_cobrados',   coalesce(v_p.pacientes_cobrados, 0),
    'ticket_promedio',      case when coalesce(v_p.pagos, 0) > 0
                                 then round(v_p.ingresos / v_p.pagos, 2) else 0 end,
    'ingresos_por_metodo',  coalesce(v_p.por_metodo, '{}'::jsonb),
    'tasa_asistencia',      case when (v_c.atendidas + v_c.ausentes) > 0
                                 then round(100.0 * v_c.atendidas / (v_c.atendidas + v_c.ausentes), 1)
                                 else null end,
    'tasa_cobro',           case when v_c.atendidas > 0
                                 then round(100.0 * v_cob / v_c.atendidas, 1)
                                 else null end
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- Serie temporal
-- ----------------------------------------------------------------------------
-- Devuelve TODOS los periodos del rango, incluso los vacios: una grafica con
-- huecos miente sobre la cadencia del negocio.

create or replace function public.kpis_serie(
  p_desde         date,
  p_hasta         date,
  p_granularidad  text default 'day'    -- day | week | month
) returns table (
  periodo     date,
  ingresos    numeric(12,2),
  pagos       int,
  atendidas   int,
  canceladas  int,
  ausentes    int
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tz   text := public.tz_clinica();
  v_gran text := lower(coalesce(p_granularidad, 'day'));
  v_step interval;
begin
  if not (public.es_admin() or public.es_recepcion()) then
    raise exception 'Su rol no permite ver los indicadores.' using errcode = 'insufficient_privilege';
  end if;

  if v_gran not in ('day', 'week', 'month') then v_gran := 'day'; end if;
  v_step := case v_gran when 'day' then interval '1 day'
                        when 'week' then interval '1 week'
                        else interval '1 month' end;

  return query
  with periodos as (
    select generate_series(
      date_trunc(v_gran, p_desde::timestamp),
      date_trunc(v_gran, p_hasta::timestamp),
      v_step
    )::date as p
  ),
  dinero as (
    select date_trunc(v_gran, (pg.fecha at time zone v_tz))::date as p,
           sum(pg.monto) as monto, count(*) as n
    from public.pagos pg
    where pg.estado = 'pagado'
      and (pg.fecha at time zone v_tz)::date between p_desde and p_hasta
    group by 1
  ),
  visitas as (
    select date_trunc(v_gran,
             coalesce((c.inicio_programado at time zone v_tz),
                      c.fecha_solicitada::timestamp))::date as p,
           count(*) filter (where c.estado = 'atendida')  as atendidas,
           count(*) filter (where c.estado = 'cancelada') as canceladas,
           count(*) filter (where c.estado = 'ausente')   as ausentes
    from public.citas c
    where coalesce((c.inicio_programado at time zone v_tz)::date, c.fecha_solicitada)
          between p_desde and p_hasta
    group by 1
  )
  select
    pe.p,
    coalesce(d.monto, 0)::numeric(12,2),
    coalesce(d.n, 0)::int,
    coalesce(v.atendidas, 0)::int,
    coalesce(v.canceladas, 0)::int,
    coalesce(v.ausentes, 0)::int
  from periodos pe
  left join dinero  d on d.p = pe.p
  left join visitas v on v.p = pe.p
  order by pe.p;
end;
$$;

-- ----------------------------------------------------------------------------
-- Las visitas que quedaron sin cobrar
-- ----------------------------------------------------------------------------
-- No basta con el numero: para que el indicador sirva hay que poder ir a
-- resolverlo. Esta lista es accionable desde el panel.

create or replace function public.kpis_sin_cobrar(p_desde date, p_hasta date)
returns table (
  cita_id           uuid,
  codigo_referencia text,
  fecha             timestamptz,
  paciente_id       uuid,
  paciente          text,
  dpi_mascara       text,
  fisioterapeuta    text,
  cargos            numeric(12,2)
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_tz text := public.tz_clinica();
begin
  if not (public.es_admin() or public.es_recepcion()) then
    raise exception 'Su rol no permite ver los indicadores.' using errcode = 'insufficient_privilege';
  end if;

  return query
  select
    c.id, c.codigo_referencia, c.inicio_programado,
    p.id, p.nombre_completo, p.dpi_mascara, f.nombre_completo,
    coalesce((
      select sum(st.precio_aplicado * st.cantidad)
      from public.sesion_tratamientos st
      join public.sesiones s on s.id = st.sesion_id
      where s.cita_id = c.id
    ), 0)::numeric(12,2)
  from public.citas c
  join public.pacientes p on p.id = c.paciente_id
  left join public.perfiles f on f.id = c.fisioterapeuta_id
  where c.estado = 'atendida'
    and coalesce((c.inicio_programado at time zone v_tz)::date, c.fecha_solicitada)
        between p_desde and p_hasta
    and not exists (
      select 1 from public.pagos pg
      where pg.cita_id = c.id and pg.estado = 'pagado')
  order by c.inicio_programado desc nulls last
  limit 200;
end;
$$;

-- ----------------------------------------------------------------------------
-- Privilegios
-- ----------------------------------------------------------------------------

revoke execute on function public.kpis_resumen(date, date)          from public, anon;
revoke execute on function public.kpis_serie(date, date, text)      from public, anon;
revoke execute on function public.kpis_sin_cobrar(date, date)       from public, anon;
revoke execute on function public.tz_clinica()                      from public, anon;

grant execute on function public.kpis_resumen(date, date)     to authenticated;
grant execute on function public.kpis_serie(date, date, text) to authenticated;
grant execute on function public.kpis_sin_cobrar(date, date)  to authenticated;
grant execute on function public.tz_clinica()                 to authenticated;

-- ####################  20260825121700_18_quien_atiende.sql  ####################

-- ============================================================================
-- NeoTerapia · 18 · Quien atiende deja de ser solo el rol "fisioterapeuta"
-- ----------------------------------------------------------------------------
-- En una clinica pequena el dueno tambien pasa consulta. Hasta ahora el sistema
-- confundia dos cosas distintas:
--
--   ROL      = que puede administrar (usuarios, precios, configuracion)
--   ATIENDE  = si pasa consulta y por lo tanto puede aparecer en la agenda,
--              quedar asignado a una cita y firmar la nota clinica
--
-- Se separan con la columna `perfiles.atiende`. Un fisioterapeuta siempre
-- atiende (es lo que significa el rol). Un superadministrador o un
-- administrador atiende si esta marcado. Recepcion nunca: no ve lo clinico, y
-- asignarle una cita crearia una nota sin autor legitimo.
--
-- Solo el superadministrador puede activar o quitar esa marca; si no, cualquiera
-- podria auto-asignarse citas editando su propio perfil.
-- ============================================================================

set search_path = public, extensions;

-- ----------------------------------------------------------------------------
-- La columna
-- ----------------------------------------------------------------------------

alter table public.perfiles
  add column if not exists atiende boolean not null default false;

comment on column public.perfiles.atiende is
  'Pasa consulta: aparece en la agenda, se le asignan citas y firma notas. El rol fisioterapeuta lo tiene siempre; recepcion nunca.';

-- ----------------------------------------------------------------------------
-- Coherencia: el rol manda sobre los extremos
-- ----------------------------------------------------------------------------

create or replace function public.tg_perfiles_atiende()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.rol = 'fisioterapeuta' then
    new.atiende := true;            -- es la definicion del rol
  elsif new.rol = 'recepcion' then
    new.atiende := false;           -- recepcion no ve lo clinico
  end if;
  new.atiende := coalesce(new.atiende, false);
  return new;
end;
$$;

drop trigger if exists tg_perfiles_atiende on public.perfiles;
create trigger tg_perfiles_atiende before insert or update on public.perfiles
  for each row execute function public.tg_perfiles_atiende();

-- El control de rol tambien vigila `atiende`: cambiarla es dar o quitar
-- capacidad clinica, no es una preferencia personal.
create or replace function public.tg_perfiles_control_rol()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (new.rol is distinct from old.rol or new.activo is distinct from old.activo)
     and not public.es_superadmin()
  then
    raise exception 'Solo un superadministrador puede cambiar el rol o el estado de un usuario.'
      using errcode = 'insufficient_privilege';
  end if;

  -- `mi_rol() is not null` deja pasar el mantenimiento hecho directamente en la
  -- base (migraciones, SQL Editor): ahi no hay JWT que consultar.
  if new.atiende is distinct from old.atiende
     and public.mi_rol() is not null
     and not public.es_superadmin()
  then
    raise exception 'Solo un superadministrador define quien atiende pacientes.'
      using errcode = 'insufficient_privilege';
  end if;

  if new.rol is distinct from old.rol then
    perform public.registrar_auditoria(
      'cambiar_rol', 'perfiles', new.id::text, null,
      format('Rol %s -> %s', old.rol, new.rol),
      jsonb_build_object('rol', old.rol), jsonb_build_object('rol', new.rol));
  end if;

  if new.atiende is distinct from old.atiende then
    perform public.registrar_auditoria(
      'cambiar_rol', 'perfiles', new.id::text, null,
      case when new.atiende then 'Ahora atiende pacientes'
           else 'Deja de atender pacientes' end,
      jsonb_build_object('atiende', old.atiende),
      jsonb_build_object('atiende', new.atiende));
  end if;

  return new;
end;
$$;

-- Estado inicial: los fisioterapeutas y el superadministrador que instala el
-- sistema. Si el superadministrador no pasa consulta, lo desmarca desde
-- Administracion y deja de aparecer en la agenda.
update public.perfiles
   set atiende = true
 where rol in ('fisioterapeuta', 'superadmin')
   and atiende is distinct from true;

update public.perfiles
   set atiende = false
 where rol = 'recepcion'
   and atiende is distinct from false;

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

-- Ojo: `es_fisio()` NO cambia. Sigue significando "tiene el rol
-- fisioterapeuta", y en las politicas RLS sirve para RESTRINGIR (ve solo sus
-- pacientes). Ampliarla le quitaria visibilidad al administrador.

create or replace function public.puede_atender(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.perfiles p
    where p.id = p_id and p.activo and p.atiende
  )
$$;

comment on function public.puede_atender is
  'Ese usuario pasa consulta: se le puede asignar una cita y puede firmar notas.';

create or replace function public.atiendo()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.puede_atender(auth.uid())
$$;

-- ----------------------------------------------------------------------------
-- Confirmar: valida que quien se asigna realmente atienda
-- ----------------------------------------------------------------------------

drop function if exists public.confirmar_cita(uuid, timestamptz, uuid, int, text, text);

create or replace function public.confirmar_cita(
  p_cita_id           uuid,
  p_inicio            timestamptz,
  p_fisioterapeuta_id uuid default null,
  p_duracion_min      int  default null,
  p_consultorio       text default null,
  p_nota              text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dur     int := coalesce(p_duracion_min, public.config_int('duracion_cita_min', 45));
  v_cita    public.citas%rowtype;
  v_enlaces jsonb;
begin
  if public.mi_rol() not in ('superadmin', 'admin', 'recepcion') then
    raise exception 'Su rol no permite confirmar citas.' using errcode = 'insufficient_privilege';
  end if;

  if p_fisioterapeuta_id is not null and not public.puede_atender(p_fisioterapeuta_id) then
    return jsonb_build_object('ok', false, 'error', 'no_atiende',
      'mensaje', 'El usuario seleccionado no esta marcado como que atiende pacientes.');
  end if;

  select * into v_cita from public.citas where id = p_cita_id for update;
  if not found then
    raise exception 'Cita no encontrada.' using errcode = 'no_data_found';
  end if;
  if v_cita.estado not in ('solicitada', 'confirmada') then
    return jsonb_build_object('ok', false, 'error', 'estado_no_permite', 'estado', v_cita.estado);
  end if;

  update public.citas
     set estado            = 'confirmada',
         inicio_programado = p_inicio,
         fin_programado    = p_inicio + make_interval(mins => v_dur),
         fisioterapeuta_id = p_fisioterapeuta_id,
         consultorio       = coalesce(p_consultorio, consultorio),
         notas_internas    = coalesce(p_nota, notas_internas),
         motivo_estado     = null,
         resuelta_por      = auth.uid(),
         resuelta_en       = now()
   where id = p_cita_id;

  if p_fisioterapeuta_id is not null then
    update public.pacientes
       set fisioterapeuta_id = p_fisioterapeuta_id
     where id = v_cita.paciente_id and fisioterapeuta_id is null;
  end if;

  v_enlaces := public.emitir_enlaces_cita(p_cita_id);
  perform public.encolar_mensaje(p_cita_id, 'confirmacion', jsonb_build_object(
    'enlaces', format(E'Confirmar asistencia: %s\nCancelar: %s',
                      v_enlaces ->> 'confirmar', v_enlaces ->> 'cancelar')
  ));

  return jsonb_build_object(
    'ok', true, 'estado', 'confirmada', 'enlaces', v_enlaces,
    'sin_fisioterapeuta', p_fisioterapeuta_id is null);
exception
  when exclusion_violation then
    return jsonb_build_object('ok', false, 'error', 'traslape',
      'mensaje', 'Esa persona ya tiene una cita confirmada en ese horario.');
end;
$$;

comment on function public.confirmar_cita is
  'Confirma y agenda. Quien atiende es opcional y puede ser cualquier perfil con atiende = true.';

-- ----------------------------------------------------------------------------
-- Asignar: ya no exige el rol, exige la marca
-- ----------------------------------------------------------------------------

create or replace function public.asignar_fisioterapeuta(
  p_cita_id           uuid,
  p_fisioterapeuta_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cita public.citas%rowtype;
begin
  if public.mi_rol() not in ('superadmin', 'admin', 'recepcion') then
    raise exception 'Su rol no permite asignar quien atiende.' using errcode = 'insufficient_privilege';
  end if;

  select * into v_cita from public.citas where id = p_cita_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'no_existe');
  end if;
  if v_cita.estado not in ('solicitada', 'confirmada') then
    return jsonb_build_object('ok', false, 'error', 'estado_no_permite', 'estado', v_cita.estado);
  end if;

  if p_fisioterapeuta_id is not null and not public.puede_atender(p_fisioterapeuta_id) then
    return jsonb_build_object('ok', false, 'error', 'no_atiende',
      'mensaje', 'El usuario seleccionado no esta marcado como que atiende pacientes.');
  end if;

  update public.citas
     set fisioterapeuta_id = p_fisioterapeuta_id
   where id = p_cita_id;

  if p_fisioterapeuta_id is not null then
    update public.pacientes
       set fisioterapeuta_id = p_fisioterapeuta_id
     where id = v_cita.paciente_id and fisioterapeuta_id is null;
  end if;

  return jsonb_build_object('ok', true, 'fisioterapeuta_id', p_fisioterapeuta_id);
exception
  when exclusion_violation then
    return jsonb_build_object('ok', false, 'error', 'traslape',
      'mensaje', 'Esa persona ya tiene una cita confirmada en ese horario.');
end;
$$;

-- ----------------------------------------------------------------------------
-- Asistencia: quien atiende se registra solo, tenga el rol que tenga
-- ----------------------------------------------------------------------------

create or replace function public.marcar_asistencia(p_cita_id uuid, p_asistio boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cita   public.citas%rowtype;
  v_sesion uuid;
  v_rol    public.rol_usuario := public.mi_rol();
  v_fisio  uuid;
begin
  select * into v_cita from public.citas where id = p_cita_id;
  if not found then
    raise exception 'Cita no encontrada.' using errcode = 'no_data_found';
  end if;

  if v_rol not in ('superadmin', 'admin', 'recepcion')
     and not (public.atiendo() and (
       v_cita.fisioterapeuta_id = auth.uid() or v_cita.fisioterapeuta_id is null)) then
    raise exception 'Su rol no permite registrar asistencia en esta cita.'
      using errcode = 'insufficient_privilege';
  end if;

  if not p_asistio then
    update public.citas
       set estado = 'ausente', resuelta_por = auth.uid(), resuelta_en = now()
     where id = p_cita_id;
    return jsonb_build_object('ok', true, 'estado', 'ausente');
  end if;

  -- ¿Quien firma la nota? La cita si la trae; si no, quien marca la asistencia
  -- siempre que atienda pacientes. Una nota clinica sin autor no sirve.
  v_fisio := v_cita.fisioterapeuta_id;
  if v_fisio is null and public.atiendo() then
    v_fisio := auth.uid();
    update public.citas set fisioterapeuta_id = v_fisio where id = p_cita_id;
  end if;

  if v_fisio is null then
    return jsonb_build_object('ok', false, 'error', 'falta_fisioterapeuta',
      'mensaje', 'Asigne quien atiende antes de marcar la cita como atendida: la nota clinica necesita autor.');
  end if;

  update public.citas
     set estado = 'atendida', asistio_en = now(), resuelta_por = auth.uid(), resuelta_en = now()
   where id = p_cita_id;

  perform set_config('neoterapia.operacion_interna', 'on', true);
  update public.pacientes
     set fisioterapeuta_id = v_fisio
   where id = v_cita.paciente_id and fisioterapeuta_id is null;
  perform set_config('neoterapia.operacion_interna', 'off', true);

  insert into public.sesiones (cita_id, paciente_id, fisioterapeuta_id, inicio)
  values (p_cita_id, v_cita.paciente_id, v_fisio, coalesce(v_cita.inicio_programado, now()))
  on conflict (cita_id) do nothing
  returning id into v_sesion;

  if v_sesion is null then
    select id into v_sesion from public.sesiones where cita_id = p_cita_id;
  end if;

  insert into public.sesion_areas (sesion_id, area_id, nivel_dolor)
  select v_sesion, ca.area_id, coalesce(ca.intensidad, 0)
  from public.cita_areas ca where ca.cita_id = p_cita_id
  on conflict (sesion_id, area_id) do nothing;

  return jsonb_build_object('ok', true, 'estado', 'atendida', 'sesion_id', v_sesion);
end;
$$;

-- ----------------------------------------------------------------------------
-- Alta de usuarios: la casilla "atiende pacientes"
-- ----------------------------------------------------------------------------

drop function if exists public.crear_usuario_personal(
  text, text, text, public.rol_usuario, text, text, text, text);

create or replace function public.crear_usuario_personal(
  p_email        text,
  p_clave        text,
  p_nombre       text,
  p_rol          public.rol_usuario,
  p_telefono     text default null,
  p_colegiado    text default null,
  p_especialidad text default null,
  p_color        text default null,
  p_atiende      boolean default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_email   text := lower(btrim(coalesce(p_email, '')));
  v_nombre  text := btrim(coalesce(p_nombre, ''));
  v_atiende boolean;
  v_id      uuid;
begin
  if not public.es_superadmin() then
    raise exception 'Solo un superadministrador puede crear usuarios.'
      using errcode = 'insufficient_privilege';
  end if;

  if v_email !~ '^[^\s@]+@[^\s@]+\.[a-zA-Z]{2,}$' then
    return jsonb_build_object('ok', false, 'error', 'correo_invalido',
      'mensaje', 'El correo no tiene un formato valido.');
  end if;

  if length(coalesce(p_clave, '')) < 10 then
    return jsonb_build_object('ok', false, 'error', 'clave_corta',
      'mensaje', 'La contrasena debe tener al menos 10 caracteres.');
  end if;

  if length(v_nombre) < 5 or array_length(string_to_array(v_nombre, ' '), 1) < 2 then
    return jsonb_build_object('ok', false, 'error', 'nombre_invalido',
      'mensaje', 'Escriba nombre y apellido.');
  end if;

  if p_color is not null and p_color !~ '^#[0-9a-fA-F]{6}$' then
    return jsonb_build_object('ok', false, 'error', 'color_invalido',
      'mensaje', 'El color debe ir en formato #rrggbb.');
  end if;

  if exists (select 1 from auth.users u where lower(u.email) = v_email) then
    return jsonb_build_object('ok', false, 'error', 'correo_existente',
      'mensaje', 'Ya existe un usuario con ese correo.');
  end if;

  -- Sin indicacion explicita: atiende quien tiene el rol clinico.
  v_atiende := coalesce(p_atiende, p_rol = 'fisioterapeuta');

  v_id := gen_random_uuid();

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new
  ) values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
    v_email, crypt(p_clave, gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('nombre_completo', v_nombre),
    now(), now(), '', '', '', ''
  );

  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(), v_id, v_id::text,
    jsonb_build_object('sub', v_id::text, 'email', v_email,
                       'email_verified', true, 'phone_verified', false),
    'email', now(), now(), now()
  );

  insert into public.perfiles (
    id, nombre_completo, rol, email, telefono, colegiado, especialidad,
    color_agenda, atiende
  ) values (
    v_id, v_nombre, p_rol, v_email,
    nullif(btrim(coalesce(p_telefono, '')), ''),
    nullif(btrim(coalesce(p_colegiado, '')), ''),
    nullif(btrim(coalesce(p_especialidad, '')), ''),
    coalesce(p_color, '#0d9488'),
    v_atiende
  );

  perform public.registrar_auditoria(
    'cambiar_rol', 'perfiles', v_id::text, null,
    format('Alta de usuario %s con rol %s', v_email, p_rol),
    null, jsonb_build_object('email', v_email, 'rol', p_rol, 'atiende', v_atiende));

  return jsonb_build_object('ok', true, 'usuario_id', v_id, 'email', v_email,
                            'atiende', v_atiende);
end;
$$;

comment on function public.crear_usuario_personal is
  'Alta de personal desde el panel. Solo superadmin. El paciente NUNCA pasa por aqui.';

-- ----------------------------------------------------------------------------
-- Privilegios
-- ----------------------------------------------------------------------------

revoke execute on function public.puede_atender(uuid) from public, anon;
revoke execute on function public.atiendo()           from public, anon;
revoke execute on function public.crear_usuario_personal(
  text, text, text, public.rol_usuario, text, text, text, text, boolean) from public, anon;

grant execute on function public.puede_atender(uuid) to authenticated;
grant execute on function public.atiendo()           to authenticated;
grant execute on function public.crear_usuario_personal(
  text, text, text, public.rol_usuario, text, text, text, text, boolean) to authenticated;
grant execute on function public.confirmar_cita(uuid, timestamptz, uuid, int, text, text) to authenticated;
grant execute on function public.asignar_fisioterapeuta(uuid, uuid) to authenticated;
grant execute on function public.marcar_asistencia(uuid, boolean) to authenticated;

-- ####################  20260825121800_19_url_publica.sql  ####################

-- ============================================================================
-- NeoTerapia · 19 · La URL publica deja de ser localhost
-- ----------------------------------------------------------------------------
-- El sitio ya esta desplegado en https://neoterapia.vercel.app. `url_publica`
-- es la base de TODO enlace que se le manda al paciente (confirmar, cancelar,
-- evaluacion, calendario); mientras apunte a localhost esos enlaces no le
-- sirven a nadie mas que al desarrollador.
--
-- Solo se corrige si sigue en el valor de desarrollo: si manana la clinica
-- compra su dominio y lo cambia desde Administracion, volver a correr esta
-- migracion no se lo pisa.
-- ============================================================================

set search_path = public, extensions;

update public.configuracion
   set valor = '"https://neoterapia.vercel.app"'::jsonb
 where clave = 'url_publica'
   and valor #>> '{}' in ('http://localhost:4200', 'http://localhost:4174', '', 'https://neoterapia.gt');

-- Si la fila no existia (instalacion vieja sin ese seed), se crea.
insert into public.configuracion (clave, valor, descripcion, editable_por)
values ('url_publica', '"https://neoterapia.vercel.app"'::jsonb,
        'Base para los enlaces enviados al paciente', 'superadmin')
on conflict (clave) do nothing;

do $$
begin
  raise notice 'url_publica = %', public.config('url_publica') #>> '{}';
end $$;

-- ####################  seed.sql  ####################

-- ============================================================================
-- NeoTerapia · Datos base (idempotente: se puede correr varias veces)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Configuracion de la clinica
-- ----------------------------------------------------------------------------

insert into public.configuracion (clave, valor, descripcion, editable_por) values
  ('nombre_clinica',          '"NeoTerapia"'::jsonb,          'Nombre visible de la clinica', 'admin'),
  ('zona_horaria',            '"America/Guatemala"'::jsonb,   'Zona horaria de operacion', 'superadmin'),
  ('url_publica',             '"https://neoterapia.vercel.app"'::jsonb, 'Base para los enlaces enviados al paciente', 'superadmin'),
  ('telefono_clinica',        '""'::jsonb,                    'Telefono de contacto', 'admin'),
  ('whatsapp_clinica',        '""'::jsonb,                    'WhatsApp de contacto', 'admin'),
  ('direccion_clinica',       '""'::jsonb,                    'Direccion fisica', 'admin'),
  ('duracion_cita_min',       '45'::jsonb,                    'Duracion por defecto de una cita, en minutos', 'admin'),
  ('dias_anticipacion_max',   '60'::jsonb,                    'Cuantos dias hacia adelante se aceptan solicitudes', 'admin'),
  ('horas_anticipacion_min',  '12'::jsonb,                    'Anticipacion minima para solicitar', 'admin'),
  ('umbral_similitud_nombre', '0.55'::jsonb,                  'Bajo este valor se alerta que el nombre no coincide con el DPI', 'admin'),
  ('umbral_duplicado',        '0.62'::jsonb,                  'Puntaje minimo para marcar dos fichas como posible duplicado', 'admin'),
  ('notificaciones_activas',  'false'::jsonb,                 'Envio real de correo/WhatsApp. Apagado: los mensajes solo se encolan', 'superadmin'),
  ('politica_datos_url',      '"/politica-de-datos"'::jsonb,  'Enlace a la politica de tratamiento de datos', 'admin')
on conflict (clave) do nothing;

-- ----------------------------------------------------------------------------
-- Mapa corporal
-- ----------------------------------------------------------------------------
-- Coordenadas sobre un viewBox de 200x420.
-- Vista anterior: la derecha del paciente queda a la izquierda de la imagen.
-- Vista posterior: la derecha del paciente queda a la derecha de la imagen.

insert into public.areas_cuerpo (codigo, nombre, region, lado, vista, svg_x, svg_y, orden) values
  -- Anterior · cabeza y cuello
  ('cabeza',            'Cabeza',                    'cabeza_cuello',    'central',   'anterior', 100, 26,  10),
  ('cuello_ant',        'Cuello (frente)',           'cabeza_cuello',    'central',   'anterior', 100, 56,  20),
  ('mandibula',         'Mandibula / ATM',           'cabeza_cuello',    'central',   'anterior', 100, 42,  30),

  -- Anterior · miembro superior
  ('hombro_der',        'Hombro derecho',            'miembro_superior', 'derecho',   'anterior', 68,  78,  40),
  ('hombro_izq',        'Hombro izquierdo',          'miembro_superior', 'izquierdo', 'anterior', 132, 78,  50),
  ('brazo_der',         'Brazo derecho',             'miembro_superior', 'derecho',   'anterior', 58,  110, 60),
  ('brazo_izq',         'Brazo izquierdo',           'miembro_superior', 'izquierdo', 'anterior', 142, 110, 70),
  ('codo_der',          'Codo derecho',              'miembro_superior', 'derecho',   'anterior', 52,  138, 80),
  ('codo_izq',          'Codo izquierdo',            'miembro_superior', 'izquierdo', 'anterior', 148, 138, 90),
  ('antebrazo_der',     'Antebrazo derecho',         'miembro_superior', 'derecho',   'anterior', 46,  164, 100),
  ('antebrazo_izq',     'Antebrazo izquierdo',       'miembro_superior', 'izquierdo', 'anterior', 154, 164, 110),
  ('muneca_der',        'Muneca derecha',            'miembro_superior', 'derecho',   'anterior', 41,  188, 120),
  ('muneca_izq',        'Muneca izquierda',          'miembro_superior', 'izquierdo', 'anterior', 159, 188, 130),
  ('mano_der',          'Mano derecha',              'miembro_superior', 'derecho',   'anterior', 37,  206, 140),
  ('mano_izq',          'Mano izquierda',            'miembro_superior', 'izquierdo', 'anterior', 163, 206, 150),

  -- Anterior · tronco
  ('pecho',             'Pecho',                     'tronco',           'central',   'anterior', 100, 98,  160),
  ('costillas_der',     'Costillas derechas',        'tronco',           'derecho',   'anterior', 80,  120, 170),
  ('costillas_izq',     'Costillas izquierdas',      'tronco',           'izquierdo', 'anterior', 120, 120, 180),
  ('abdomen',           'Abdomen',                   'tronco',           'central',   'anterior', 100, 142, 190),

  -- Anterior · miembro inferior
  ('cadera_der',        'Cadera derecha',            'miembro_inferior', 'derecho',   'anterior', 80,  176, 200),
  ('cadera_izq',        'Cadera izquierda',          'miembro_inferior', 'izquierdo', 'anterior', 120, 176, 210),
  ('ingle',             'Ingle',                     'miembro_inferior', 'central',   'anterior', 100, 186, 220),
  ('muslo_der',         'Muslo derecho',             'miembro_inferior', 'derecho',   'anterior', 82,  222, 230),
  ('muslo_izq',         'Muslo izquierdo',           'miembro_inferior', 'izquierdo', 'anterior', 118, 222, 240),
  ('rodilla_der',       'Rodilla derecha',           'miembro_inferior', 'derecho',   'anterior', 82,  262, 250),
  ('rodilla_izq',       'Rodilla izquierda',         'miembro_inferior', 'izquierdo', 'anterior', 118, 262, 260),
  ('espinilla_der',     'Espinilla derecha',         'miembro_inferior', 'derecho',   'anterior', 82,  305, 270),
  ('espinilla_izq',     'Espinilla izquierda',       'miembro_inferior', 'izquierdo', 'anterior', 118, 305, 280),
  ('tobillo_der',       'Tobillo derecho',           'miembro_inferior', 'derecho',   'anterior', 82,  344, 290),
  ('tobillo_izq',       'Tobillo izquierdo',         'miembro_inferior', 'izquierdo', 'anterior', 118, 344, 300),
  ('pie_der',           'Pie derecho',               'miembro_inferior', 'derecho',   'anterior', 80,  366, 310),
  ('pie_izq',           'Pie izquierdo',             'miembro_inferior', 'izquierdo', 'anterior', 120, 366, 320),

  -- Posterior · columna
  ('nuca',              'Nuca',                      'cabeza_cuello',    'central',   'posterior', 100, 48,  400),
  ('cervical',          'Columna cervical',          'columna',          'central',   'posterior', 100, 68,  410),
  ('trapecio_der',      'Trapecio derecho',          'columna',          'derecho',   'posterior', 118, 74,  420),
  ('trapecio_izq',      'Trapecio izquierdo',        'columna',          'izquierdo', 'posterior', 82,  74,  430),
  ('escapula_der',      'Escapula derecha',          'tronco',           'derecho',   'posterior', 120, 100, 440),
  ('escapula_izq',      'Escapula izquierda',        'tronco',           'izquierdo', 'posterior', 80,  100, 450),
  ('dorsal',            'Columna dorsal',            'columna',          'central',   'posterior', 100, 112, 460),
  ('lumbar',            'Columna lumbar',            'columna',          'central',   'posterior', 100, 150, 470),
  ('sacro',             'Sacro / coxis',             'columna',          'central',   'posterior', 100, 176, 480),

  -- Posterior · miembro superior e inferior
  ('codo_post_der',     'Codo derecho (posterior)',  'miembro_superior', 'derecho',   'posterior', 148, 138, 490),
  ('codo_post_izq',     'Codo izquierdo (posterior)','miembro_superior', 'izquierdo', 'posterior', 52,  138, 500),
  ('gluteo_der',        'Gluteo derecho',            'miembro_inferior', 'derecho',   'posterior', 116, 192, 510),
  ('gluteo_izq',        'Gluteo izquierdo',          'miembro_inferior', 'izquierdo', 'posterior', 84,  192, 520),
  ('isquios_der',       'Isquiotibiales derechos',   'miembro_inferior', 'derecho',   'posterior', 116, 230, 530),
  ('isquios_izq',       'Isquiotibiales izquierdos', 'miembro_inferior', 'izquierdo', 'posterior', 84,  230, 540),
  ('rodilla_post_der',  'Rodilla derecha (hueco)',   'miembro_inferior', 'derecho',   'posterior', 116, 264, 550),
  ('rodilla_post_izq',  'Rodilla izquierda (hueco)', 'miembro_inferior', 'izquierdo', 'posterior', 84,  264, 560),
  ('pantorrilla_der',   'Pantorrilla derecha',       'miembro_inferior', 'derecho',   'posterior', 116, 305, 570),
  ('pantorrilla_izq',   'Pantorrilla izquierda',     'miembro_inferior', 'izquierdo', 'posterior', 84,  305, 580),
  ('aquiles_der',       'Tendon de Aquiles derecho', 'miembro_inferior', 'derecho',   'posterior', 116, 346, 590),
  ('aquiles_izq',       'Tendon de Aquiles izquierdo','miembro_inferior','izquierdo', 'posterior', 84,  346, 600),
  ('talon_der',         'Talon derecho',             'miembro_inferior', 'derecho',   'posterior', 116, 368, 610),
  ('talon_izq',         'Talon izquierdo',           'miembro_inferior', 'izquierdo', 'posterior', 84,  368, 620)
on conflict (codigo) do nothing;

-- ----------------------------------------------------------------------------
-- Tratamientos
-- ----------------------------------------------------------------------------
-- Sin precio a proposito: varia por caso y se escribe al aplicarlo en la sesion.

insert into public.tratamientos (codigo, nombre, descripcion, duracion_min, requiere_nota) values
  ('EVAL',   'Evaluacion inicial',        'Valoracion completa, historia clinica y plan de tratamiento', 60, true),
  ('TMAN',   'Terapia manual',            'Movilizacion articular y tecnicas de tejido blando',          45, false),
  ('MASO',   'Masaje descontracturante',  'Masaje terapeutico profundo',                                40, false),
  ('ELEC',   'Electroterapia',            'TENS / corrientes analgesicas',                              20, false),
  ('ULTR',   'Ultrasonido terapeutico',   'Ultrasonido para tejidos profundos',                         15, false),
  ('LASE',   'Laserterapia',              'Laser de baja potencia',                                     15, false),
  ('PSEC',   'Puncion seca',              'Tratamiento de puntos gatillo miofasciales',                 30, true),
  ('EJER',   'Ejercicio terapeutico',     'Programa supervisado de fortalecimiento y movilidad',        45, false),
  ('VNM',    'Vendaje neuromuscular',     'Aplicacion de kinesiotape',                                  15, false),
  ('CRIO',   'Crioterapia',               'Aplicacion de frio local',                                   15, false),
  ('TERM',   'Termoterapia',              'Compresas humedo-calientes / parafina',                      15, false),
  ('TRAC',   'Traccion',                  'Traccion cervical o lumbar',                                 20, false),
  ('RESP',   'Fisioterapia respiratoria', 'Tecnicas de higiene bronquial y reeducacion respiratoria',   40, true),
  ('DREN',   'Drenaje linfatico',         'Drenaje linfatico manual',                                   50, false)
on conflict (codigo) do nothing;

-- ----------------------------------------------------------------------------
-- Horario de la clinica (lunes a viernes manana y tarde, sabado manana)
-- ----------------------------------------------------------------------------

insert into public.horarios_atencion (fisioterapeuta_id, dia_semana, hora_inicio, hora_fin, cupos)
select null, d, h.inicio, h.fin, 2
from generate_series(1, 5) d
cross join (values ('08:00'::time, '12:00'::time), ('14:00'::time, '18:00'::time)) as h(inicio, fin)
where not exists (
  select 1 from public.horarios_atencion x
  where x.fisioterapeuta_id is null and x.dia_semana = d and x.hora_inicio = h.inicio
);

insert into public.horarios_atencion (fisioterapeuta_id, dia_semana, hora_inicio, hora_fin, cupos)
select null, 6, '08:00'::time, '12:00'::time, 1
where not exists (
  select 1 from public.horarios_atencion x
  where x.fisioterapeuta_id is null and x.dia_semana = 6
);


-- ----------------------------------------------------------------------------
-- Inventario inicial
-- ----------------------------------------------------------------------------
-- Existencia en cero: se carga registrando movimientos de entrada, para que la
-- bitacora cuadre desde el primer dia.

insert into public.inventario_articulos (codigo, nombre, descripcion, categoria, unidad, minimo, ubicacion) values
  ('INS-ELEC', 'Electrodos autoadhesivos',  'Para TENS / electroestimulacion',      'insumo',      'par',    10, 'Bodega'),
  ('INS-GEL',  'Gel conductor',             'Para ultrasonido y electroterapia',     'insumo',      'frasco',  4, 'Bodega'),
  ('INS-KT',   'Kinesiotape',               'Rollo de vendaje neuromuscular',        'insumo',      'rollo',   6, 'Bodega'),
  ('INS-PAP',  'Papel para camilla',        'Rollo desechable',                      'insumo',      'rollo',   8, 'Bodega'),
  ('INS-ALG',  'Algodon',                   'Bolsa',                                 'insumo',      'bolsa',   3, 'Bodega'),
  ('INS-GUA',  'Guantes de nitrilo',        'Caja de 100 unidades',                  'insumo',      'caja',    4, 'Bodega'),
  ('INS-VEN',  'Venda elastica',            'Venda de compresion',                   'insumo',      'unidad', 10, 'Bodega'),
  ('INS-PAR',  'Parafina',                  'Bloque para termoterapia',              'insumo',      'kg',      2, 'Bodega'),
  ('LIM-DES',  'Desinfectante de superficies', 'Galon',                              'limpieza',    'galon',   2, 'Bodega'),
  ('LIM-ALC',  'Alcohol en gel',            'Dispensador',                           'limpieza',    'litro',   3, 'Recepcion'),
  ('EQU-TENS', 'Equipo TENS',               'Electroestimulador portatil',           'equipo',      'unidad',  1, 'Consultorio 1'),
  ('EQU-ULT',  'Equipo de ultrasonido',     'Ultrasonido terapeutico',               'equipo',      'unidad',  1, 'Consultorio 1'),
  ('EQU-BAN',  'Bandas elasticas',          'Juego de resistencias',                 'equipo',      'juego',   2, 'Gimnasio'),
  ('PAP-CONS', 'Hojas de consentimiento',   'Formato impreso',                       'papeleria',   'unidad', 25, 'Recepcion')
on conflict (codigo) do nothing;

-- ============================================================================
--  QUE SIGUE (no se ejecuta solo: hay que editarlo)
-- ----------------------------------------------------------------------------
--  1. Cree su usuario en  Authentication → Users → Add user
--     (marque "Auto Confirm User" para no tener que confirmar el correo).
--
--  2. Copie el UUID que le asigno y descomente esto, cambiando los tres valores.
--     `atiende` en true si ademas de administrar usted pasa consulta: asi
--     aparece en la agenda y puede firmar notas clinicas.
--
--     insert into public.perfiles (id, nombre_completo, rol, email, atiende)
--     values ('PEGUE-AQUI-EL-UUID', 'Miguel Cabrera', 'superadmin', 'su@correo.com', true);
--
--  3. La URL base de los enlaces que se le envian al paciente ya queda en
--     https://neoterapia.vercel.app. Solo hay que tocarla si cambia de dominio:
--
--     update public.configuracion
--        set valor = '"https://su-dominio.com"'::jsonb
--      where clave = 'url_publica';
-- ============================================================================

-- Verificacion rapida: las dos cifras deben ser iguales (todas las tablas con RLS).
select count(*) filter (where rowsecurity)      as tablas_con_rls,
       count(*)                                  as tablas_totales
from pg_tables
where schemaname = 'public';
