-- ============================================================================
-- NeoTerapia · 09 · Seguridad: roles, RLS y privilegios de columna
-- ----------------------------------------------------------------------------
-- Principios:
--   1. `anon` no toca ninguna tabla directamente. Solo RPCs SECURITY DEFINER.
--   2. `recepcion` coordina: ve pacientes y citas, NUNCA notas clinicas.
--   3. `fisioterapeuta` ve la clinica SOLO de los pacientes que atiende.
--   4. El DPI en claro no se puede leer por SQL directo desde la app: hay que
--      pasar por `ver_dpi_paciente()`, que audita.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Helpers de rol (SECURITY DEFINER: los ejecuta el dueno, que salta RLS,
-- evitando la recursion infinita al consultar `perfiles` desde su propia RLS)
-- ----------------------------------------------------------------------------

-- Resuelve pgcrypto / pg_trgm / unaccent vivan donde vivan (Supabase las pone
-- en `extensions`; un Postgres normal las deja en `public`).
set search_path = public, extensions;

create or replace function public.mi_rol()
returns public.rol_usuario
language sql
stable
security definer
set search_path = public
as $$
  select p.rol from public.perfiles p where p.id = auth.uid() and p.activo
$$;

create or replace function public.es_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select public.mi_rol() is not null
$$;

create or replace function public.es_superadmin()
returns boolean language sql stable security definer set search_path = public as $$
  select public.mi_rol() = 'superadmin'
$$;

create or replace function public.es_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select public.mi_rol() in ('admin', 'superadmin')
$$;

create or replace function public.es_recepcion()
returns boolean language sql stable security definer set search_path = public as $$
  select public.mi_rol() = 'recepcion'
$$;

create or replace function public.es_fisio()
returns boolean language sql stable security definer set search_path = public as $$
  select public.mi_rol() = 'fisioterapeuta'
$$;

-- ¿El fisioterapeuta autenticado atiende a este paciente?
create or replace function public.atiendo_paciente(p_paciente_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.pacientes p
    where p.id = p_paciente_id and p.fisioterapeuta_id = auth.uid()
  ) or exists (
    select 1 from public.citas c
    where c.paciente_id = p_paciente_id and c.fisioterapeuta_id = auth.uid()
  )
$$;

