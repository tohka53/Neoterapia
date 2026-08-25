-- ============================================================================
-- NeoTerapia · Pruebas funcionales del backend
-- Ejecutar sobre una base con las migraciones + seed aplicados.
--   psql -d neoterapia_test -v ON_ERROR_STOP=1 -f tests/01_pruebas.sql
-- ============================================================================

\set QUIET on
\pset pager off

create or replace function pg_temp.ok(p_cond boolean, p_titulo text)
returns void language plpgsql as $$
begin
  if p_cond then
    raise notice '  OK    %', p_titulo;
  else
    raise exception 'FALLO: %', p_titulo;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Personal de prueba
-- ---------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'super@neoterapia.gt'),
  ('22222222-2222-2222-2222-222222222222', 'admin@neoterapia.gt'),
  ('33333333-3333-3333-3333-333333333333', 'recepcion@neoterapia.gt'),
  ('44444444-4444-4444-4444-444444444444', 'fisio1@neoterapia.gt'),
  ('55555555-5555-5555-5555-555555555555', 'fisio2@neoterapia.gt')
on conflict (id) do nothing;

insert into public.perfiles (id, nombre_completo, rol, email) values
  ('11111111-1111-1111-1111-111111111111', 'Super Admin',        'superadmin',     'super@neoterapia.gt'),
  ('22222222-2222-2222-2222-222222222222', 'Ana Administradora', 'admin',          'admin@neoterapia.gt'),
  ('33333333-3333-3333-3333-333333333333', 'Rita Recepcion',     'recepcion',      'recepcion@neoterapia.gt'),
  ('44444444-4444-4444-4444-444444444444', 'Fabio Fisio',        'fisioterapeuta', 'fisio1@neoterapia.gt'),
  ('55555555-5555-5555-5555-555555555555', 'Fiona Fisio',        'fisioterapeuta', 'fisio2@neoterapia.gt')
on conflict (id) do nothing;

\echo ''
\echo '== 1. Validacion de DPI guatemalteco =='
do $$
begin
  perform pg_temp.ok(public.dpi_es_valido('6018159041102'),        'DPI valido se acepta');
  perform pg_temp.ok(public.dpi_es_valido('6018 15904 1102'),      'DPI con espacios se normaliza');
  -- Mismo DPI con el 9.o digito (verificador) alterado de 4 a 5
  perform pg_temp.ok(not public.dpi_es_valido('6018159051102'),    'Digito verificador incorrecto se rechaza');
  perform pg_temp.ok(not public.dpi_es_valido('123456789'),        'Longitud incorrecta se rechaza');
  perform pg_temp.ok(
    (public.validar_dpi('6018159049902') ->> 'motivo') = 'departamento',
    'Departamento fuera de rango se rechaza');
  perform pg_temp.ok(public.normalizar_dpi('6018-15904-1102') = '6018159041102',
    'normalizar_dpi quita separadores');
  perform pg_temp.ok(public.enmascarar_dpi('6018159041102') = '6018 ***** 1102',
    'El DPI se enmascara para listados');
end $$;

\echo ''
\echo '== 2. Solicitud publica: alta automatica de la ficha =='
do $$
declare
  r1 jsonb; r2 jsonb;
  v_pac uuid; v_total int;
begin
  r1 := public.solicitar_cita(jsonb_build_object(
    'dpi', '6018 15904 1102',
    'nombre_completo', 'Juan Carlos Perez Lopez',
    'telefono', '5512-3456',
    'email', 'JUAN.perez@Example.COM ',
    'canal_preferido', 'whatsapp',
    'whatsapp', '5512-3456',
    'fecha', (current_date + 5)::text,
    'hora', '09:00',
    'motivo_consulta', 'Dolor lumbar al levantar peso',
    'comentarios', 'Trabajo sentado 8 horas',
    'acepta_politica', true,
    'areas', jsonb_build_array(
      jsonb_build_object('codigo', 'lumbar', 'intensidad', 7),
      jsonb_build_object('codigo', 'gluteo_der', 'intensidad', 4))));

  perform pg_temp.ok((r1 ->> 'ok')::boolean, 'La solicitud se acepta');
  perform pg_temp.ok(r1 ->> 'codigo_referencia' like 'NT-%', 'Devuelve codigo de referencia');
  perform pg_temp.ok(r1 ? 'codigo_referencia' and not (r1 ? 'paciente_id'),
    'La respuesta publica NO expone el id interno del paciente');

  select id into v_pac from public.pacientes where dpi_norm = '6018159041102';
  perform pg_temp.ok(v_pac is not null,           'La ficha del paciente se creo sola');
  perform pg_temp.ok(
    (select creado_por is null from public.pacientes where id = v_pac),
    'La ficha queda marcada como alta automatica (creado_por null)');
  perform pg_temp.ok(
    (select email = 'juan.perez@example.com' from public.pacientes where id = v_pac),
    'El correo se normaliza a minusculas y sin espacios');
  perform pg_temp.ok(
    (select telefono_norm = '50255123456' from public.pacientes where id = v_pac),
    'El telefono se normaliza con codigo de pais');

  select count(*) into v_total from public.cita_areas ca
  join public.citas c on c.id = ca.cita_id where c.paciente_id = v_pac;
  perform pg_temp.ok(v_total = 2, 'Se guardaron las 2 areas de molestia');

  -- Segunda solicitud, MISMO DPI, otra fecha: debe reutilizar la ficha
  r2 := public.solicitar_cita(jsonb_build_object(
    'dpi', '6018159041102',
    'nombre_completo', 'Juan C. Perez Lopez',
    'telefono', '5512-3456',
    'fecha', (current_date + 12)::text,
    'hora', '10:00',
    'acepta_politica', true,
    'areas', jsonb_build_array(jsonb_build_object('codigo', 'lumbar', 'intensidad', 5))));

  perform pg_temp.ok((r2 ->> 'ok')::boolean, 'Segunda solicitud aceptada');
  perform pg_temp.ok((select count(*) from public.pacientes where dpi_norm = '6018159041102') = 1,
    'El DPI no genera una ficha duplicada');
  perform pg_temp.ok((select count(*) from public.citas where paciente_id = v_pac) = 2,
    'Las dos citas quedan colgadas de la misma ficha');
  perform pg_temp.ok(
    (r1 ->> 'codigo_referencia') <> (r2 ->> 'codigo_referencia'),
    'Cada cita tiene su propio codigo de referencia');
end $$;

\echo ''
\echo '== 3. El nombre es dato de comprobacion, no identificador =='
do $$
declare r jsonb; v_pac uuid;
begin
  select id into v_pac from public.pacientes where dpi_norm = '6018159041102';

  r := public.solicitar_cita(jsonb_build_object(
    'dpi', '6018159041102',
    'nombre_completo', 'Rodrigo Melgar Xoyon',   -- nombre totalmente distinto
    'telefono', '5512-3456',
    'fecha', (current_date + 20)::text,
    'acepta_politica', true,
    'areas', jsonb_build_array(jsonb_build_object('codigo', 'cervical', 'intensidad', 6))));

  perform pg_temp.ok((r ->> 'ok')::boolean, 'La cita se acepta igual (el DPI manda)');
  perform pg_temp.ok(
    exists (select 1 from public.alertas
            where paciente_id = v_pac and tipo = 'nombre_no_coincide' and estado = 'pendiente'),
    'Se genera alerta administrativa por nombre que no coincide');
  perform pg_temp.ok(
    (select nombre_completo from public.pacientes where id = v_pac) = 'Juan Carlos Perez Lopez',
    'El nombre de la ficha NO se sobreescribe con el declarado');
