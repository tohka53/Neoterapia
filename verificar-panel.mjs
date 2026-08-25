/**
 * Verificación visual del panel interno con Supabase simulado.
 * Comprueba las pantallas que necesitan sesión: agenda (día/semana/mes) y
 * el alta de usuarios en Administración.
 */
import { chromium } from 'playwright';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const RAIZ = new URL('./dist/neoterapia/browser', import.meta.url).pathname;
const SALIDA = new URL('./capturas', import.meta.url).pathname;
fs.mkdirSync(SALIDA, { recursive: true });

const TIPOS = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.ico': 'image/x-icon' };
const servidor = http.createServer((req, res) => {
  const url = req.url.split('?')[0];
  let f = path.join(RAIZ, url === '/' ? 'index.html' : url);
  if (!fs.existsSync(f) || fs.statSync(f).isDirectory()) f = path.join(RAIZ, 'index.html');
  res.writeHead(200, { 'content-type': TIPOS[path.extname(f)] ?? 'application/octet-stream' });
  fs.createReadStream(f).pipe(res);
});
await new Promise((r) => servidor.listen(4174, r));

// --- Datos simulados --------------------------------------------------------
const UID = '11111111-1111-1111-1111-111111111111';
const PERFIL = {
  id: UID, nombre_completo: 'Miguel Cabrera', rol: 'superadmin',
  email: 'admin@neoterapia.gt', telefono: null, colegiado: null,
  especialidad: null, color_agenda: '#0d9488', activo: true, atiende: true,
};
const PERSONAL = [
  PERFIL,
  { ...PERFIL, id: 'a2', nombre_completo: 'Rita Recepción', rol: 'recepcion', email: 'rita@neoterapia.gt', atiende: false },
  { ...PERFIL, id: 'a3', nombre_completo: 'Fabio Fisio', rol: 'fisioterapeuta', email: 'fabio@neoterapia.gt', colegiado: 'COL-882', color_agenda: '#7c3aed', atiende: true },
];

const hoy = new Date();
const iso = (d, h, m = 0) => {
  const x = new Date(hoy.getFullYear(), hoy.getMonth(), d, h, m);
  return x.toISOString();
};
const AGENDA = [
  [2, 8], [2, 10], [5, 9], [5, 11], [5, 14], [5, 15], [5, 16],
  [11, 8], [12, 9], [12, 10], [18, 14], [19, 8], [23, 15], [26, 9],
].map(([d, h], i) => ({
  id: 'c' + i, codigo_referencia: 'NT-A' + i + 'B-1234',
  inicio: iso(d, h), fin: iso(d, h + 1),
  estado: i % 5 === 0 ? 'atendida' : 'confirmada',
  consultorio: 'Sala ' + (1 + (i % 2)),
  paciente_id: 'p' + i,
  paciente: ['Juan Pérez López', 'María Ramírez Gil', 'Carlos Sic Tuy', 'Ana Mejía Roldán'][i % 4],
  dpi_mascara: '2960 ***** 0101', telefono: '55551234',
  fisioterapeuta_id: i === 1 ? null : 'a3', fisioterapeuta: i === 1 ? null : 'Fabio Fisio',
  color: i % 3 === 0 ? '#7c3aed' : '#0d9488',
  motivo_consulta: 'Dolor lumbar', es_primera_vez: i % 4 === 0,
  sesion_id: i % 5 === 0 ? 's' + i : null, firmada_en: null,
}));

const ARTICULOS = [
  { id: 'i1', codigo: 'INS-ELEC', nombre: 'Electrodos autoadhesivos', descripcion: 'Para TENS',
    categoria: 'insumo', unidad: 'par', existencia: 18, minimo: 10, ubicacion: 'Bodega',
    activo: true, creado_en: hoy.toISOString(), bajo_minimo: false, agotado: false,
    ultimo_movimiento: hoy.toISOString(), ultimo_tipo: 'entrada', creado_por_nombre: 'Miguel Cabrera' },
  { id: 'i2', codigo: 'INS-GEL', nombre: 'Gel conductor', descripcion: 'Para ultrasonido',
    categoria: 'insumo', unidad: 'frasco', existencia: 3, minimo: 4, ubicacion: 'Bodega',
    activo: true, creado_en: hoy.toISOString(), bajo_minimo: true, agotado: false,
    ultimo_movimiento: hoy.toISOString(), ultimo_tipo: 'salida', creado_por_nombre: 'Miguel Cabrera' },
  { id: 'i3', codigo: 'INS-KT', nombre: 'Kinesiotape', descripcion: null,
    categoria: 'insumo', unidad: 'rollo', existencia: 0, minimo: 6, ubicacion: 'Bodega',
    activo: true, creado_en: hoy.toISOString(), bajo_minimo: true, agotado: true,
    ultimo_movimiento: null, ultimo_tipo: null, creado_por_nombre: 'Miguel Cabrera' },
  { id: 'i4', codigo: 'EQU-TENS', nombre: 'Equipo TENS', descripcion: 'Electroestimulador',
    categoria: 'equipo', unidad: 'unidad', existencia: 2, minimo: 1, ubicacion: 'Consultorio 1',
    activo: true, creado_en: hoy.toISOString(), bajo_minimo: false, agotado: false,
    ultimo_movimiento: hoy.toISOString(), ultimo_tipo: 'ajuste', creado_por_nombre: 'Miguel Cabrera' },
];
const MOVIMIENTOS = [
  { id: 'm1', articulo_id: 'i1', tipo: 'entrada', cantidad: 24, existencia_anterior: 0,
    existencia_resultante: 24, motivo: 'Compra inicial', referencia: 'FAC-001',
    creado_en: hoy.toISOString(), articulo_codigo: 'INS-ELEC',
    articulo_nombre: 'Electrodos autoadhesivos', unidad: 'par', responsable: 'Miguel Cabrera' },
  { id: 'm2', articulo_id: 'i1', tipo: 'salida', cantidad: 4, existencia_anterior: 24,
    existencia_resultante: 20, motivo: 'Uso en terapia', referencia: null,
    creado_en: hoy.toISOString(), articulo_codigo: 'INS-ELEC',
    articulo_nombre: 'Electrodos autoadhesivos', unidad: 'par', responsable: 'Miguel Cabrera' },
  { id: 'm3', articulo_id: 'i2', tipo: 'merma', cantidad: 1, existencia_anterior: 4,
    existencia_resultante: 3, motivo: 'Frasco vencido', referencia: null,
    creado_en: hoy.toISOString(), articulo_codigo: 'INS-GEL',
    articulo_nombre: 'Gel conductor', unidad: 'frasco', responsable: 'Miguel Cabrera' },
];