-- ¿Puede el usuario actual ver la ficha de este paciente?
create or replace function public.puedo_ver_paciente(p_paciente_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when public.mi_rol() in ('superadmin', 'admin', 'recepcion') then true
    when public.mi_rol() = 'fisioterapeuta' then public.atiendo_paciente(p_paciente_id)
    else false
  end
$$;

-- ¿Puede ver el contenido clinico (notas, antecedentes, evolucion)?
create or replace function public.puedo_ver_clinico(p_paciente_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when public.mi_rol() in ('superadmin', 'admin') then true
    when public.mi_rol() = 'fisioterapeuta' then public.atiendo_paciente(p_paciente_id)
    else false   -- recepcion NO
  end
$$;

-- ============================================================================
-- Activar RLS en absolutamente todo
-- ============================================================================

do $$
declare t text;
begin
  foreach t in array array[
    'perfiles', 'configuracion', 'areas_cuerpo', 'tratamientos',
    'horarios_atencion', 'bloqueos_agenda',
    'pacientes', 'pacientes_clinico', 'pacientes_historial_identidad',
    'alertas', 'posibles_duplicados',
    'citas', 'cita_areas', 'citas_historial_estado',
    'sesiones', 'sesiones_adendas', 'sesion_areas', 'sesion_tratamientos',
    'evaluaciones', 'pagos',
    'auditoria', 'enlaces_accion', 'mensajes', 'control_solicitudes'
  ] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- Deliberadamente NO se usa FORCE ROW LEVEL SECURITY: el dueno de las tablas
-- (postgres) debe poder saltarse RLS para que funcionen las RPC SECURITY
-- DEFINER que sostienen el flujo publico. `anon` y `authenticated` no son
-- dueños de nada, asi que para ellos RLS aplica siempre.

-- ============================================================================
-- Privilegios base: `anon` no ve nada; `authenticated` parte de cero
-- ============================================================================

revoke all on all tables    in schema public from anon, authenticated;
revoke all on all functions in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

grant usage on schema public to anon, authenticated;

-- ----------------------------------------------------------------------------
-- perfiles
-- ----------------------------------------------------------------------------
grant select, update on public.perfiles to authenticated;

drop policy if exists perfiles_select_staff on public.perfiles;
create policy perfiles_select_staff on public.perfiles
  for select to authenticated
  using (public.es_staff());

drop policy if exists perfiles_update_propio on public.perfiles;
create policy perfiles_update_propio on public.perfiles
  for update to authenticated
  using (id = auth.uid() or public.es_superadmin())
  with check (id = auth.uid() or public.es_superadmin());

-- Solo el superadmin cambia roles o reactiva usuarios.
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
  if new.rol is distinct from old.rol then
    perform public.registrar_auditoria(
      'cambiar_rol', 'perfiles', new.id::text, null,
      format('Rol %s -> %s', old.rol, new.rol),
      jsonb_build_object('rol', old.rol), jsonb_build_object('rol', new.rol));
  end if;
  return new;
end;
$$;

drop trigger if exists tg_perfiles_rol on public.perfiles;
create trigger tg_perfiles_rol before update on public.perfiles
  for each row execute function public.tg_perfiles_control_rol();

-- ----------------------------------------------------------------------------
-- configuracion
-- ----------------------------------------------------------------------------
grant select on public.configuracion to authenticated;
grant insert, update on public.configuracion to authenticated;

drop policy if exists config_select on public.configuracion;
create policy config_select on public.configuracion
  for select to authenticated using (public.es_staff());
drop policy if exists config_write on public.configuracion;
create policy config_write on public.configuracion
  for all to authenticated using (public.es_admin()) with check (public.es_admin());

-- ----------------------------------------------------------------------------
-- areas_cuerpo: catalogo publico (lo necesita el mapa corporal del formulario)
-- ----------------------------------------------------------------------------
grant select on public.areas_cuerpo to anon, authenticated;
grant insert, update, delete on public.areas_cuerpo to authenticated;

drop policy if exists areas_select_publico on public.areas_cuerpo;
create policy areas_select_publico on public.areas_cuerpo
  for select to anon using (activo);
drop policy if exists areas_select_staff on public.areas_cuerpo;
create policy areas_select_staff on public.areas_cuerpo
  for select to authenticated using (public.es_staff());
drop policy if exists areas_write_admin on public.areas_cuerpo;
create policy areas_write_admin on public.areas_cuerpo
  for all to authenticated using (public.es_admin()) with check (public.es_admin());

-- ----------------------------------------------------------------------------
-- tratamientos / horarios / bloqueos
-- ----------------------------------------------------------------------------
grant select, insert, update, delete on public.tratamientos      to authenticated;
grant select, insert, update, delete on public.horarios_atencion to authenticated;
grant select, insert, update, delete on public.bloqueos_agenda   to authenticated;

drop policy if exists tratamientos_select on public.tratamientos;
create policy tratamientos_select on public.tratamientos
  for select to authenticated using (public.es_staff());
drop policy if exists tratamientos_write on public.tratamientos;
create policy tratamientos_write on public.tratamientos
  for all to authenticated using (public.es_admin()) with check (public.es_admin());

drop policy if exists horarios_select on public.horarios_atencion;
create policy horarios_select on public.horarios_atencion
  for select to authenticated using (public.es_staff());
drop policy if exists horarios_write on public.horarios_atencion;
create policy horarios_write on public.horarios_atencion
  for all to authenticated using (public.es_admin()) with check (public.es_admin());

drop policy if exists bloqueos_select on public.bloqueos_agenda;
create policy bloqueos_select on public.bloqueos_agenda
  for select to authenticated using (public.es_staff());
drop policy if exists bloqueos_write on public.bloqueos_agenda;
create policy bloqueos_write on public.bloqueos_agenda
  for all to authenticated
  using (public.es_admin() or fisioterapeuta_id = auth.uid())
  with check (public.es_admin() or fisioterapeuta_id = auth.uid());

-- ----------------------------------------------------------------------------
-- pacientes: el DPI en claro queda fuera del alcance de la app
-- ----------------------------------------------------------------------------
do $$
declare
  v_lectura   text;
  v_escritura text;
  v_ocultas   text[] := array['dpi', 'dpi_norm'];
begin
  select string_agg(quote_ident(c.column_name), ', ' order by c.ordinal_position)
    into v_lectura
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = 'pacientes'
    and c.column_name <> all (v_ocultas);

  select string_agg(quote_ident(c.column_name), ', ' order by c.ordinal_position)
    into v_escritura
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = 'pacientes'
    and c.column_name <> all (v_ocultas || array['id', 'creado_en', 'creado_por'])
    and c.is_generated = 'NEVER'
    and c.is_updatable = 'YES';

  execute format('grant select (%s) on public.pacientes to authenticated', v_lectura);
  execute format('grant insert (%s) on public.pacientes to authenticated', v_escritura);
  execute format('grant update (%s) on public.pacientes to authenticated', v_escritura);
end $$;

comment on column public.pacientes.dpi is
  'REVOCADO para anon/authenticated. Se lee unicamente con ver_dpi_paciente(), que deja rastro en auditoria.';

drop policy if exists pacientes_select on public.pacientes;
create policy pacientes_select on public.pacientes
  for select to authenticated
  using (public.puedo_ver_paciente(id));

drop policy if exists pacientes_insert on public.pacientes;
create policy pacientes_insert on public.pacientes
  for insert to authenticated
  with check (public.mi_rol() in ('superadmin', 'admin', 'recepcion'));

drop policy if exists pacientes_update on public.pacientes;
create policy pacientes_update on public.pacientes
  for update to authenticated
  using (public.mi_rol() in ('superadmin', 'admin', 'recepcion')
         or (public.es_fisio() and public.atiendo_paciente(id)))
  with check (public.mi_rol() in ('superadmin', 'admin', 'recepcion')
         or (public.es_fisio() and public.atiendo_paciente(id)));

-- El estado de fusion solo se toca desde fusionar_pacientes().
create or replace function public.tg_pacientes_control_edicion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_setting('neoterapia.operacion_interna', true) = 'on' then
    return new;
  end if;

  if new.estado is distinct from old.estado and new.estado = 'fusionado' then
    raise exception 'La fusion de fichas se realiza con fusionar_pacientes().'
      using errcode = 'insufficient_privilege';
  end if;

  if new.fusionado_en_id is distinct from old.fusionado_en_id then
    raise exception 'fusionado_en_id lo administra fusionar_pacientes().'
      using errcode = 'insufficient_privilege';
  end if;

  -- El fisioterapeuta no administra datos de contacto ni asignaciones.
  if public.es_fisio() and (
       new.telefono          is distinct from old.telefono or
       new.whatsapp          is distinct from old.whatsapp or
       new.email             is distinct from old.email    or
       new.nombre_completo   is distinct from old.nombre_completo or
       new.fisioterapeuta_id is distinct from old.fisioterapeuta_id)
  then
    raise exception 'Un fisioterapeuta no modifica identidad, contacto ni asignacion del paciente.'
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

drop trigger if exists tg_pacientes_edicion on public.pacientes;
create trigger tg_pacientes_edicion before update on public.pacientes
  for each row execute function public.tg_pacientes_control_edicion();

-- ----------------------------------------------------------------------------
-- pacientes_clinico
-- ----------------------------------------------------------------------------
grant select, insert, update on public.pacientes_clinico to authenticated;

drop policy if exists clinico_select on public.pacientes_clinico;
create policy clinico_select on public.pacientes_clinico
  for select to authenticated using (public.puedo_ver_clinico(paciente_id));
drop policy if exists clinico_write on public.pacientes_clinico;
create policy clinico_write on public.pacientes_clinico
  for all to authenticated
  using (public.puedo_ver_clinico(paciente_id))
  with check (public.puedo_ver_clinico(paciente_id));

-- ----------------------------------------------------------------------------
-- historial de identidad / alertas / duplicados
-- ----------------------------------------------------------------------------
grant select on public.pacientes_historial_identidad to authenticated;
grant select, update on public.alertas             to authenticated;
grant select, update on public.posibles_duplicados to authenticated;

drop policy if exists hist_identidad_select on public.pacientes_historial_identidad;
create policy hist_identidad_select on public.pacientes_historial_identidad
  for select to authenticated using (public.es_admin());

drop policy if exists alertas_select on public.alertas;
create policy alertas_select on public.alertas
  for select to authenticated
  using (public.es_admin() or public.es_recepcion());
drop policy if exists alertas_update on public.alertas;
create policy alertas_update on public.alertas
  for update to authenticated
  using (public.es_admin() or public.es_recepcion())
  with check (public.es_admin() or public.es_recepcion());

drop policy if exists duplicados_select on public.posibles_duplicados;
create policy duplicados_select on public.posibles_duplicados
  for select to authenticated using (public.es_admin());
drop policy if exists duplicados_update on public.posibles_duplicados;
create policy duplicados_update on public.posibles_duplicados
  for update to authenticated using (public.es_admin()) with check (public.es_admin());

-- ----------------------------------------------------------------------------
-- citas
-- ----------------------------------------------------------------------------
grant select, insert, update on public.citas to authenticated;
grant select, insert, update, delete on public.cita_areas to authenticated;
grant select on public.citas_historial_estado to authenticated;

drop policy if exists citas_select on public.citas;
create policy citas_select on public.citas
  for select to authenticated
  using (
    public.mi_rol() in ('superadmin', 'admin', 'recepcion')
    or (public.es_fisio() and (fisioterapeuta_id = auth.uid() or public.atiendo_paciente(paciente_id)))
  );

drop policy if exists citas_insert on public.citas;
create policy citas_insert on public.citas
  for insert to authenticated
  with check (public.mi_rol() in ('superadmin', 'admin', 'recepcion'));

drop policy if exists citas_update on public.citas;
create policy citas_update on public.citas
  for update to authenticated
  using (
    public.mi_rol() in ('superadmin', 'admin', 'recepcion')
    or (public.es_fisio() and fisioterapeuta_id = auth.uid())
  )
  with check (
    public.mi_rol() in ('superadmin', 'admin', 'recepcion')
    or (public.es_fisio() and fisioterapeuta_id = auth.uid())
  );

drop policy if exists cita_areas_select on public.cita_areas;
create policy cita_areas_select on public.cita_areas
  for select to authenticated
  using (exists (select 1 from public.citas c where c.id = cita_id));
drop policy if exists cita_areas_write on public.cita_areas;
create policy cita_areas_write on public.cita_areas
  for all to authenticated
  using (exists (select 1 from public.citas c where c.id = cita_id))
  with check (exists (select 1 from public.citas c where c.id = cita_id));

drop policy if exists citas_hist_select on public.citas_historial_estado;
create policy citas_hist_select on public.citas_historial_estado
  for select to authenticated
  using (exists (select 1 from public.citas c where c.id = cita_id));

-- ----------------------------------------------------------------------------
-- sesiones y todo lo clinico: recepcion queda fuera
-- ----------------------------------------------------------------------------
grant select, insert, update on public.sesiones            to authenticated;
grant select, insert          on public.sesiones_adendas   to authenticated;
grant select, insert, update, delete on public.sesion_areas        to authenticated;
grant select, insert, update, delete on public.sesion_tratamientos to authenticated;

drop policy if exists sesiones_select on public.sesiones;
create policy sesiones_select on public.sesiones
  for select to authenticated using (public.puedo_ver_clinico(paciente_id));
drop policy if exists sesiones_insert on public.sesiones;
create policy sesiones_insert on public.sesiones
  for insert to authenticated
  with check (public.es_admin() or (public.es_fisio() and fisioterapeuta_id = auth.uid()));
drop policy if exists sesiones_update on public.sesiones;
create policy sesiones_update on public.sesiones
  for update to authenticated
  using (public.es_admin() or (public.es_fisio() and fisioterapeuta_id = auth.uid()))
  with check (public.es_admin() or (public.es_fisio() and fisioterapeuta_id = auth.uid()));

drop policy if exists adendas_select on public.sesiones_adendas;
create policy adendas_select on public.sesiones_adendas
  for select to authenticated
  using (exists (select 1 from public.sesiones s where s.id = sesion_id));
drop policy if exists adendas_insert on public.sesiones_adendas;
create policy adendas_insert on public.sesiones_adendas
  for insert to authenticated
  with check (autor_id = auth.uid()
              and exists (select 1 from public.sesiones s where s.id = sesion_id));

drop policy if exists sesion_areas_all on public.sesion_areas;
create policy sesion_areas_all on public.sesion_areas
  for all to authenticated
  using (exists (select 1 from public.sesiones s where s.id = sesion_id))
  with check (exists (select 1 from public.sesiones s where s.id = sesion_id));

drop policy if exists sesion_trat_all on public.sesion_tratamientos;
create policy sesion_trat_all on public.sesion_tratamientos
  for all to authenticated
  using (exists (select 1 from public.sesiones s where s.id = sesion_id))
  with check (exists (select 1 from public.sesiones s where s.id = sesion_id));

-- ----------------------------------------------------------------------------
-- evaluaciones
-- ----------------------------------------------------------------------------
grant select on public.evaluaciones to authenticated;

drop policy if exists evaluaciones_select on public.evaluaciones;
create policy evaluaciones_select on public.evaluaciones
  for select to authenticated
  using (public.puedo_ver_paciente(paciente_id));

-- ----------------------------------------------------------------------------
-- pagos: administracion y recepcion. El fisioterapeuta no.
-- ----------------------------------------------------------------------------
grant select, insert, update on public.pagos to authenticated;

drop policy if exists pagos_select on public.pagos;
create policy pagos_select on public.pagos
  for select to authenticated
  using (public.mi_rol() in ('superadmin', 'admin', 'recepcion'));
drop policy if exists pagos_insert on public.pagos;
create policy pagos_insert on public.pagos
  for insert to authenticated
  with check (public.mi_rol() in ('superadmin', 'admin', 'recepcion'));
drop policy if exists pagos_update on public.pagos;
create policy pagos_update on public.pagos
  for update to authenticated
  using (public.mi_rol() in ('superadmin', 'admin', 'recepcion'))
  with check (public.mi_rol() in ('superadmin', 'admin', 'recepcion'));

-- ----------------------------------------------------------------------------
-- auditoria: solo lectura y solo administracion
-- ----------------------------------------------------------------------------
grant select on public.auditoria to authenticated;

drop policy if exists auditoria_select on public.auditoria;
create policy auditoria_select on public.auditoria
  for select to authenticated using (public.es_admin());

-- ----------------------------------------------------------------------------
-- mensajes: bitacora de comunicacion, sin acceso del fisioterapeuta
-- ----------------------------------------------------------------------------
grant select on public.mensajes to authenticated;

drop policy if exists mensajes_select on public.mensajes;
create policy mensajes_select on public.mensajes
  for select to authenticated
  using (public.mi_rol() in ('superadmin', 'admin', 'recepcion'));

-- ----------------------------------------------------------------------------
-- enlaces_accion y control_solicitudes: ningun cliente los toca.
-- Se manipulan exclusivamente desde funciones SECURITY DEFINER.
-- ----------------------------------------------------------------------------
-- (sin GRANT y sin policies para anon/authenticated: acceso cero)

-- ----------------------------------------------------------------------------
-- Vistas
-- ----------------------------------------------------------------------------
grant select on public.v_saldos_paciente to authenticated;

-- ----------------------------------------------------------------------------
-- Defaults para objetos futuros: nada se expone por accidente
-- ----------------------------------------------------------------------------
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on functions from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