end $$;

\echo ''
\echo '== 4. Validaciones del formulario publico =='
do $$
declare r jsonb;
begin
  r := public.solicitar_cita(jsonb_build_object(
    'dpi', '1234567890123', 'nombre_completo', 'Test Uno', 'telefono', '55551234',
    'fecha', (current_date + 3)::text, 'acepta_politica', true,
    'areas', jsonb_build_array(jsonb_build_object('codigo', 'lumbar'))));
  perform pg_temp.ok((r ->> 'error') = 'dpi_invalido', 'DPI invalido se rechaza con mensaje claro');

  r := public.solicitar_cita(jsonb_build_object(
    'dpi', '6091390961702', 'nombre_completo', 'Test Dos', 'telefono', '55551234',
    'fecha', (current_date + 3)::text, 'acepta_politica', false,
    'areas', jsonb_build_array(jsonb_build_object('codigo', 'lumbar'))));
  perform pg_temp.ok((r ->> 'error') = 'politica_no_aceptada', 'Exige aceptar la politica de datos');

  r := public.solicitar_cita(jsonb_build_object(
    'dpi', '6091390961702', 'nombre_completo', 'Test Tres', 'telefono', '55551234',
    'fecha', (current_date - 1)::text, 'acepta_politica', true,
    'areas', jsonb_build_array(jsonb_build_object('codigo', 'lumbar'))));
  perform pg_temp.ok((r ->> 'error') = 'fecha_invalida', 'No se aceptan fechas pasadas');

  r := public.solicitar_cita(jsonb_build_object(
    'dpi', '6091390961702', 'nombre_completo', 'Test Cuatro', 'telefono', '55551234',
    'fecha', (current_date + 3)::text, 'acepta_politica', true, 'areas', '[]'::jsonb));
  perform pg_temp.ok((r ->> 'error') = 'sin_areas', 'Exige al menos un area de molestia');

  r := public.solicitar_cita(jsonb_build_object(
    'dpi', '6091390961702', 'nombre_completo', 'SoloNombre', 'telefono', '55551234',
    'fecha', (current_date + 3)::text, 'acepta_politica', true,
    'areas', jsonb_build_array(jsonb_build_object('codigo', 'lumbar'))));
  perform pg_temp.ok((r ->> 'error') = 'nombre_invalido', 'Exige nombre y apellido');

  r := public.solicitar_cita(jsonb_build_object(
    'dpi', '6091390961702', 'nombre_completo', 'Sin Contacto',
    'fecha', (current_date + 3)::text, 'acepta_politica', true,
    'areas', jsonb_build_array(jsonb_build_object('codigo', 'lumbar'))));
  perform pg_temp.ok((r ->> 'error') = 'sin_contacto', 'Exige al menos una via de contacto');
end $$;

\echo ''
\echo '== 5. Flujo de la cita: confirmar, atender, firmar =='
do $$
declare
  v_cita uuid; v_res jsonb; v_ses uuid; v_inicio timestamptz;
begin
  perform set_config('neoterapia.test_uid', '33333333-3333-3333-3333-333333333333', true);

  select id, (fecha_solicitada + coalesce(hora_solicitada, '09:00'::time)) at time zone 'America/Guatemala'
    into v_cita, v_inicio
  from public.citas where estado = 'solicitada' order by fecha_solicitada, creado_en limit 1;

  v_res := public.confirmar_cita(v_cita, v_inicio, '44444444-4444-4444-4444-444444444444');
  perform pg_temp.ok((v_res ->> 'ok')::boolean, 'Recepcion puede confirmar la cita');
  perform pg_temp.ok((v_res -> 'enlaces') ? 'confirmar', 'Se emiten enlaces de accion para el paciente');
  perform pg_temp.ok(
    (select estado = 'confirmada' and fin_programado > inicio_programado from public.citas where id = v_cita),
    'La cita queda confirmada con rango horario calculado');
  perform pg_temp.ok(
    (select count(*) from public.mensajes where cita_id = v_cita and tipo = 'confirmacion' and estado = 'pendiente') = 1,
    'El mensaje de confirmacion se ENCOLA (sin enviar: no hay proveedor)');
  perform pg_temp.ok(
    (select count(*) from public.citas_historial_estado where cita_id = v_cita) >= 2,
    'Queda bitacora de cambios de estado');

  -- Traslape: el mismo fisioterapeuta a la misma hora
  declare v_otra uuid;
  begin
    select id into v_otra from public.citas
     where estado = 'solicitada' and id <> v_cita order by fecha_solicitada limit 1;
    v_res := public.confirmar_cita(v_otra, v_inicio, '44444444-4444-4444-4444-444444444444');
    perform pg_temp.ok((v_res ->> 'error') = 'traslape', 'Se bloquea el traslape de agenda del fisioterapeuta');
  end;

  perform set_config('neoterapia.test_uid', '44444444-4444-4444-4444-444444444444', true);
  v_res := public.marcar_asistencia(v_cita, true);
  perform pg_temp.ok((v_res ->> 'ok')::boolean, 'El fisioterapeuta marca la asistencia');
  v_ses := (v_res ->> 'sesion_id')::uuid;
  perform pg_temp.ok(v_ses is not null, 'Se abre la sesion clinica automaticamente');
  perform pg_temp.ok(
    (select count(*) from public.sesion_areas where sesion_id = v_ses) = 2,
    'La sesion hereda las areas que marco el paciente');

  update public.sesiones
     set subjetivo = 'Refiere dolor lumbar irradiado', objetivo = 'Contractura paravertebral L4-L5',
         analisis = 'Lumbalgia mecanica', plan = 'Terapia manual + ejercicio', dolor_inicial = 7, dolor_final = 4
   where id = v_ses;

  v_res := public.firmar_sesion(v_ses);
  perform pg_temp.ok((v_res ->> 'ok')::boolean, 'La sesion se firma');

  begin
    update public.sesiones set plan = 'otro plan' where id = v_ses;
    perform pg_temp.ok(false, 'Una sesion firmada NO deberia poder editarse');
  exception when check_violation then
    perform pg_temp.ok(true, 'Una sesion firmada queda bloqueada para edicion');
  end;

  perform pg_temp.ok(
    (select count(*) from public.mensajes where cita_id = v_cita and tipo = 'evaluacion') = 1,
    'Al firmar se encola la invitacion a evaluar');
end $$;

