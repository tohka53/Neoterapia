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