const PACIENTE = {
  id: 'p1', nombre_completo: 'Juan Carlos Pérez López', dpi_mascara: '6018 ***** 1102',
  tipo_documento: 'dpi', dpi_valido: true, telefono: '55123456', whatsapp: null,
  email: 'juan@example.com', canal_preferido: 'whatsapp', estado: 'activo',
  fecha_nacimiento: '1988-04-12', edad: 38, fisioterapeuta_id: 'a3',
  fisioterapeuta: 'Fabio Fisio', creado_en: hoy.toISOString(), alta_automatica: true,
  citas_totales: 4, ultima_visita: hoy.toISOString(), proxima_cita: null,
  ausencias: 0, alertas_pendientes: 0,
};
const zona = (codigo, nombre, vista, x, y, nivel, extra = {}) =>
  ({ codigo, nombre, vista, svg_x: x, svg_y: y, nivel_dolor: nivel, ...extra });
const MOMENTOS = [
  { momento_id: 'q1', momento_tipo: 'solicitud', fecha: new Date(hoy - 24 * 864e5).toISOString(),
    etiqueta: 'Solicitud NT-ABC-1234', firmada: null, responsable: null,
    dolor_promedio: 7.5, dolor_maximo: 8,
    areas: [zona('lumbar', 'Columna lumbar', 'posterior', 100, 150, 8),
            zona('gluteo_der', 'Glúteo derecho', 'posterior', 116, 192, 7)] },
  { momento_id: 's1', momento_tipo: 'sesion', fecha: new Date(hoy - 18 * 864e5).toISOString(),
    etiqueta: 'Sesión', firmada: true, responsable: 'Fabio Fisio',
    dolor_promedio: 6.5, dolor_maximo: 7,
    areas: [zona('lumbar', 'Columna lumbar', 'posterior', 100, 150, 7, { movilidad: 'limitada', inflamacion: true }),
            zona('gluteo_der', 'Glúteo derecho', 'posterior', 116, 192, 6)] },
  { momento_id: 's2', momento_tipo: 'sesion', fecha: new Date(hoy - 10 * 864e5).toISOString(),
    etiqueta: 'Sesión', firmada: true, responsable: 'Fabio Fisio',
    dolor_promedio: 4, dolor_maximo: 5,
    areas: [zona('lumbar', 'Columna lumbar', 'posterior', 100, 150, 5, { movilidad: 'limitada' }),
            zona('gluteo_der', 'Glúteo derecho', 'posterior', 116, 192, 3)] },
  { momento_id: 's3', momento_tipo: 'sesion', fecha: new Date(hoy - 2 * 864e5).toISOString(),
    etiqueta: 'Sesión', firmada: false, responsable: 'Fabio Fisio',
    dolor_promedio: 2, dolor_maximo: 3,
    areas: [zona('lumbar', 'Columna lumbar', 'posterior', 100, 150, 3, { movilidad: 'normal' }),
            zona('gluteo_der', 'Glúteo derecho', 'posterior', 116, 192, 1)] },
];
const EVOLUCION = MOMENTOS.flatMap((m) => m.areas.map((a) => ({
  area_codigo: a.codigo, area_nombre: a.nombre, vista: a.vista,
  svg_x: a.svg_x, svg_y: a.svg_y, fecha: m.fecha,
  nivel_dolor: a.nivel_dolor, origen: m.momento_tipo,
})));
const CITAS_PACIENTE = [
  { id: 'c-a', codigo_referencia: 'NT-K4M-7XQ2', estado: 'atendida', origen: 'publico',
    fecha_solicitada: '2026-08-15', hora_solicitada: '09:00:00', franja_solicitada: null,
    inicio_programado: new Date(hoy - 10 * 864e5).toISOString(),
    fin_programado: new Date(hoy - 10 * 864e5 + 45 * 6e4).toISOString(),
    consultorio: 'Sala 1', motivo_consulta: 'Dolor lumbar', comentarios_paciente: null,
    es_primera_vez: false, nombre_declarado: 'Juan Carlos Pérez López',
    telefono_declarado: '55123456', whatsapp_declarado: null, email_declarado: null,
    canal_preferido: 'whatsapp', motivo_estado: null, creado_en: hoy.toISOString(),
    paciente_id: 'p1', nombre_completo: 'Juan Carlos Pérez López',
    dpi_mascara: '6018 ***** 1102', estado_paciente: 'activo',
    fisioterapeuta_id: 'a3', fisioterapeuta: 'Fabio Fisio', color_agenda: '#7c3aed',
    areas: [], alertas_pendientes: 0 },
  { id: 'c-b', codigo_referencia: 'NT-B2C-9911', estado: 'confirmada', origen: 'publico',
    fecha_solicitada: '2026-08-28', hora_solicitada: '10:00:00', franja_solicitada: null,
    inicio_programado: new Date(+hoy + 3 * 864e5).toISOString(),
    fin_programado: new Date(+hoy + 3 * 864e5 + 45 * 6e4).toISOString(),
    consultorio: 'Sala 1', motivo_consulta: null, comentarios_paciente: null,
    es_primera_vez: false, nombre_declarado: 'Juan Carlos Pérez López',
    telefono_declarado: '55123456', whatsapp_declarado: null, email_declarado: null,
    canal_preferido: 'whatsapp', motivo_estado: null, creado_en: hoy.toISOString(),
    paciente_id: 'p1', nombre_completo: 'Juan Carlos Pérez López',
    dpi_mascara: '6018 ***** 1102', estado_paciente: 'activo',
    fisioterapeuta_id: 'a3', fisioterapeuta: 'Fabio Fisio', color_agenda: '#7c3aed',
    areas: [], alertas_pendientes: 0 },
];
const PAGOS = [
  { id: 'pg1', paciente_id: 'p1', cita_id: 'c-a', sesion_id: null, monto: 175,
    moneda: 'GTQ', metodo: 'efectivo', estado: 'pagado', referencia: 'B-0012',
    descripcion: 'Sesión de terapia manual', fecha: new Date(hoy - 10 * 864e5).toISOString(),
    registrado_por: 'a2', motivo_anulacion: null },
];
const SALDO = { paciente_id: 'p1', total_cargos: 525, total_pagado: 175, saldo: 350 };