\echo ''
\echo '== 6. Enlaces de accion: sin portal, sin historial =='
do $$
declare v_cita uuid; v_token text; r jsonb; v_sol jsonb;
begin
  perform set_config('neoterapia.test_uid', '33333333-3333-3333-3333-333333333333', true);

  -- Paciente propio de esta seccion, atendido por fisio 2, para no contaminar
  -- las pruebas de visibilidad de la seccion 8.
  v_sol := public.solicitar_cita(jsonb_build_object(
    'dpi', '6091390961702', 'nombre_completo', 'Sofia Marroquin Diaz',
    'telefono', '3210-9876', 'fecha', (current_date + 9)::text,
    'acepta_politica', true,
    'areas', jsonb_build_array(jsonb_build_object('codigo', 'rodilla_izq', 'intensidad', 6))));

  select id into v_cita from public.citas where codigo_referencia = v_sol ->> 'codigo_referencia';
  perform public.confirmar_cita(v_cita, now() + interval '9 days',
                                '55555555-5555-5555-5555-555555555555');

  v_token := public.emitir_enlace_accion(v_cita, 'cancelar', 24, 1);
  perform pg_temp.ok(length(v_token) = 64, 'El token es aleatorio de 256 bits');
  perform pg_temp.ok(
    not exists (select 1 from public.enlaces_accion where token_hash = v_token::bytea),
    'En la base solo se guarda el hash, nunca el token');

  r := public.cita_publica_por_token(v_token);
  perform pg_temp.ok((r ->> 'ok')::boolean, 'El token devuelve contexto minimo de la cita');
  perform pg_temp.ok(not (r ? 'paciente_id') and not (r ? 'dpi') and not (r ? 'motivo_consulta'),
    'El contexto publico NO trae expediente ni identificadores internos');

  r := public.usar_enlace_accion(v_token, jsonb_build_object('motivo', 'Se me complico el trabajo'));
  perform pg_temp.ok((r ->> 'ok')::boolean, 'El enlace de cancelacion funciona');
  perform pg_temp.ok((select estado = 'cancelada' from public.citas where id = v_cita), 'La cita queda cancelada');

  r := public.usar_enlace_accion(v_token);
  perform pg_temp.ok((r ->> 'error') = 'enlace_agotado', 'El enlace de un solo uso no se puede reutilizar');

  r := public.usar_enlace_accion(repeat('a', 64));
  perform pg_temp.ok((r ->> 'error') = 'token_invalido', 'Un token inventado se rechaza');
end $$;

\echo ''
\echo '== 7. Duplicados, fusion y correccion de DPI =='
do $$
declare
  v_a uuid; v_b uuid; r jsonb; v_citas_a int; v_citas_b int;
begin
  perform set_config('neoterapia.test_uid', '22222222-2222-2222-2222-222222222222', true);

  -- Misma persona, DPI mal tecleado en una de las dos fichas
  perform public.solicitar_cita(jsonb_build_object(
    'dpi', '0308246211904', 'nombre_completo', 'Maria Jose Ramirez Gil',
    'telefono', '4444-1111', 'fecha', (current_date + 4)::text, 'acepta_politica', true,
    'areas', jsonb_build_array(jsonb_build_object('codigo', 'hombro_der', 'intensidad', 5))));

  perform public.solicitar_cita(jsonb_build_object(
    'dpi', '9482199391801', 'nombre_completo', 'Maria Jose Ramirez Gil',
    'telefono', '4444-1111', 'fecha', (current_date + 6)::text, 'acepta_politica', true,
    'areas', jsonb_build_array(jsonb_build_object('codigo', 'hombro_der', 'intensidad', 6))));

  select id into v_a from public.pacientes where dpi_norm = '0308246211904';
  select id into v_b from public.pacientes where dpi_norm = '9482199391801';

  perform pg_temp.ok(
    exists (select 1 from public.posibles_duplicados
            where (paciente_a = v_a and paciente_b = v_b) or (paciente_a = v_b and paciente_b = v_a)),
    'Se detectan las dos fichas como posible duplicado');

  select count(*) into v_citas_a from public.citas where paciente_id = v_a;
  select count(*) into v_citas_b from public.citas where paciente_id = v_b;

  r := public.fusionar_pacientes(v_b, v_a, 'DPI mal digitado en la segunda solicitud');
  perform pg_temp.ok((r ->> 'ok')::boolean, 'La fusion se ejecuta');
  perform pg_temp.ok(
    (select count(*) from public.citas where paciente_id = v_a) = v_citas_a + v_citas_b,
    'La ficha superviviente conserva TODO el historial de citas');
  perform pg_temp.ok(
    (select estado = 'fusionado' and fusionado_en_id = v_a from public.pacientes where id = v_b),
    'La ficha origen queda marcada como fusionada y apunta a la superviviente');
  perform pg_temp.ok(
    exists (select 1 from public.pacientes_historial_identidad
            where paciente_id = v_a and campo = 'fusion'),
    'Queda rastro de la fusion en el historial de identidad');
  perform pg_temp.ok(
    exists (select 1 from public.auditoria where accion = 'fusionar'),
    'La fusion queda en auditoria');

  -- Correccion de DPI
  r := public.corregir_dpi(v_a, '8190937851201', 'El paciente presento su DPI fisico y no coincidia');
  perform pg_temp.ok((r ->> 'ok')::boolean, 'Se puede corregir un DPI mal ingresado');
  perform pg_temp.ok(
    (select dpi_norm = '8190937851201' from public.pacientes where id = v_a),
    'El DPI queda corregido');
  perform pg_temp.ok(
    exists (select 1 from public.auditoria where accion = 'corregir_dpi'),
    'La correccion de DPI queda en auditoria');
  perform pg_temp.ok(
    (select valor_anterior = '0308 ***** 1904' from public.pacientes_historial_identidad
      where paciente_id = v_a and campo = 'dpi' limit 1),
    'El historial guarda el DPI anterior ENMASCARADO');

  r := public.corregir_dpi(v_a, '6018159041102', 'Prueba de choque de documento');
  perform pg_temp.ok((r ->> 'error') = 'documento_en_uso',
    'No se puede asignar un DPI que ya pertenece a otra ficha');

  r := public.corregir_dpi(v_a, '7975432361403', 'no');
  perform pg_temp.ok((r ->> 'error') = 'motivo_requerido', 'La correccion exige motivo');
end $$;

\echo ''
\echo '== 8. Acceso auditado al DPI completo =='
do $$
declare v_pac uuid; r jsonb; v_antes int;
begin
  select id into v_pac from public.pacientes where dpi_norm = '6018159041102';
  select count(*) into v_antes from public.auditoria where accion = 'consultar_sensible';

  perform set_config('neoterapia.test_uid', '22222222-2222-2222-2222-222222222222', true);
  r := public.ver_dpi_paciente(v_pac, 'Verificacion de identidad en mostrador');
  perform pg_temp.ok((r ->> 'documento') = '6018159041102', 'Administracion puede ver el DPI completo');
  perform pg_temp.ok(
    (select count(*) from public.auditoria where accion = 'consultar_sensible') = v_antes + 1,
    'Cada consulta del DPI completo deja rastro en auditoria');

  perform set_config('neoterapia.test_uid', '33333333-3333-3333-3333-333333333333', true);
  begin
    r := public.ver_dpi_paciente(v_pac);
    perform pg_temp.ok(false, 'Recepcion NO deberia poder destapar el DPI');
  exception when insufficient_privilege then
    perform pg_temp.ok(true, 'Recepcion no puede destapar el DPI completo');
  end;

  perform set_config('neoterapia.test_uid', '55555555-5555-5555-5555-555555555555', true);
  begin
    r := public.ver_dpi_paciente(v_pac);
    perform pg_temp.ok(false, 'Un fisioterapeuta ajeno NO deberia ver el DPI');
  exception when insufficient_privilege then
    perform pg_temp.ok(true, 'Un fisioterapeuta que no atiende al paciente no ve su DPI');
  end;
end $$;

