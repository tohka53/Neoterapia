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
