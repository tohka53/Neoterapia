-- ============================================================================
-- NeoTerapia · Datos base (idempotente: se puede correr varias veces)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Configuracion de la clinica
-- ----------------------------------------------------------------------------

insert into public.configuracion (clave, valor, descripcion, editable_por) values
  ('nombre_clinica',          '"NeoTerapia"'::jsonb,          'Nombre visible de la clinica', 'admin'),
  ('zona_horaria',            '"America/Guatemala"'::jsonb,   'Zona horaria de operacion', 'superadmin'),
  ('url_publica',             '"http://localhost:4200"'::jsonb, 'Base para los enlaces enviados al paciente', 'superadmin'),
  ('telefono_clinica',        '""'::jsonb,                    'Telefono de contacto', 'admin'),
  ('whatsapp_clinica',        '""'::jsonb,                    'WhatsApp de contacto', 'admin'),
  ('direccion_clinica',       '""'::jsonb,                    'Direccion fisica', 'admin'),
  ('duracion_cita_min',       '45'::jsonb,                    'Duracion por defecto de una cita, en minutos', 'admin'),
  ('dias_anticipacion_max',   '60'::jsonb,                    'Cuantos dias hacia adelante se aceptan solicitudes', 'admin'),
  ('horas_anticipacion_min',  '12'::jsonb,                    'Anticipacion minima para solicitar', 'admin'),
  ('umbral_similitud_nombre', '0.55'::jsonb,                  'Bajo este valor se alerta que el nombre no coincide con el DPI', 'admin'),
  ('umbral_duplicado',        '0.62'::jsonb,                  'Puntaje minimo para marcar dos fichas como posible duplicado', 'admin'),
  ('notificaciones_activas',  'false'::jsonb,                 'Envio real de correo/WhatsApp. Apagado: los mensajes solo se encolan', 'superadmin'),
  ('politica_datos_url',      '"/politica-de-datos"'::jsonb,  'Enlace a la politica de tratamiento de datos', 'admin')
on conflict (clave) do nothing;

-- ----------------------------------------------------------------------------
-- Mapa corporal
-- ----------------------------------------------------------------------------
-- Coordenadas sobre un viewBox de 200x420.
-- Vista anterior: la derecha del paciente queda a la izquierda de la imagen.
-- Vista posterior: la derecha del paciente queda a la derecha de la imagen.