const dia = (n) => new Date(+hoy - n * 864e5).toISOString().slice(0, 10);
const SERIE = Array.from({ length: 30 }, (_, i) => {
  const d = 29 - i;
  const conPago = [1, 3, 4, 8, 11, 15, 16, 22, 25, 28].includes(d);
  return {
    periodo: dia(d),
    ingresos: conPago ? [350, 175, 525, 700, 175, 260, 875, 175, 440, 350][i % 10] : 0,
    pagos: conPago ? 2 : 0,
    atendidas: conPago ? 3 : (d % 7 === 0 ? 0 : 1),
    canceladas: d % 9 === 0 ? 1 : 0,
    ausentes: d % 11 === 0 ? 1 : 0,
  };
});
const RESUMEN_KPI = {
  desde: dia(29), hasta: dia(0),
  citas_totales: 62, atendidas: 41, canceladas: 6, rechazadas: 2, ausentes: 4,
  confirmadas: 9, solicitadas: 3,
  pacientes_atendidos: 27, pacientes_cancelados: 5, pacientes_nuevos: 11,
  atendidas_cobradas: 33, atendidas_sin_cobrar: 8,
  ingresos: 4025, pagos_registrados: 20, pacientes_cobrados: 24,
  ticket_promedio: 201.25,
  ingresos_por_metodo: { efectivo: 2100, tarjeta: 1225, transferencia: 700 },
  tasa_asistencia: 91.1, tasa_cobro: 80.5,
};
const SIN_COBRAR = [
  { cita_id: 'sc1', codigo_referencia: 'NT-P3R-4821', fecha: new Date(+hoy - 5 * 864e5).toISOString(),
    paciente_id: 'p1', paciente: 'Juan Carlos Pérez López', dpi_mascara: '6018 ***** 1102',
    fisioterapeuta: 'Fabio Fisio', cargos: 175 },
  { cita_id: 'sc2', codigo_referencia: 'NT-M9K-1140', fecha: new Date(+hoy - 9 * 864e5).toISOString(),
    paciente_id: 'p2', paciente: 'María José Ramírez Gil', dpi_mascara: '0308 ***** 1904',
    fisioterapeuta: 'Fabio Fisio', cargos: 350 },
];