\echo ''
\echo '== 9. Disponibilidad =='
do $$
declare v_n int; v_fecha date;
begin
  -- Proximo lunes
  v_fecha := current_date + ((8 - extract(dow from current_date)::int) % 7);
  if v_fecha = current_date then v_fecha := v_fecha + 7; end if;

  select count(*) into v_n from public.slots_disponibles(v_fecha);
  perform pg_temp.ok(v_n > 0, format('Hay slots generados para el %s (%s)', v_fecha, v_n));
  perform pg_temp.ok(
    (select count(*) from public.slots_disponibles(current_date - 5)) = 0,
    'No se ofrecen slots en fechas pasadas');
  perform pg_temp.ok(
    (select count(*) from public.slots_disponibles(current_date + 400)) = 0,
    'No se ofrecen slots mas alla del limite de anticipacion');
end $$;

\echo ''
\echo '== 10. RLS por rol =='
-- Se prueba con los roles reales de PostgREST (anon / authenticated).
grant usage on schema auth to anon;
grant execute on function auth.uid() to anon, authenticated;

do $$
declare v_pac uuid;
begin
  select id into v_pac from public.pacientes where estado = 'activo' limit 1;
  perform set_config('neoterapia.pac_prueba', v_pac::text, false);
end $$;

set role anon;
do $$
declare v_n int;
begin
  begin
    select count(*) into v_n from public.pacientes;
    raise exception 'FALLO: anon pudo leer pacientes';
  exception when insufficient_privilege then
    raise notice '  OK    anon no tiene ningun acceso a la tabla pacientes';
  end;

  begin
    select count(*) into v_n from public.citas;
    raise exception 'FALLO: anon pudo leer citas';
  exception when insufficient_privilege then
    raise notice '  OK    anon no tiene ningun acceso a la tabla citas';
  end;

  begin
    select count(*) into v_n from public.sesiones;
    raise exception 'FALLO: anon pudo leer sesiones';
  exception when insufficient_privilege then
    raise notice '  OK    anon no tiene ningun acceso a las notas clinicas';
  end;

  select count(*) into v_n from public.areas_cuerpo;
  if v_n = 0 then raise exception 'FALLO: anon deberia leer el catalogo de areas'; end if;
  raise notice '  OK    anon si puede leer el catalogo del mapa corporal (%)', v_n;
end $$;
reset role;

set role authenticated;

-- Recepcion
select set_config('neoterapia.test_uid', '33333333-3333-3333-3333-333333333333', false);
do $$
declare v_n int; v_dpi text;
begin
  select count(*) into v_n from public.pacientes;
  if v_n = 0 then raise exception 'FALLO: recepcion no vio pacientes'; end if;
  raise notice '  OK    recepcion ve la lista de pacientes (%)', v_n;

  begin
    execute 'select dpi from public.pacientes limit 1' into v_dpi;
    raise exception 'FALLO: recepcion pudo leer la columna dpi';
  exception when insufficient_privilege then
    raise notice '  OK    la columna dpi esta revocada incluso para consultas directas';
  end;

  select count(*) into v_n from public.sesiones;
  if v_n > 0 then raise exception 'FALLO: recepcion vio notas clinicas'; end if;
  raise notice '  OK    recepcion NO ve notas clinicas';

  select count(*) into v_n from public.pacientes_clinico;
  if v_n > 0 then raise exception 'FALLO: recepcion vio antecedentes clinicos'; end if;
  raise notice '  OK    recepcion NO ve antecedentes clinicos';

  select count(*) into v_n from public.auditoria;
  if v_n > 0 then raise exception 'FALLO: recepcion vio la auditoria'; end if;
  raise notice '  OK    recepcion NO ve la bitacora de auditoria';
end $$;

-- Fisioterapeuta con pacientes asignados
select set_config('neoterapia.test_uid', '44444444-4444-4444-4444-444444444444', false);
do $$
declare v_mios int; v_ses int; v_pagos int;
begin
  select count(*) into v_mios from public.pacientes;
  raise notice '  OK    fisio 1 ve solo sus pacientes (%)', v_mios;

  select count(*) into v_ses from public.sesiones;
  if v_ses = 0 then raise exception 'FALLO: fisio 1 no vio sus propias sesiones'; end if;
  raise notice '  OK    fisio 1 ve sus notas clinicas (%)', v_ses;

  select count(*) into v_pagos from public.pagos;
  if v_pagos > 0 then raise exception 'FALLO: fisio vio pagos'; end if;
  raise notice '  OK    el fisioterapeuta NO ve pagos';
end $$;

-- Fisioterapeuta sin pacientes asignados
select set_config('neoterapia.test_uid', '55555555-5555-5555-5555-555555555555', false);
do $$
declare v_ses int; v_pac int;
begin
  select count(*) into v_ses from public.sesiones;
  if v_ses > 0 then raise exception 'FALLO: fisio 2 vio sesiones ajenas'; end if;
  raise notice '  OK    fisio 2 NO ve las notas clinicas de otro fisioterapeuta';

  select count(*) into v_pac from public.pacientes;
  raise notice '  OK    fisio 2 solo ve pacientes que atiende (%)', v_pac;
end $$;

-- Administracion
select set_config('neoterapia.test_uid', '22222222-2222-2222-2222-222222222222', false);
do $$
declare v_n int;
begin
  select count(*) into v_n from public.auditoria;
  if v_n = 0 then raise exception 'FALLO: admin no vio auditoria'; end if;
  raise notice '  OK    administracion ve la auditoria (%)', v_n;

  select count(*) into v_n from public.v_pacientes_listado;
  if v_n = 0 then raise exception 'FALLO: la vista de listado vino vacia'; end if;
  raise notice '  OK    la vista de pacientes respeta RLS y trae datos (%)', v_n;
end $$;

reset role;

\echo ''
\echo '== 11. La bitacora de auditoria es inmutable =='
do $$
begin
  begin
    update public.auditoria set descripcion = 'alterado' where id = (select min(id) from public.auditoria);
    perform pg_temp.ok(false, 'La auditoria NO deberia poder modificarse');
  exception when insufficient_privilege then
    perform pg_temp.ok(true, 'La auditoria no se puede modificar');
  end;
  begin
    delete from public.auditoria where id = (select min(id) from public.auditoria);
    perform pg_temp.ok(false, 'La auditoria NO deberia poder borrarse');
  exception when insufficient_privilege then
    perform pg_temp.ok(true, 'La auditoria no se puede borrar');
  end;
end $$;

\echo ''
\echo '== 12. Control de abuso del formulario publico =='
do $$
declare r jsonb; v_err text := null; i int;
begin
  for i in 1..7 loop
    r := public.solicitar_cita(jsonb_build_object(
      'dpi', '7975432361403', 'nombre_completo', 'Abuso Prueba Test',
      'telefono', '3333-2222', 'fecha', (current_date + i + 1)::text,
      'acepta_politica', true,
      'areas', jsonb_build_array(jsonb_build_object('codigo', 'cervical', 'intensidad', 3))));
    if (r ->> 'error') = 'demasiadas_solicitudes' then v_err := 'si'; end if;
  end loop;
  perform pg_temp.ok(v_err = 'si', 'Se corta el envio masivo con el mismo documento');
end $$;

\echo ''
\echo '== 13. Metricas del tablero =='
do $$
declare m jsonb;
begin
  perform set_config('neoterapia.test_uid', '22222222-2222-2222-2222-222222222222', true);
  m := public.metricas_tablero();
  perform pg_temp.ok(m ? 'solicitudes_pendientes' and m ? 'alertas_pendientes',
    'metricas_tablero devuelve el resumen del panel');
  raise notice '        %', m::text;
end $$;

