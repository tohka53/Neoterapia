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
