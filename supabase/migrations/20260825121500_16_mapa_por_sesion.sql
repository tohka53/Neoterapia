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
