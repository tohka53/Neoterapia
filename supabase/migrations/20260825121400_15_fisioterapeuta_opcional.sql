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