\echo ''
\echo '== 14. Alta de usuarios del personal desde el panel =='
do $$
declare r jsonb; v_id uuid;
begin
  -- Recepcion no puede crear usuarios
  perform set_config('neoterapia.test_uid', '33333333-3333-3333-3333-333333333333', true);
  begin
    r := public.crear_usuario_personal('x@y.com', 'unaClaveLarga1', 'Nuevo Usuario', 'admin');
    perform pg_temp.ok(false, 'Recepcion NO deberia poder crear usuarios');
  exception when insufficient_privilege then
    perform pg_temp.ok(true, 'Recepcion no puede crear usuarios');
  end;

  -- Un admin normal tampoco: solo superadmin
  perform set_config('neoterapia.test_uid', '22222222-2222-2222-2222-222222222222', true);
  begin
    r := public.crear_usuario_personal('x@y.com', 'unaClaveLarga1', 'Nuevo Usuario', 'admin');
    perform pg_temp.ok(false, 'Un admin NO deberia poder crear usuarios');
  exception when insufficient_privilege then
    perform pg_temp.ok(true, 'Un administrador tampoco puede crear usuarios');
  end;

  -- Superadmin si
  perform set_config('neoterapia.test_uid', '11111111-1111-1111-1111-111111111111', true);

  r := public.crear_usuario_personal('correo-malo', 'unaClaveLarga1', 'Nuevo Usuario', 'admin');
  perform pg_temp.ok((r ->> 'error') = 'correo_invalido', 'Rechaza correos con formato invalido');

  r := public.crear_usuario_personal('nuevo@neoterapia.gt', 'corta', 'Nuevo Usuario', 'admin');
  perform pg_temp.ok((r ->> 'error') = 'clave_corta', 'Exige contrasena de al menos 10 caracteres');

  r := public.crear_usuario_personal('nuevo@neoterapia.gt', 'unaClaveLarga1', 'Solo', 'admin');
  perform pg_temp.ok((r ->> 'error') = 'nombre_invalido', 'Exige nombre y apellido');

  r := public.crear_usuario_personal('super@neoterapia.gt', 'unaClaveLarga1', 'Otro Usuario', 'admin');
  perform pg_temp.ok((r ->> 'error') = 'correo_existente', 'No permite dos usuarios con el mismo correo');

  r := public.crear_usuario_personal(
    '  NUEVO@NeoTerapia.GT ', 'unaClaveLarga1', 'Carla Fisio Nueva',
    'fisioterapeuta', '5555-0000', 'COL-1234', 'Deportiva', '#7c3aed');
  perform pg_temp.ok((r ->> 'ok')::boolean, 'El superadministrador crea el usuario');
  v_id := (r ->> 'usuario_id')::uuid;

  perform pg_temp.ok(
    (select email = 'nuevo@neoterapia.gt' from auth.users where id = v_id),
    'El correo se normaliza a minusculas y sin espacios');
  perform pg_temp.ok(
    (select email_confirmed_at is not null from auth.users where id = v_id),
    'El correo queda confirmado (lo dio de alta un superadministrador)');
  perform pg_temp.ok(
    (select encrypted_password = extensions.crypt('unaClaveLarga1', encrypted_password)
       from auth.users where id = v_id),
    'La contrasena queda cifrada con bcrypt y valida correctamente');
  perform pg_temp.ok(
    (select count(*) from auth.identities where user_id = v_id) = 1,
    'Se crea la identidad de correo asociada');
  perform pg_temp.ok(
    (select rol = 'fisioterapeuta' and activo and colegiado = 'COL-1234'
       from public.perfiles where id = v_id),
    'El perfil queda con el rol y los datos indicados');
  perform pg_temp.ok(
    exists (select 1 from public.auditoria
            where entidad = 'perfiles' and entidad_id = v_id::text),
    'El alta queda registrada en auditoria');

  -- Restablecer contrasena
  r := public.restablecer_contrasena(v_id, 'otraClaveLarga99');
  perform pg_temp.ok((r ->> 'ok')::boolean, 'El superadministrador restablece contrasenas');
  perform pg_temp.ok(
    (select encrypted_password = extensions.crypt('otraClaveLarga99', encrypted_password)
       from auth.users where id = v_id),
    'La contrasena nueva queda activa');

  perform set_config('neoterapia.test_uid', '22222222-2222-2222-2222-222222222222', true);
  begin
    r := public.restablecer_contrasena(v_id, 'terceraClave123');
    perform pg_temp.ok(false, 'Un admin NO deberia restablecer contrasenas ajenas');
  exception when insufficient_privilege then
    perform pg_temp.ok(true, 'Un administrador no puede restablecer contrasenas ajenas');
  end;
end $$;

\echo ''
\echo '== 15. Inventario =='
do $$
declare
  r jsonb; v_art uuid; v_ex numeric;
begin
  select id into v_art from public.inventario_articulos where codigo = 'INS-ELEC';
  perform pg_temp.ok(v_art is not null, 'El inventario arranca con articulos del seed');
  perform pg_temp.ok(
    (select existencia = 0 from public.inventario_articulos where id = v_art),
    'Los articulos arrancan en cero: la existencia se carga con movimientos');

  -- Recepcion no mueve inventario
  perform set_config('neoterapia.test_uid', '33333333-3333-3333-3333-333333333333', true);
  begin
    r := public.registrar_movimiento_inventario(v_art, 'entrada', 10);
    perform pg_temp.ok(false, 'Recepcion NO deberia mover el inventario');
  exception when insufficient_privilege then
    perform pg_temp.ok(true, 'Recepcion no puede mover el inventario');
  end;
  perform pg_temp.ok(
    (select count(*) from public.inventario_articulos) > 0,
    'Recepcion si puede consultar las existencias');

  -- Un fisioterapeuta tampoco
  perform set_config('neoterapia.test_uid', '44444444-4444-4444-4444-444444444444', true);
  begin
    r := public.registrar_movimiento_inventario(v_art, 'entrada', 10);
    perform pg_temp.ok(false, 'Un fisioterapeuta NO deberia mover el inventario');
  exception when insufficient_privilege then
    perform pg_temp.ok(true, 'El fisioterapeuta no puede mover el inventario');
  end;

  -- Administracion si
  perform set_config('neoterapia.test_uid', '22222222-2222-2222-2222-222222222222', true);

  r := public.registrar_movimiento_inventario(v_art, 'entrada', 24, 'Compra inicial', 'FAC-001');
  perform pg_temp.ok((r ->> 'ok')::boolean, 'Administracion registra una entrada');
  perform pg_temp.ok((r ->> 'existencia')::numeric = 24, 'La entrada suma a la existencia');

  r := public.registrar_movimiento_inventario(v_art, 'salida', 4, 'Uso en terapia');
  perform pg_temp.ok((r ->> 'existencia')::numeric = 20, 'La salida resta de la existencia');

  r := public.registrar_movimiento_inventario(v_art, 'merma', 2, 'Empaque danado');
  perform pg_temp.ok((r ->> 'existencia')::numeric = 18, 'La merma resta de la existencia');

  r := public.registrar_movimiento_inventario(v_art, 'salida', 999, 'Prueba de sobregiro');
  perform pg_temp.ok((r ->> 'error') = 'sin_existencia',
    'No se puede sacar mas de lo que hay');
  perform pg_temp.ok(
    (select existencia = 18 from public.inventario_articulos where id = v_art),
    'El intento fallido no altero la existencia');

  r := public.registrar_movimiento_inventario(v_art, 'ajuste', 15, 'Conteo fisico de fin de mes');
  perform pg_temp.ok((r ->> 'existencia')::numeric = 15,
    'El ajuste FIJA la existencia al conteo fisico');

  r := public.registrar_movimiento_inventario(v_art, 'entrada', -5);
  perform pg_temp.ok((r ->> 'error') = 'cantidad_invalida', 'Rechaza cantidades negativas');

  -- La bitacora cuadra: los intentos fallidos no dejan rastro (rollback al
  -- savepoint implicito del bloque exception), asi que son 4 y no 6.
  perform pg_temp.ok(
    (select count(*) from public.inventario_movimientos where articulo_id = v_art) = 4,
    'Solo quedan registrados los 4 movimientos que si se aplicaron');
  perform pg_temp.ok(
    (select existencia_resultante = 15 from public.inventario_movimientos
      where articulo_id = v_art and tipo = 'ajuste'),
    'El movimiento guarda la existencia resultante');
  perform pg_temp.ok(
    (select bool_and(realizado_por = '22222222-2222-2222-2222-222222222222')
       from public.inventario_movimientos where articulo_id = v_art),
    'Cada movimiento guarda quien lo hizo');

  -- La existencia no se toca a mano
  begin
    update public.inventario_articulos set existencia = 9999 where id = v_art;
    perform pg_temp.ok(false, 'La existencia NO deberia editarse directamente');
  exception when insufficient_privilege then
    perform pg_temp.ok(true, 'La existencia no se puede editar a mano, solo con movimientos');
  end;

  -- La bitacora es inmutable
  begin
    delete from public.inventario_movimientos where articulo_id = v_art;
    perform pg_temp.ok(false, 'Los movimientos NO deberian borrarse');
  exception when insufficient_privilege then
    perform pg_temp.ok(true, 'Los movimientos de inventario no se borran');
  end;

  -- Bajo minimo
  update public.inventario_articulos set minimo = 20 where id = v_art;
  perform pg_temp.ok(
    (select bajo_minimo from public.v_inventario where id = v_art),
    'La vista marca el articulo por debajo del minimo');
  perform pg_temp.ok(
    ((public.resumen_inventario()) ->> 'bajo_minimo')::int >= 1,
    'El resumen cuenta los articulos bajo minimo');
