-- ============================================================================
-- NeoTerapia · 13 · Alta y gestion de usuarios del personal desde el panel
-- ----------------------------------------------------------------------------
-- Por que una RPC y no la Admin API de Supabase:
--   `auth.admin.createUser()` exige la service_role key, que JAMAS debe estar
--   en el cliente Angular. La alternativa seria una Edge Function; mientras no
--   haya uno desplegado, estas funciones SECURITY DEFINER hacen el trabajo sin
--   exponer ninguna credencial: el unico permiso lo da el JWT del que llama.
--
-- El candado: `es_superadmin()` lee auth.uid() del JWT, que no se puede
-- falsificar sin el secreto del proyecto. Sin ese rol, la funcion aborta antes
-- de tocar nada.
-- ============================================================================

set search_path = public, extensions;

-- La migracion 18 le agrega el parametro `p_atiende`. Si esa version ya existe
-- (reinstalacion sobre una base ya migrada), hay que quitarla antes: dos
-- sobrecargas del mismo nombre volverian ambigua cualquier llamada.
drop function if exists public.crear_usuario_personal(
  text, text, text, public.rol_usuario, text, text, text, text, boolean);

create or replace function public.crear_usuario_personal(
  p_email        text,
  p_clave        text,
  p_nombre       text,
  p_rol          public.rol_usuario,
  p_telefono     text default null,
  p_colegiado    text default null,
  p_especialidad text default null,
  p_color        text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_email  text := lower(btrim(coalesce(p_email, '')));
  v_nombre text := btrim(coalesce(p_nombre, ''));
  v_id     uuid;
begin
  -- ---------- Candado ----------------------------------------------------
  if not public.es_superadmin() then
    raise exception 'Solo un superadministrador puede crear usuarios.'
      using errcode = 'insufficient_privilege';
  end if;

  -- ---------- Validaciones ------------------------------------------------
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

  -- ---------- Alta en Auth ------------------------------------------------
  -- El correo queda confirmado de una vez: lo esta dando de alta un
  -- superadministrador, no es un auto-registro que haya que verificar.
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

  -- ---------- Perfil ------------------------------------------------------
  insert into public.perfiles (
    id, nombre_completo, rol, email, telefono, colegiado, especialidad, color_agenda
  ) values (
    v_id, v_nombre, p_rol, v_email,
    nullif(btrim(coalesce(p_telefono, '')), ''),
    nullif(btrim(coalesce(p_colegiado, '')), ''),
    nullif(btrim(coalesce(p_especialidad, '')), ''),
    coalesce(p_color, '#0d9488')
  );

  perform public.registrar_auditoria(
    'cambiar_rol', 'perfiles', v_id::text, null,
    format('Alta de usuario %s con rol %s', v_email, p_rol),
    null, jsonb_build_object('email', v_email, 'rol', p_rol));

  return jsonb_build_object('ok', true, 'usuario_id', v_id, 'email', v_email);
end;
$$;

comment on function public.crear_usuario_personal is
  'Alta de personal desde el panel. Solo superadmin. El paciente NUNCA pasa por aqui.';

-- ----------------------------------------------------------------------------
-- Restablecer la contrasena de otro usuario
-- ----------------------------------------------------------------------------
-- Para la propia contrasena esta `/panel/clave`, que usa auth.updateUser().
-- Esta es para cuando alguien del equipo la olvida y no tiene acceso al correo.

create or replace function public.restablecer_contrasena(
  p_usuario_id uuid,
  p_clave      text
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_email text;
begin
  if not public.es_superadmin() then
    raise exception 'Solo un superadministrador puede restablecer contrasenas.'
      using errcode = 'insufficient_privilege';
  end if;

  if length(coalesce(p_clave, '')) < 10 then
    return jsonb_build_object('ok', false, 'error', 'clave_corta',
      'mensaje', 'La contrasena debe tener al menos 10 caracteres.');
  end if;

  select u.email into v_email from auth.users u where u.id = p_usuario_id;
  if v_email is null then
    return jsonb_build_object('ok', false, 'error', 'no_existe');
  end if;

  update auth.users
     set encrypted_password = crypt(p_clave, gen_salt('bf')),
         email_confirmed_at = coalesce(email_confirmed_at, now()),
         updated_at = now()
   where id = p_usuario_id;

  perform public.registrar_auditoria(
    'cambiar_rol', 'perfiles', p_usuario_id::text, null,
    format('Restablecimiento de contrasena de %s', v_email));

  return jsonb_build_object('ok', true, 'email', v_email);
end;
$$;

-- ----------------------------------------------------------------------------
-- Privilegios: nada de esto lo puede llamar `anon`
-- ----------------------------------------------------------------------------
revoke execute on function public.crear_usuario_personal(
  text, text, text, public.rol_usuario, text, text, text, text) from public, anon;
revoke execute on function public.restablecer_contrasena(uuid, text) from public, anon;

grant execute on function public.crear_usuario_personal(
  text, text, text, public.rol_usuario, text, text, text, text) to authenticated;
grant execute on function public.restablecer_contrasena(uuid, text) to authenticated;