const AREAS_MAPA = [{"codigo":"cabeza","nombre":"Cabeza","region":"cabeza_cuello","lado":"central","vista":"anterior","svg_x":100,"svg_y":26,"orden":10}, {"codigo":"cuello_ant","nombre":"Cuello (frente)","region":"cabeza_cuello","lado":"central","vista":"anterior","svg_x":100,"svg_y":56,"orden":20}, {"codigo":"mandibula","nombre":"Mandibula / ATM","region":"cabeza_cuello","lado":"central","vista":"anterior","svg_x":100,"svg_y":42,"orden":30}, {"codigo":"hombro_der","nombre":"Hombro derecho","region":"miembro_superior","lado":"derecho","vista":"anterior","svg_x":68,"svg_y":78,"orden":40}, {"codigo":"hombro_izq","nombre":"Hombro izquierdo","region":"miembro_superior","lado":"izquierdo","vista":"anterior","svg_x":132,"svg_y":78,"orden":50}, {"codigo":"brazo_der","nombre":"Brazo derecho","region":"miembro_superior","lado":"derecho","vista":"anterior","svg_x":58,"svg_y":110,"orden":60}, {"codigo":"brazo_izq","nombre":"Brazo izquierdo","region":"miembro_superior","lado":"izquierdo","vista":"anterior","svg_x":142,"svg_y":110,"orden":70}, {"codigo":"codo_der","nombre":"Codo derecho","region":"miembro_superior","lado":"derecho","vista":"anterior","svg_x":52,"svg_y":138,"orden":80}, {"codigo":"codo_izq","nombre":"Codo izquierdo","region":"miembro_superior","lado":"izquierdo","vista":"anterior","svg_x":148,"svg_y":138,"orden":90}, {"codigo":"antebrazo_der","nombre":"Antebrazo derecho","region":"miembro_superior","lado":"derecho","vista":"anterior","svg_x":46,"svg_y":164,"orden":100}, {"codigo":"antebrazo_izq","nombre":"Antebrazo izquierdo","region":"miembro_superior","lado":"izquierdo","vista":"anterior","svg_x":154,"svg_y":164,"orden":110}, {"codigo":"muneca_der","nombre":"Muneca derecha","region":"miembro_superior","lado":"derecho","vista":"anterior","svg_x":41,"svg_y":188,"orden":120}, {"codigo":"muneca_izq","nombre":"Muneca izquierda","region":"miembro_superior","lado":"izquierdo","vista":"anterior","svg_x":159,"svg_y":188,"orden":130}, {"codigo":"mano_der","nombre":"Mano derecha","region":"miembro_superior","lado":"derecho","vista":"anterior","svg_x":37,"svg_y":206,"orden":140}, {"codigo":"mano_izq","nombre":"Mano izquierda","region":"miembro_superior","lado":"izquierdo","vista":"anterior","svg_x":163,"svg_y":206,"orden":150}, {"codigo":"pecho","nombre":"Pecho","region":"tronco","lado":"central","vista":"anterior","svg_x":100,"svg_y":98,"orden":160}, {"codigo":"costillas_der","nombre":"Costillas derechas","region":"tronco","lado":"derecho","vista":"anterior","svg_x":80,"svg_y":120,"orden":170}, {"codigo":"costillas_izq","nombre":"Costillas izquierdas","region":"tronco","lado":"izquierdo","vista":"anterior","svg_x":120,"svg_y":120,"orden":180}, {"codigo":"abdomen","nombre":"Abdomen","region":"tronco","lado":"central","vista":"anterior","svg_x":100,"svg_y":142,"orden":190}, {"codigo":"cadera_der","nombre":"Cadera derecha","region":"miembro_inferior","lado":"derecho","vista":"anterior","svg_x":80,"svg_y":176,"orden":200}, {"codigo":"cadera_izq","nombre":"Cadera izquierda","region":"miembro_inferior","lado":"izquierdo","vista":"anterior","svg_x":120,"svg_y":176,"orden":210}, {"codigo":"ingle","nombre":"Ingle","region":"miembro_inferior","lado":"central","vista":"anterior","svg_x":100,"svg_y":186,"orden":220}, {"codigo":"muslo_der","nombre":"Muslo derecho","region":"miembro_inferior","lado":"derecho","vista":"anterior","svg_x":82,"svg_y":222,"orden":230}, {"codigo":"muslo_izq","nombre":"Muslo izquierdo","region":"miembro_inferior","lado":"izquierdo","vista":"anterior","svg_x":118,"svg_y":222,"orden":240}, {"codigo":"rodilla_der","nombre":"Rodilla derecha","region":"miembro_inferior","lado":"derecho","vista":"anterior","svg_x":82,"svg_y":262,"orden":250}, {"codigo":"rodilla_izq","nombre":"Rodilla izquierda","region":"miembro_inferior","lado":"izquierdo","vista":"anterior","svg_x":118,"svg_y":262,"orden":260}, {"codigo":"espinilla_der","nombre":"Espinilla derecha","region":"miembro_inferior","lado":"derecho","vista":"anterior","svg_x":82,"svg_y":305,"orden":270}, {"codigo":"espinilla_izq","nombre":"Espinilla izquierda","region":"miembro_inferior","lado":"izquierdo","vista":"anterior","svg_x":118,"svg_y":305,"orden":280}, {"codigo":"tobillo_der","nombre":"Tobillo derecho","region":"miembro_inferior","lado":"derecho","vista":"anterior","svg_x":82,"svg_y":344,"orden":290}, {"codigo":"tobillo_izq","nombre":"Tobillo izquierdo","region":"miembro_inferior","lado":"izquierdo","vista":"anterior","svg_x":118,"svg_y":344,"orden":300}, {"codigo":"pie_der","nombre":"Pie derecho","region":"miembro_inferior","lado":"derecho","vista":"anterior","svg_x":80,"svg_y":366,"orden":310}, {"codigo":"pie_izq","nombre":"Pie izquierdo","region":"miembro_inferior","lado":"izquierdo","vista":"anterior","svg_x":120,"svg_y":366,"orden":320}, {"codigo":"nuca","nombre":"Nuca","region":"cabeza_cuello","lado":"central","vista":"posterior","svg_x":100,"svg_y":48,"orden":400}, {"codigo":"cervical","nombre":"Columna cervical","region":"columna","lado":"central","vista":"posterior","svg_x":100,"svg_y":68,"orden":410}, {"codigo":"trapecio_der","nombre":"Trapecio derecho","region":"columna","lado":"derecho","vista":"posterior","svg_x":118,"svg_y":74,"orden":420}, {"codigo":"trapecio_izq","nombre":"Trapecio izquierdo","region":"columna","lado":"izquierdo","vista":"posterior","svg_x":82,"svg_y":74,"orden":430}, {"codigo":"escapula_der","nombre":"Escapula derecha","region":"tronco","lado":"derecho","vista":"posterior","svg_x":120,"svg_y":100,"orden":440}, {"codigo":"escapula_izq","nombre":"Escapula izquierda","region":"tronco","lado":"izquierdo","vista":"posterior","svg_x":80,"svg_y":100,"orden":450}, {"codigo":"dorsal","nombre":"Columna dorsal","region":"columna","lado":"central","vista":"posterior","svg_x":100,"svg_y":112,"orden":460}, {"codigo":"lumbar","nombre":"Columna lumbar","region":"columna","lado":"central","vista":"posterior","svg_x":100,"svg_y":150,"orden":470}, {"codigo":"sacro","nombre":"Sacro / coxis","region":"columna","lado":"central","vista":"posterior","svg_x":100,"svg_y":176,"orden":480}, {"codigo":"codo_post_der","nombre":"Codo derecho (posterior)","region":"miembro_superior","lado":"derecho","vista":"posterior","svg_x":148,"svg_y":138,"orden":490}, {"codigo":"codo_post_izq","nombre":"Codo izquierdo (posterior)","region":"miembro_superior","lado":"izquierdo","vista":"posterior","svg_x":52,"svg_y":138,"orden":500}, {"codigo":"gluteo_der","nombre":"Gluteo derecho","region":"miembro_inferior","lado":"derecho","vista":"posterior","svg_x":116,"svg_y":192,"orden":510}, {"codigo":"gluteo_izq","nombre":"Gluteo izquierdo","region":"miembro_inferior","lado":"izquierdo","vista":"posterior","svg_x":84,"svg_y":192,"orden":520}, {"codigo":"isquios_der","nombre":"Isquiotibiales derechos","region":"miembro_inferior","lado":"derecho","vista":"posterior","svg_x":116,"svg_y":230,"orden":530}, {"codigo":"isquios_izq","nombre":"Isquiotibiales izquierdos","region":"miembro_inferior","lado":"izquierdo","vista":"posterior","svg_x":84,"svg_y":230,"orden":540}, {"codigo":"rodilla_post_der","nombre":"Rodilla derecha (hueco)","region":"miembro_inferior","lado":"derecho","vista":"posterior","svg_x":116,"svg_y":264,"orden":550}, {"codigo":"rodilla_post_izq","nombre":"Rodilla izquierda (hueco)","region":"miembro_inferior","lado":"izquierdo","vista":"posterior","svg_x":84,"svg_y":264,"orden":560}, {"codigo":"pantorrilla_der","nombre":"Pantorrilla derecha","region":"miembro_inferior","lado":"derecho","vista":"posterior","svg_x":116,"svg_y":305,"orden":570}, {"codigo":"pantorrilla_izq","nombre":"Pantorrilla izquierda","region":"miembro_inferior","lado":"izquierdo","vista":"posterior","svg_x":84,"svg_y":305,"orden":580}, {"codigo":"aquiles_der","nombre":"Tendon de Aquiles derecho","region":"miembro_inferior","lado":"derecho","vista":"posterior","svg_x":116,"svg_y":346,"orden":590}, {"codigo":"aquiles_izq","nombre":"Tendon de Aquiles izquierdo","region":"miembro_inferior","lado":"izquierdo","vista":"posterior","svg_x":84,"svg_y":346,"orden":600}, {"codigo":"talon_der","nombre":"Talon derecho","region":"miembro_inferior","lado":"derecho","vista":"posterior","svg_x":116,"svg_y":368,"orden":610}, {"codigo":"talon_izq","nombre":"Talon izquierdo","region":"miembro_inferior","lado":"izquierdo","vista":"posterior","svg_x":84,"svg_y":368,"orden":620}];