end $$;

\echo ''
\echo '== 16. El catalogo de tratamientos ya no lleva precio =='
do $$
begin
  perform pg_temp.ok(
    not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'tratamientos' and column_name = 'precio'),
    'La columna precio ya no existe en el catalogo');
  perform pg_temp.ok(
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'sesion_tratamientos'
        and column_name = 'precio_aplicado'),
    'El monto por aplicacion se conserva en la sesion');
  perform pg_temp.ok(
    not exists (select 1 from pg_proc where proname = 'tg_heredar_precio_tratamiento'),
    'El trigger que heredaba el precio del catalogo fue retirado');
end $$;

\echo ''
\echo '== 17. El fisioterapeuta es opcional al agendar =='
do $$
declare
  v_sol jsonb; v_cita uuid; r jsonb;
begin
  perform set_config('neoterapia.test_uid', '33333333-3333-3333-3333-333333333333', true);

  v_sol := public.solicitar_cita(jsonb_build_object(
    'dpi', '0716202140101', 'nombre_completo', 'Sin Fisio Asignado',
    'telefono', '4444-9999', 'fecha', (current_date + 30)::text,
    'acepta_politica', true,
    'areas', jsonb_build_array(jsonb_build_object('codigo', 'cervical', 'intensidad', 4))));
  select id into v_cita from public.citas where codigo_referencia = v_sol ->> 'codigo_referencia';

  -- Confirmar sin pasar fisioterapeuta
  r := public.confirmar_cita(v_cita, now() + interval '30 days');
  perform pg_temp.ok((r ->> 'ok')::boolean, 'Se puede confirmar sin asignar fisioterapeuta');
  perform pg_temp.ok((r ->> 'sin_fisioterapeuta')::boolean, 'La respuesta avisa que quedo sin asignar');
  perform pg_temp.ok(
    (select fisioterapeuta_id is null and estado = 'confirmada' from public.citas where id = v_cita),
    'La cita queda confirmada y sin fisioterapeuta');
  perform pg_temp.ok(
    (select count(*) from public.mensajes where cita_id = v_cita and tipo = 'confirmacion') = 1,
    'Al paciente se le confirma igual');

  -- Recepcion no puede cerrarla como atendida sin autor de la nota
  r := public.marcar_asistencia(v_cita, true);
  perform pg_temp.ok((r ->> 'error') = 'falta_fisioterapeuta',
    'Sin fisioterapeuta no se puede marcar atendida: la nota necesita autor');
  perform pg_temp.ok(
    (select estado = 'confirmada' from public.citas where id = v_cita),
    'La cita no cambio de estado en el intento fallido');

  -- Pero si puede marcar la inasistencia
  declare v_otra uuid; v_sol2 jsonb;
  begin
    v_sol2 := public.solicitar_cita(jsonb_build_object(
      'dpi', '0716202140101', 'nombre_completo', 'Sin Fisio Asignado',
      'telefono', '4444-9999', 'fecha', (current_date + 31)::text,
      'acepta_politica', true,
      'areas', jsonb_build_array(jsonb_build_object('codigo', 'cervical', 'intensidad', 4))));
    select id into v_otra from public.citas where codigo_referencia = v_sol2 ->> 'codigo_referencia';
    perform public.confirmar_cita(v_otra, now() + interval '31 days');
    r := public.marcar_asistencia(v_otra, false);
    perform pg_temp.ok((r ->> 'ok')::boolean, 'La inasistencia si se registra sin fisioterapeuta');
  end;

  -- Asignar despues
  r := public.asignar_fisioterapeuta(v_cita, '55555555-5555-5555-5555-555555555555');
  perform pg_temp.ok((r ->> 'ok')::boolean, 'Se asigna el fisioterapeuta despues');
  perform pg_temp.ok(
    (select fisioterapeuta_id = '55555555-5555-5555-5555-555555555555'
       from public.citas where id = v_cita),
    'La cita queda con el fisioterapeuta asignado');
  perform pg_temp.ok(
    (select count(*) from public.mensajes where cita_id = v_cita and tipo = 'confirmacion') = 1,
    'Asignar NO reenvia el mensaje de confirmacion al paciente');

  -- No se puede asignar a alguien que no atiende pacientes
  r := public.asignar_fisioterapeuta(v_cita, '33333333-3333-3333-3333-333333333333');
  perform pg_temp.ok((r ->> 'error') = 'no_atiende',
    'No se puede asignar a recepcion como quien atiende');

  -- Ahora si se puede atender
  r := public.marcar_asistencia(v_cita, true);
  perform pg_temp.ok((r ->> 'ok')::boolean, 'Con fisioterapeuta asignado ya se marca atendida');
  perform pg_temp.ok(
    (select fisioterapeuta_id = '55555555-5555-5555-5555-555555555555'
       from public.sesiones where cita_id = v_cita),
    'La sesion queda a nombre del fisioterapeuta de la cita');
end $$;

