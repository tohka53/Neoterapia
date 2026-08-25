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