insert into public.areas_cuerpo (codigo, nombre, region, lado, vista, svg_x, svg_y, orden) values
  -- Anterior · cabeza y cuello
  ('cabeza',            'Cabeza',                    'cabeza_cuello',    'central',   'anterior', 100, 26,  10),
  ('cuello_ant',        'Cuello (frente)',           'cabeza_cuello',    'central',   'anterior', 100, 56,  20),
  ('mandibula',         'Mandibula / ATM',           'cabeza_cuello',    'central',   'anterior', 100, 42,  30),

  -- Anterior · miembro superior
  ('hombro_der',        'Hombro derecho',            'miembro_superior', 'derecho',   'anterior', 68,  78,  40),
  ('hombro_izq',        'Hombro izquierdo',          'miembro_superior', 'izquierdo', 'anterior', 132, 78,  50),
  ('brazo_der',         'Brazo derecho',             'miembro_superior', 'derecho',   'anterior', 58,  110, 60),
  ('brazo_izq',         'Brazo izquierdo',           'miembro_superior', 'izquierdo', 'anterior', 142, 110, 70),
  ('codo_der',          'Codo derecho',              'miembro_superior', 'derecho',   'anterior', 52,  138, 80),
  ('codo_izq',          'Codo izquierdo',            'miembro_superior', 'izquierdo', 'anterior', 148, 138, 90),
  ('antebrazo_der',     'Antebrazo derecho',         'miembro_superior', 'derecho',   'anterior', 46,  164, 100),
  ('antebrazo_izq',     'Antebrazo izquierdo',       'miembro_superior', 'izquierdo', 'anterior', 154, 164, 110),
  ('muneca_der',        'Muneca derecha',            'miembro_superior', 'derecho',   'anterior', 41,  188, 120),
  ('muneca_izq',        'Muneca izquierda',          'miembro_superior', 'izquierdo', 'anterior', 159, 188, 130),
  ('mano_der',          'Mano derecha',              'miembro_superior', 'derecho',   'anterior', 37,  206, 140),
  ('mano_izq',          'Mano izquierda',            'miembro_superior', 'izquierdo', 'anterior', 163, 206, 150),

  -- Anterior · tronco
  ('pecho',             'Pecho',                     'tronco',           'central',   'anterior', 100, 98,  160),
  ('costillas_der',     'Costillas derechas',        'tronco',           'derecho',   'anterior', 80,  120, 170),
  ('costillas_izq',     'Costillas izquierdas',      'tronco',           'izquierdo', 'anterior', 120, 120, 180),
  ('abdomen',           'Abdomen',                   'tronco',           'central',   'anterior', 100, 142, 190),

  -- Anterior · miembro inferior
  ('cadera_der',        'Cadera derecha',            'miembro_inferior', 'derecho',   'anterior', 80,  176, 200),
  ('cadera_izq',        'Cadera izquierda',          'miembro_inferior', 'izquierdo', 'anterior', 120, 176, 210),
  ('ingle',             'Ingle',                     'miembro_inferior', 'central',   'anterior', 100, 186, 220),
  ('muslo_der',         'Muslo derecho',             'miembro_inferior', 'derecho',   'anterior', 82,  222, 230),
  ('muslo_izq',         'Muslo izquierdo',           'miembro_inferior', 'izquierdo', 'anterior', 118, 222, 240),
  ('rodilla_der',       'Rodilla derecha',           'miembro_inferior', 'derecho',   'anterior', 82,  262, 250),
  ('rodilla_izq',       'Rodilla izquierda',         'miembro_inferior', 'izquierdo', 'anterior', 118, 262, 260),
  ('espinilla_der',     'Espinilla derecha',         'miembro_inferior', 'derecho',   'anterior', 82,  305, 270),
  ('espinilla_izq',     'Espinilla izquierda',       'miembro_inferior', 'izquierdo', 'anterior', 118, 305, 280),
  ('tobillo_der',       'Tobillo derecho',           'miembro_inferior', 'derecho',   'anterior', 82,  344, 290),
  ('tobillo_izq',       'Tobillo izquierdo',         'miembro_inferior', 'izquierdo', 'anterior', 118, 344, 300),
  ('pie_der',           'Pie derecho',               'miembro_inferior', 'derecho',   'anterior', 80,  366, 310),
  ('pie_izq',           'Pie izquierdo',             'miembro_inferior', 'izquierdo', 'anterior', 120, 366, 320),

  -- Posterior · columna
  ('nuca',              'Nuca',                      'cabeza_cuello',    'central',   'posterior', 100, 48,  400),
  ('cervical',          'Columna cervical',          'columna',          'central',   'posterior', 100, 68,  410),
  ('trapecio_der',      'Trapecio derecho',          'columna',          'derecho',   'posterior', 118, 74,  420),
  ('trapecio_izq',      'Trapecio izquierdo',        'columna',          'izquierdo', 'posterior', 82,  74,  430),
  ('escapula_der',      'Escapula derecha',          'tronco',           'derecho',   'posterior', 120, 100, 440),
  ('escapula_izq',      'Escapula izquierda',        'tronco',           'izquierdo', 'posterior', 80,  100, 450),
  ('dorsal',            'Columna dorsal',            'columna',          'central',   'posterior', 100, 112, 460),
  ('lumbar',            'Columna lumbar',            'columna',          'central',   'posterior', 100, 150, 470),
  ('sacro',             'Sacro / coxis',             'columna',          'central',   'posterior', 100, 176, 480),

  -- Posterior · miembro superior e inferior
  ('codo_post_der',     'Codo derecho (posterior)',  'miembro_superior', 'derecho',   'posterior', 148, 138, 490),
  ('codo_post_izq',     'Codo izquierdo (posterior)','miembro_superior', 'izquierdo', 'posterior', 52,  138, 500),
  ('gluteo_der',        'Gluteo derecho',            'miembro_inferior', 'derecho',   'posterior', 116, 192, 510),
  ('gluteo_izq',        'Gluteo izquierdo',          'miembro_inferior', 'izquierdo', 'posterior', 84,  192, 520),
  ('isquios_der',       'Isquiotibiales derechos',   'miembro_inferior', 'derecho',   'posterior', 116, 230, 530),
  ('isquios_izq',       'Isquiotibiales izquierdos', 'miembro_inferior', 'izquierdo', 'posterior', 84,  230, 540),
  ('rodilla_post_der',  'Rodilla derecha (hueco)',   'miembro_inferior', 'derecho',   'posterior', 116, 264, 550),
  ('rodilla_post_izq',  'Rodilla izquierda (hueco)', 'miembro_inferior', 'izquierdo', 'posterior', 84,  264, 560),
  ('pantorrilla_der',   'Pantorrilla derecha',       'miembro_inferior', 'derecho',   'posterior', 116, 305, 570),
  ('pantorrilla_izq',   'Pantorrilla izquierda',     'miembro_inferior', 'izquierdo', 'posterior', 84,  305, 580),
  ('aquiles_der',       'Tendon de Aquiles derecho', 'miembro_inferior', 'derecho',   'posterior', 116, 346, 590),
  ('aquiles_izq',       'Tendon de Aquiles izquierdo','miembro_inferior','izquierdo', 'posterior', 84,  346, 600),
  ('talon_der',         'Talon derecho',             'miembro_inferior', 'derecho',   'posterior', 116, 368, 610),
  ('talon_izq',         'Talon izquierdo',           'miembro_inferior', 'izquierdo', 'posterior', 84,  368, 620)