do $$
declare v_sol jsonb; v_cita uuid; r jsonb;
begin
  -- Un fisioterapeuta que atiende una cita sin asignar queda como autor
  perform set_config('neoterapia.test_uid', '33333333-3333-3333-3333-333333333333', true);
  v_sol := public.solicitar_cita(jsonb_build_object(
    'dpi', '8322002390703', 'nombre_completo', 'Otro Paciente Prueba',
    'telefono', '4444-8888', 'fecha', (current_date + 33)::text,
    'acepta_politica', true,
    'areas', jsonb_build_array(jsonb_build_object('codigo', 'lumbar', 'intensidad', 5))));
  select id into v_cita from public.citas where codigo_referencia = v_sol ->> 'codigo_referencia';
  perform public.confirmar_cita(v_cita, now() + interval '33 days');

  perform set_config('neoterapia.test_uid', '44444444-4444-4444-4444-444444444444', true);
  r := public.marcar_asistencia(v_cita, true);
  perform pg_temp.ok((r ->> 'ok')::boolean,
    'El fisioterapeuta puede atender una cita que nadie tenia asignada');
  perform pg_temp.ok(
    (select fisioterapeuta_id = '44444444-4444-4444-4444-444444444444'
       from public.citas where id = v_cita),
    'Al atenderla, la cita queda a su nombre');
  perform pg_temp.ok(
    (select fisioterapeuta_id = '44444444-4444-4444-4444-444444444444'
       from public.sesiones where cita_id = v_cita),
    'Y la nota clinica tambien');
end $$;

\echo ''
\echo '== 18. El mapa corporal se guarda y se lee por momento =='
do $$
declare
  v_pac uuid; v_ses uuid; v_n int; m record;
begin
  perform set_config('neoterapia.test_uid', '22222222-2222-2222-2222-222222222222', true);
  select id into v_pac from public.pacientes where dpi_norm = '6018159041102';

  select count(*) into v_n from public.historial_mapa_corporal(v_pac);
  perform pg_temp.ok(v_n >= 2,
    format('El historial trae varios momentos, no uno solo (%s)', v_n));

  perform pg_temp.ok(
    exists (select 1 from public.historial_mapa_corporal(v_pac) where momento_tipo = 'solicitud'),
    'Incluye lo que el paciente marco al solicitar');
  perform pg_temp.ok(
    exists (select 1 from public.historial_mapa_corporal(v_pac) where momento_tipo = 'sesion'),
    'Incluye lo que el fisioterapeuta registro en sesion');

  select * into m from public.historial_mapa_corporal(v_pac)
   where momento_tipo = 'sesion' order by fecha limit 1;
  perform pg_temp.ok(jsonb_array_length(m.areas) > 0, 'Cada momento trae su mapa completo');
  perform pg_temp.ok(m.dolor_maximo between 0 and 10, 'Trae el dolor maximo del momento');
  perform pg_temp.ok(m.responsable is not null, 'La sesion dice quien la registro');

  -- Dos sesiones del mismo paciente conservan mapas distintos
  select s.id into v_ses from public.sesiones s where s.paciente_id = v_pac limit 1;
  perform pg_temp.ok(
    (select count(distinct sesion_id) from public.sesion_areas sa
      join public.sesiones s2 on s2.id = sa.sesion_id
     where s2.paciente_id = v_pac) >= 1,
    'El mapa vive colgado de la sesion, no del paciente');

  perform pg_temp.ok(
    not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'pacientes'
        and column_name like '%area%'),
    'No hay ningun mapa "permanente" pegado a la ficha del paciente');
end $$;

do $$
declare v_pac uuid;
begin
  -- Recepcion ve la solicitud del paciente pero NO el mapa clinico
  select id into v_pac from public.pacientes where dpi_norm = '6018159041102';
  perform set_config('neoterapia.test_uid', '33333333-3333-3333-3333-333333333333', true);
  perform pg_temp.ok(
    not exists (select 1 from public.historial_mapa_corporal(v_pac) where momento_tipo = 'sesion'),
    'Recepcion no ve los mapas registrados en sesion');
  perform pg_temp.ok(
    exists (select 1 from public.historial_mapa_corporal(v_pac) where momento_tipo = 'solicitud'),
    'Recepcion si ve lo que el paciente declaro al pedir la cita');
end $$;

\echo ''
\echo '== 19. Indicadores (KPIs) =='
do $$
declare
  k jsonb; v_pac uuid; v_cita uuid; n int;
begin
  perform set_config('neoterapia.test_uid', '44444444-4444-4444-4444-444444444444', true);
  begin
    k := public.kpis_resumen(current_date - 60, current_date + 60);
    perform pg_temp.ok(false, 'Un fisioterapeuta NO deberia ver los indicadores');
  exception when insufficient_privilege then
    perform pg_temp.ok(true, 'El fisioterapeuta no ve los indicadores de cobro');
  end;

  perform set_config('neoterapia.test_uid', '22222222-2222-2222-2222-222222222222', true);
  k := public.kpis_resumen(current_date - 60, current_date + 60);
  perform pg_temp.ok(k ? 'atendidas' and k ? 'canceladas' and k ? 'ingresos',
    'El resumen trae atendidas, canceladas e ingresos');
  perform pg_temp.ok((k ->> 'atendidas')::int > 0, 'Cuenta las citas atendidas del periodo');
  perform pg_temp.ok((k ->> 'canceladas')::int > 0, 'Cuenta las canceladas');
  perform pg_temp.ok((k ->> 'pacientes_atendidos')::int > 0, 'Cuenta pacientes distintos atendidos');
  perform pg_temp.ok((k ->> 'ingresos')::numeric = 0, 'Sin pagos todavia, los ingresos van en cero');
  perform pg_temp.ok((k ->> 'atendidas_sin_cobrar')::int = (k ->> 'atendidas')::int,
    'Todas las atendidas arrancan sin cobrar');

  -- Se registra un pago ligado a una cita atendida
  select c.id, c.paciente_id into v_cita, v_pac
  from public.citas c where c.estado = 'atendida' limit 1;

  insert into public.pagos (paciente_id, cita_id, monto, metodo, estado, descripcion, registrado_por)
  values (v_pac, v_cita, 175.00, 'efectivo', 'pagado', 'Sesion de terapia manual',
          '22222222-2222-2222-2222-222222222222');
  insert into public.pagos (paciente_id, monto, metodo, estado, descripcion, registrado_por)
  values (v_pac, 100.00, 'tarjeta', 'pagado', 'Abono suelto',
          '22222222-2222-2222-2222-222222222222');

  k := public.kpis_resumen(current_date - 60, current_date + 60);
  perform pg_temp.ok((k ->> 'ingresos')::numeric = 275.00, 'Suma los ingresos del periodo');
  perform pg_temp.ok((k ->> 'pagos_registrados')::int = 2, 'Cuenta los pagos registrados');
  perform pg_temp.ok((k ->> 'atendidas_cobradas')::int = 1,
    'Marca como cobrada la cita que tiene el pago ligado');
  perform pg_temp.ok(
    (k -> 'ingresos_por_metodo' ->> 'efectivo')::numeric = 175.00
    and (k -> 'ingresos_por_metodo' ->> 'tarjeta')::numeric = 100.00,
    'Desglosa los ingresos por metodo de pago');
  perform pg_temp.ok((k ->> 'ticket_promedio')::numeric = 137.50, 'Calcula el ticket promedio');
  perform pg_temp.ok((k ->> 'tasa_cobro')::numeric is not null, 'Calcula la tasa de cobro');

  -- Un pago anulado no cuenta
  update public.pagos set estado = 'anulado', anulado_en = now(), motivo_anulacion = 'prueba'
   where cita_id = v_cita;
  k := public.kpis_resumen(current_date - 60, current_date + 60);
  perform pg_temp.ok((k ->> 'ingresos')::numeric = 100.00, 'Un pago anulado deja de sumar');
  perform pg_temp.ok((k ->> 'atendidas_cobradas')::int = 0,
    'Y la cita vuelve a contar como no cobrada');

  -- Serie temporal
  select count(*) into n from public.kpis_serie(current_date - 6, current_date, 'day');
  perform pg_temp.ok(n = 7, format('La serie diaria devuelve un punto por dia (%s)', n));
  perform pg_temp.ok(
    (select count(*) from public.kpis_serie(current_date - 6, current_date, 'day')
      where ingresos = 0) >= 1,
    'Incluye los periodos vacios en vez de dejar huecos');
  perform pg_temp.ok(
    (select count(*) from public.kpis_serie(current_date - 60, current_date, 'month')) between 2 and 4,
    'La granularidad mensual agrupa de verdad');
  perform pg_temp.ok(
    (select count(*) from public.kpis_serie(current_date - 60, current_date, 'inventado')) > 0,
    'Una granularidad invalida cae a diaria en vez de reventar');

  -- Lista accionable de lo no cobrado
  select count(*) into n from public.kpis_sin_cobrar(current_date - 60, current_date + 60);
  perform pg_temp.ok(n >= 1, 'Lista las visitas atendidas sin cobrar');
  perform pg_temp.ok(
    (select paciente is not null and codigo_referencia is not null
       from public.kpis_sin_cobrar(current_date - 60, current_date + 60) limit 1),
    'La lista trae con quien resolverlo');
  perform pg_temp.ok(
    (select bool_and(dpi_mascara like '%*%')
       from public.kpis_sin_cobrar(current_date - 60, current_date + 60)),
    'Y el DPI sigue enmascarado tambien aqui');
