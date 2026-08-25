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
  v_base   text := coalesce(public.config('url_publica') #>> '{}', 'https://neoterapia.gt');
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
  v_base  text := coalesce(public.config('url_publica') #>> '{}', 'https://neoterapia.gt');
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