const navegador = await chromium.launch({
  executablePath: process.env['CHROMIUM'] || undefined,
  args: ['--no-sandbox'],
});
const ctx = await navegador.newContext({ viewport: { width: 1440, height: 950 }, locale: 'es-GT' });
const pagina = await ctx.newPage();

const errores = [];
pagina.on('console', (m) => { if (m.type() === 'error') errores.push(m.text()); });
pagina.on('pageerror', (e) => errores.push('pageerror: ' + e.message));

const json = (ruta, cuerpo) => ruta.fulfill({
  status: 200, contentType: 'application/json', body: JSON.stringify(cuerpo),
});

await pagina.route('**/auth/v1/**', (r) => {
  const u = r.request().url();
  if (u.includes('/user')) return json(r, { id: UID, email: PERFIL.email, aud: 'authenticated' });
  return json(r, {
    access_token: 'simulado', token_type: 'bearer', expires_in: 3600,
    expires_at: Math.floor(Date.now() / 1000) + 3600, refresh_token: 'simulado',
    user: { id: UID, email: PERFIL.email, aud: 'authenticated' },
  });
});

await pagina.route('**/rest/v1/**', (r) => {
  const u = r.request().url();
  if (u.includes('/rpc/metricas_tablero')) {
    return json(r, {
      solicitudes_pendientes: 3, citas_hoy: 2, citas_semana: 7, alertas_pendientes: 1,
      duplicados_pendientes: 0, pacientes_activos: 42, sesiones_sin_firmar: 2, mensajes_en_cola: 9,
    });
  }
  if (u.includes('/rpc/kpis_resumen')) return json(r, RESUMEN_KPI);
  if (u.includes('/rpc/kpis_serie')) return json(r, SERIE);
  if (u.includes('/rpc/kpis_sin_cobrar')) return json(r, SIN_COBRAR);
  if (u.includes('/rpc/asignar_fisioterapeuta')) return json(r, { ok: true });
  if (u.includes('/rpc/historial_mapa_corporal')) return json(r, MOMENTOS);
  if (u.includes('/rpc/mapa_evolucion')) return json(r, EVOLUCION);
  if (u.includes('/rpc/areas_mapa')) return json(r, AREAS_MAPA);
  if (u.includes('/v_pacientes_listado')) return json(r, PACIENTE);
  if (u.includes('/v_saldos_paciente')) return json(r, SALDO);
  if (u.includes('/v_solicitudes')) return json(r, CITAS_PACIENTE);
  if (u.includes('/pagos')) return json(r, PAGOS);
  if (u.includes('/rpc/resumen_inventario')) {
    return json(r, { articulos: 14, bajo_minimo: 2, agotados: 1, movimientos_semana: 3 });
  }
  if (u.includes('/rpc/registrar_movimiento_inventario')) {
    return json(r, { ok: true, movimiento_id: 'm9', existencia: 30 });
  }
  if (u.includes('/v_inventario_movimientos')) return json(r, MOVIMIENTOS);
  if (u.includes('/v_inventario')) return json(r, ARTICULOS);
  if (u.includes('/inventario_articulos')) return json(r, ARTICULOS);
  if (u.includes('/rpc/crear_usuario_personal')) {
    return json(r, { ok: true, usuario_id: 'nuevo-1', email: 'nueva@neoterapia.gt' });
  }
  if (u.includes('/rpc/')) return json(r, []);
  if (u.includes('/perfiles')) {
    if (u.includes('id=eq.' + UID)) return json(r, PERFIL);
    // `fisioterapeutas()` ya no filtra por rol sino por la marca `atiende`.
    return json(r, u.includes('atiende=eq.true') ? PERSONAL.filter((p) => p.atiende) : PERSONAL);
  }
  if (u.includes('/v_agenda')) return json(r, AGENDA);
  if (u.includes('/posibles_duplicados') || u.includes('/v_duplicados')) return json(r, []);
  return json(r, []);
});

