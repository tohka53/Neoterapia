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
