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
\echo '================= TODAS LAS PRUEBAS PASARON ================='