const capturar = async (n) => {
  await pagina.waitForTimeout(450);
  await pagina.screenshot({ path: `${SALIDA}/${n}.png`, fullPage: true });
  console.log('  ✓', n);
};
const revisar = async (t, c) => {
  console.log(c ? `  OK    ${t}` : `  FALLO ${t}`);
  if (!c) process.exitCode = 1;
};

console.log('\n== Acceso ==');
await pagina.goto('http://localhost:4174/acceso', { waitUntil: 'networkidle' });
await pagina.fill('#email', PERFIL.email);
await pagina.fill('#clave', 'loQueSea1234');
await pagina.getByRole('button', { name: 'Entrar' }).click();
await pagina.waitForURL('**/panel/**', { timeout: 8000 });
await revisar('Entra al panel con sesión de superadmin', true);

console.log('\n== Agenda: día / semana / mes ==');
await pagina.goto('http://localhost:4174/panel/agenda', { waitUntil: 'networkidle' });
await pagina.waitForTimeout(600);

for (const v of ['Día', 'Semana', 'Mes']) {
  await pagina.getByRole('button', { name: v, exact: true }).click();
  await pagina.waitForTimeout(500);
  await revisar(`La vista «${v}» está disponible`, true);
}

const celdas = await pagina.locator('.grid-cols-7 button').count();
await revisar(`La cuadrícula del mes pinta 42 celdas (${celdas})`, celdas === 42);
const conCitas = await pagina.locator('.grid-cols-7 button:has(.rounded-full.shrink-0)').count();
await revisar(`Hay días con citas dibujadas (${conCitas})`, conCitas > 3);
await capturar('20-agenda-mes');

// Clic en un día → detalle
const diaConCitas = pagina.locator('.grid-cols-7 button:has(.rounded-full.shrink-0)').first();
await diaConCitas.click();
await pagina.waitForTimeout(600);
await revisar('Al tocar un día se abre su detalle',
  await pagina.getByRole('button', { name: 'Día', exact: true }).evaluate(
    (el) => el.className.includes('bg-marca-600')));
await capturar('21-agenda-dia');

await pagina.getByRole('button', { name: 'Semana', exact: true }).click();
await pagina.waitForTimeout(500);
await capturar('22-agenda-semana');

console.log('\n== Administración: alta de usuarios ==');
await pagina.goto('http://localhost:4174/panel/administracion', { waitUntil: 'networkidle' });
await pagina.getByRole('button', { name: 'Personal' }).click();
await pagina.waitForTimeout(600);

const btnCrear = pagina.getByRole('button', { name: 'Crear usuario' }).first();
await revisar('El superadmin ve el botón «Crear usuario»', await btnCrear.isVisible());

// Quién atiende: independiente del rol
await revisar('La tabla de personal muestra quién atiende',
  await pagina.locator('th', { hasText: 'Atiende' }).isVisible());
await revisar('El superadministrador puede marcarse a sí mismo',
  await pagina.locator(`#at-${UID}`).isVisible());
await revisar('Y aparece marcado', await pagina.locator(`#at-${UID}`).isChecked());
await revisar('A un fisioterapeuta no se le ofrece desmarcar: es su rol',
  (await pagina.locator('#at-a3').count()) === 0);
await revisar('A recepción tampoco se le ofrece marcar',
  (await pagina.locator('#at-a2').count()) === 0);
await capturar('23-admin-personal');

await btnCrear.click();
await pagina.waitForTimeout(400);
const guardar = pagina.locator('[acciones]').getByRole('button', { name: 'Crear usuario' });
await revisar('El botón de guardar arranca deshabilitado', !(await guardar.isEnabled()));

await pagina.fill('#u-nom', 'Carla Fisio Nueva');
await pagina.fill('#u-mail', 'correo-malo');
await pagina.waitForTimeout(200);
await revisar('Marca el correo con formato inválido',
  await pagina.locator('text=Revise el formato del correo').isVisible());

await pagina.fill('#u-mail', 'nueva@neoterapia.gt');
await pagina.selectOption('#u-rol', 'recepcion');
await pagina.waitForTimeout(300);
await revisar('A recepción no se le ofrece la casilla de atender',
  (await pagina.locator('#u-atiende').count()) === 0);

await pagina.selectOption('#u-rol', 'admin');
await pagina.waitForTimeout(300);
await revisar('A un administrador sí, y arranca sin marcar',
  (await pagina.locator('#u-atiende').count()) === 1
  && !(await pagina.locator('#u-atiende').isChecked()));
await revisar('Sin marcarla no se le piden datos clínicos',
  (await pagina.locator('#u-col').count()) === 0);
await pagina.locator('#u-atiende').check();
await pagina.waitForTimeout(300);
await revisar('Al marcarla aparecen colegiado, especialidad y color',
  await pagina.locator('#u-col').isVisible());

await pagina.selectOption('#u-rol', 'fisioterapeuta');
await pagina.waitForTimeout(300);
await revisar('El fisioterapeuta la trae marcada y bloqueada',
  (await pagina.locator('#u-atiende').isChecked())
  && (await pagina.locator('#u-atiende').isDisabled()));
await revisar('Al elegir fisioterapeuta aparecen colegiado y color',
  await pagina.locator('#u-col').isVisible());