on conflict (codigo) do nothing;

-- ----------------------------------------------------------------------------
-- Tratamientos
-- ----------------------------------------------------------------------------

insert into public.tratamientos (codigo, nombre, descripcion, duracion_min, precio, requiere_nota) values
  ('EVAL',   'Evaluacion inicial',        'Valoracion completa, historia clinica y plan de tratamiento', 60, 200.00, true),
  ('TMAN',   'Terapia manual',            'Movilizacion articular y tecnicas de tejido blando',          45, 175.00, false),
  ('MASO',   'Masaje descontracturante',  'Masaje terapeutico profundo',                                40, 150.00, false),
  ('ELEC',   'Electroterapia',            'TENS / corrientes analgesicas',                              20,  75.00, false),
  ('ULTR',   'Ultrasonido terapeutico',   'Ultrasonido para tejidos profundos',                         15,  70.00, false),
  ('LASE',   'Laserterapia',              'Laser de baja potencia',                                     15,  90.00, false),
  ('PSEC',   'Puncion seca',              'Tratamiento de puntos gatillo miofasciales',                 30, 200.00, true),
  ('EJER',   'Ejercicio terapeutico',     'Programa supervisado de fortalecimiento y movilidad',        45, 160.00, false),
  ('VNM',    'Vendaje neuromuscular',     'Aplicacion de kinesiotape',                                  15,  80.00, false),
  ('CRIO',   'Crioterapia',               'Aplicacion de frio local',                                   15,  50.00, false),
  ('TERM',   'Termoterapia',              'Compresas humedo-calientes / parafina',                      15,  50.00, false),
  ('TRAC',   'Traccion',                  'Traccion cervical o lumbar',                                 20, 110.00, false),
  ('RESP',   'Fisioterapia respiratoria', 'Tecnicas de higiene bronquial y reeducacion respiratoria',   40, 190.00, true),
  ('DREN',   'Drenaje linfatico',         'Drenaje linfatico manual',                                   50, 210.00, false)
on conflict (codigo) do nothing;

-- ----------------------------------------------------------------------------
-- Horario de la clinica (lunes a viernes manana y tarde, sabado manana)
-- ----------------------------------------------------------------------------

insert into public.horarios_atencion (fisioterapeuta_id, dia_semana, hora_inicio, hora_fin, cupos)
select null, d, h.inicio, h.fin, 2
from generate_series(1, 5) d
cross join (values ('08:00'::time, '12:00'::time), ('14:00'::time, '18:00'::time)) as h(inicio, fin)
where not exists (
  select 1 from public.horarios_atencion x
  where x.fisioterapeuta_id is null and x.dia_semana = d and x.hora_inicio = h.inicio
);

insert into public.horarios_atencion (fisioterapeuta_id, dia_semana, hora_inicio, hora_fin, cupos)
select null, 6, '08:00'::time, '12:00'::time, 1
where not exists (
  select 1 from public.horarios_atencion x
  where x.fisioterapeuta_id is null and x.dia_semana = 6
);
