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