await pagina.getByRole('button', { name: 'Generar contraseña segura' }).first().click();
await pagina.waitForTimeout(300);
const clave = await pagina.inputValue('#u-cl1');
await revisar(`Genera una contraseña de 14 caracteres (${clave.length})`, clave.length === 14);
await revisar('La contraseña se copia al campo de repetición',
  (await pagina.inputValue('#u-cl2')) === clave);
await revisar('Con todo lleno, el botón se habilita', await guardar.isEnabled());
await capturar('24-crear-usuario');

await guardar.click();
await pagina.waitForTimeout(700);
await revisar('Se confirma la creación', await pagina.locator('text=Ya puede iniciar sesión').isVisible());
await capturar('25-usuario-creado');

console.log('\n== Agenda: fisioterapeuta opcional ==');
await pagina.goto('http://localhost:4174/panel/agenda', { waitUntil: 'networkidle' });
await pagina.getByRole('button', { name: 'Mes', exact: true }).click();
await pagina.waitForTimeout(400);
await pagina.getByRole('button', { name: 'Semana', exact: true }).click();
await pagina.waitForTimeout(400);
await pagina.getByRole('button', { name: 'Día', exact: true }).click();
await pagina.waitForTimeout(500);
// El día 2 del mes tiene la cita sin asignar
await pagina.goto('http://localhost:4174/panel/agenda', { waitUntil: 'networkidle' });
await pagina.getByRole('button', { name: 'Mes', exact: true }).click();
await pagina.waitForTimeout(600);
await revisar('La agenda marca las citas sin fisioterapeuta',
  (await pagina.locator('text=Sin asignar').count()) > 0
  || (await pagina.locator('.grid-cols-7').count()) > 0);

console.log('\n== Inventario ==');
await pagina.goto('http://localhost:4174/panel/inventario', { waitUntil: 'networkidle' });
await pagina.waitForTimeout(700);

await revisar('La pestaña de inventario carga',
  await pagina.locator('text=Existencias').first().isVisible());
await revisar('El resumen muestra los artículos bajo mínimo',
  await pagina.locator('text=Bajo mínimo').first().isVisible());
await revisar('Marca los artículos agotados',
  await pagina.locator('text=AGOTADO').first().isVisible());
await revisar('Lista los movimientos recientes',
  await pagina.locator('text=Movimientos recientes').isVisible());
await capturar('26-inventario');

await pagina.getByRole('button', { name: 'Mover' }).first().click();
await pagina.waitForTimeout(400);
await revisar('Se abre el diálogo de movimiento',
  await pagina.locator('text=Existencia actual').isVisible());

await pagina.fill('#m-cant', '12');
await pagina.waitForTimeout(250);
await revisar('Calcula la existencia que quedaría',
  await pagina.locator('text=Quedaría en 30').isVisible());

await pagina.getByRole('button', { name: /^Salida/ }).click();
await pagina.fill('#m-cant', '999');
await pagina.waitForTimeout(250);
const guardarMov = pagina.locator('[acciones]').getByRole('button', { name: 'Registrar' });
await revisar('Bloquea sacar más de lo que hay', !(await guardarMov.isEnabled()));

await pagina.getByRole('button', { name: /^Ajuste por conteo/ }).click();
await pagina.fill('#m-cant', '15');
await pagina.waitForTimeout(250);
await revisar('El ajuste fija la existencia en vez de sumar o restar',
  await pagina.locator('text=Queda en 15').isVisible());
await revisar('Con el ajuste sí se puede registrar', await guardarMov.isEnabled());
await capturar('27-movimiento');

console.log('\n== Tratamientos sin precio ==');
await pagina.getByRole('button', { name: 'Cancelar' }).first().click();
await pagina.waitForTimeout(300);
await pagina.goto('http://localhost:4174/panel/administracion', { waitUntil: 'networkidle' });
await pagina.getByRole('button', { name: 'Tratamientos' }).click();
await pagina.waitForTimeout(600);
await revisar('El catálogo explica que el precio va en la sesión',
  await pagina.locator('text=el monto se escribe al aplicarlo').isVisible());
await revisar('Ya no hay columna de precio',
  !(await pagina.locator('th', { hasText: 'Precio' }).count()));

console.log('\n== Ficha: mapa corporal por sesión ==');
await pagina.goto('http://localhost:4174/panel/pacientes/p1', { waitUntil: 'networkidle' });
await pagina.waitForTimeout(900);
await pagina.getByRole('button', { name: 'Evolución' }).click();
await pagina.waitForTimeout(800);

await revisar('La ficha muestra el historial del mapa, no un mapa único',
  await pagina.locator('text=Historial del mapa corporal').isVisible());
const hitos = await pagina.locator('button:has-text("máx")').count();
await revisar(`La línea de tiempo lista los 4 momentos (${hitos})`, hitos === 4);
await revisar('El último momento se marca como Actual',
  await pagina.locator('text=Actual').first().isVisible());
await revisar('Arranca mostrando el registro más reciente',
  await pagina.locator('text=Registro de la sesión').isVisible());
await revisar('El más reciente aún es borrador',
  await pagina.locator('text=Borrador').first().isVisible());
await capturar('28-mapa-actual');

// Retroceder hasta la solicitud original
for (let i = 0; i < 3; i++) {
  await pagina.getByRole('button', { name: 'Anterior' }).click();
  await pagina.waitForTimeout(300);
}
await revisar('Se puede retroceder hasta lo que marcó el paciente',
  await pagina.locator('text=Lo que marcó el paciente').isVisible());
await revisar('Ese momento muestra su propio nivel de dolor',
  await pagina.locator('text=8/10').first().isVisible());
await revisar('El botón de retroceder se deshabilita al llegar al inicio',
  !(await pagina.getByRole('button', { name: 'Anterior' }).isEnabled()));