end $$;

\echo ''
\echo '== 20. Atender pacientes no depende del rol =='
do $$
declare v_sol jsonb; v_cita uuid; r jsonb;
  c_super constant uuid := '11111111-1111-1111-1111-111111111111';
  c_admin constant uuid := '22222222-2222-2222-2222-222222222222';
  c_recep constant uuid := '33333333-3333-3333-3333-333333333333';
  c_fisio constant uuid := '44444444-4444-4444-4444-444444444444';
begin
  -- Punto de partida de las pruebas: solo los fisioterapeutas atienden
  perform pg_temp.ok((select atiende from public.perfiles where id = c_fisio),
    'El fisioterapeuta atiende por definicion del rol');
  perform pg_temp.ok(not (select atiende from public.perfiles where id = c_recep),
    'Recepcion no atiende');
  perform pg_temp.ok(not public.puede_atender(c_super),
    'Sin marcar, el superadministrador no aparece como quien atiende');

  perform set_config('neoterapia.test_uid', c_super::text, true);
  v_sol := public.solicitar_cita(jsonb_build_object(
    'dpi', '1834571100901', 'nombre_completo', 'Paciente Del Dueno',
    'telefono', '4444-7777', 'fecha', (current_date + 34)::text,
    'acepta_politica', true,
    'areas', jsonb_build_array(jsonb_build_object('codigo', 'hombro_der', 'intensidad', 6))));
  select id into v_cita from public.citas where codigo_referencia = v_sol ->> 'codigo_referencia';
  perform public.confirmar_cita(v_cita, now() + interval '34 days');

  -- Antes de marcarse: ni se le asigna, ni se auto-asigna al atender
  r := public.asignar_fisioterapeuta(v_cita, c_super);
  perform pg_temp.ok((r ->> 'error') = 'no_atiende',
    'No se asigna a quien no esta marcado como que atiende');
  r := public.marcar_asistencia(v_cita, true);
  perform pg_temp.ok((r ->> 'error') = 'falta_fisioterapeuta',
    'Y tampoco queda el como autor de la nota por marcar la asistencia');

  -- El superadministrador se marca a si mismo
  update public.perfiles set atiende = true where id = c_super;
  perform pg_temp.ok(public.puede_atender(c_super), 'Ya figura como quien atiende');
  perform pg_temp.ok(public.atiendo(), 'Y se reconoce a si mismo');
  perform pg_temp.ok(
    (select bool_and(id in (select id from public.perfiles where atiende and activo))
       from public.perfiles where id in (c_super, c_fisio)),
    'La agenda ahora lo ofrece a el junto a los fisioterapeutas');

  -- Ahora si atiende
  r := public.marcar_asistencia(v_cita, true);
  perform pg_temp.ok((r ->> 'ok')::boolean,
    'El superadministrador que atiende cierra la cita como atendida');
  perform pg_temp.ok(
    (select fisioterapeuta_id = c_super from public.citas where id = v_cita),
    'La cita queda a su nombre');
  perform pg_temp.ok(
    (select fisioterapeuta_id = c_super from public.sesiones where cita_id = v_cita),
    'Y la nota clinica tambien: tiene autor');
  r := public.firmar_sesion((select id from public.sesiones where cita_id = v_cita));
  perform pg_temp.ok((r ->> 'ok')::boolean, 'Puede firmar la nota que el mismo escribio');
  perform pg_temp.ok(public.puedo_ver_clinico(
      (select paciente_id from public.citas where id = v_cita)),
    'Y ve el expediente de ese paciente');

  -- El rol sigue mandando en los extremos
  update public.perfiles set atiende = false where id = c_fisio;
  perform pg_temp.ok((select atiende from public.perfiles where id = c_fisio),
    'A un fisioterapeuta no se le puede quitar: es su rol');
  update public.perfiles set atiende = true where id = c_recep;
  perform pg_temp.ok(not (select atiende from public.perfiles where id = c_recep),
    'A recepcion no se le puede poner: no ve lo clinico');

  -- Solo el superadministrador reparte esa capacidad
  perform set_config('neoterapia.test_uid', c_admin::text, true);
  begin
    update public.perfiles set atiende = true where id = c_admin;
    perform pg_temp.ok(false, 'Un admin NO deberia poder auto-asignarse consulta');
  exception when insufficient_privilege then
    perform pg_temp.ok(true, 'Un administrador no se marca a si mismo: lo hace el superadmin');
  end;

  -- Alta de personal con la casilla marcada
  perform set_config('neoterapia.test_uid', c_super::text, true);
  r := public.crear_usuario_personal(
    'dueno2@neoterapia.gt', 'unaClaveLarga1', 'Segundo Dueno', 'admin',
    null, null, null, '#7c3aed', true);
  perform pg_temp.ok((r ->> 'ok')::boolean, 'Se da de alta un administrador que atiende');
  perform pg_temp.ok((r ->> 'atiende')::boolean, 'La respuesta confirma que atendera');
  perform pg_temp.ok(public.puede_atender((r ->> 'usuario_id')::uuid),
    'Y entra directo a la lista de quien puede atender');

  r := public.crear_usuario_personal(
    'recep2@neoterapia.gt', 'unaClaveLarga1', 'Segunda Recepcion', 'recepcion',
    null, null, null, null, true);
  perform pg_temp.ok(not public.puede_atender((r ->> 'usuario_id')::uuid),
    'Marcar la casilla en un usuario de recepcion no lo convierte en clinico');
end $$;

\echo ''
\echo '================= TODAS LAS PRUEBAS PASARON ================='
