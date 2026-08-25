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