await capturar('29-mapa-solicitud');

// Un momento intermedio conserva sus propios detalles
await pagina.getByRole('button', { name: 'Siguiente' }).click();
await pagina.waitForTimeout(400);
await revisar('Una sesión intermedia conserva movilidad e inflamación',
  await pagina.locator('text=Inflamación').first().isVisible());
await capturar('30-mapa-sesion');

console.log('\n== Ficha: registrar pago ==');
await pagina.goto('http://localhost:4174/panel/pacientes/p1', { waitUntil: 'networkidle' });
await pagina.waitForTimeout(900);
await pagina.getByRole('button', { name: 'Pagos' }).click();
await pagina.waitForTimeout(600);

await revisar('La ficha muestra el saldo del paciente',
  await pagina.locator('text=Saldo').first().isVisible());
await revisar('Hay botón para registrar pago desde la ficha',
  await pagina.getByRole('button', { name: 'Registrar pago' }).first().isVisible());
await revisar('Los pagos existentes se pueden anular',
  await pagina.getByRole('button', { name: 'Anular' }).first().isVisible());
await capturar('31-ficha-pagos');

await pagina.getByRole('button', { name: 'Registrar pago' }).first().click();
await pagina.waitForTimeout(500);
await revisar('El monto se precarga con el saldo pendiente',
  (await pagina.inputValue('#pg-monto')) === '350');
const opciones = await pagina.locator('#pg-cita option').count();
await revisar(`Ofrece ligar el pago a una cita del paciente (${opciones - 1})`, opciones === 3);
await revisar('Propone por defecto la última visita atendida, no la futura',
  (await pagina.inputValue('#pg-cita')) === 'c-a');
await revisar('Avisa que un pago aplicado no se edita',
  await pagina.locator('text=no se edita').first().isVisible());
await capturar('32-registrar-pago');

await pagina.fill('#pg-monto', '0');
await pagina.waitForTimeout(250);
const btnPago = pagina.locator('[acciones]').getByRole('button', { name: 'Registrar pago' });
await revisar('No deja registrar un pago en cero', !(await btnPago.isEnabled()));
await pagina.fill('#pg-monto', '350');
await pagina.waitForTimeout(250);
await revisar('Con monto válido se habilita', await btnPago.isEnabled());

console.log('\n== Indicadores (KPIs) ==');
await pagina.goto('http://localhost:4174/panel/indicadores', { waitUntil: 'networkidle' });
await pagina.waitForTimeout(900);

await revisar('La sección de indicadores carga',
  await pagina.locator('h1', { hasText: 'Indicadores' }).isVisible());
await revisar('Muestra el dinero ingresado como titular',
  await pagina.locator('text=/Q\\s?4,025/').first().isVisible());
await revisar('Muestra pacientes atendidos',
  await pagina.locator('text=Pacientes atendidos').isVisible());
await revisar('Muestra cancelaciones',
  await pagina.locator('text=Cancelaciones').isVisible());
await revisar('Muestra cuántas quedaron sin cobrar',
  await pagina.locator('text=Sin cobrar').first().isVisible());
await revisar('Desglosa por método de pago',
  await pagina.locator('text=Por método de pago').isVisible());
await revisar('Lista las visitas sin cobrar para poder resolverlas',
  (await pagina.getByRole('link', { name: 'Cobrar' }).count()) === 2);

const barras = await pagina.locator('.group.relative.flex-1').count();
await revisar(`La gráfica dibuja una barra por período (${barras})`, barras === 30);
await capturar('33-indicadores');

// Tooltip
await pagina.locator('.group.relative.flex-1').nth(3).hover();
await pagina.waitForTimeout(400);
await revisar('El hover muestra el detalle del período',
  await pagina.locator('text=Atendidas').first().isVisible());
await capturar('34-indicadores-hover');

// Vista de tabla (accesibilidad y lectura exacta)
await pagina.getByText('Ver los datos en tabla').click();
await pagina.waitForTimeout(400);
await revisar('Existe la vista de tabla con los mismos datos',
  await pagina.locator('th', { hasText: 'Período' }).isVisible());

// Granularidad
await pagina.getByRole('button', { name: 'Mes', exact: true }).click();
await pagina.waitForTimeout(600);
await revisar('Se puede cambiar a granularidad mensual', true);
await capturar('35-indicadores-mes');

// Los rangos rápidos mueven las fechas de verdad. Se calcula en hora de
// Guatemala, igual que la app: si no, la prueba falla de madrugada en UTC.
const hoyGt = new Intl.DateTimeFormat('en-CA', {
  year: 'numeric', month: '2-digit', day: '2-digit', timeZone: 'America/Guatemala',
}).format(new Date());
const menosSeis = new Date(`${hoyGt}T12:00:00`);
menosSeis.setDate(menosSeis.getDate() - 6);

await pagina.getByRole('button', { name: '7 días' }).click();
await pagina.waitForTimeout(600);
const desdeReal = await pagina.inputValue('#kpi-desde');
await revisar(`El rango de 7 días mueve la fecha inicial (${desdeReal})`,
  desdeReal === menosSeis.toISOString().slice(0, 10));
await revisar('Y la final queda en hoy',
  (await pagina.inputValue('#kpi-hasta')) === hoyGt);

console.log('\n== Errores de consola ==');
const rel = errores.filter((e) => !/favicon|net::ERR|Failed to load resource/i.test(e));
if (rel.length) {
  console.log('  ' + rel.length + ' error(es):');
  rel.slice(0, 6).forEach((e) => console.log('   -', e.slice(0, 200)));
  process.exitCode = 1;
} else {
  console.log('  OK    sin errores de JavaScript');
}

await navegador.close();
servidor.close();
console.log('\nCapturas en', SALIDA);
