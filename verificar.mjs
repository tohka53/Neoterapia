/**
 * Verificación visual del frontend contra respuestas simuladas de Supabase.
 * No toca el proyecto real: intercepta las llamadas y devuelve datos del
 * esquema local, para comprobar que el flujo público se pinta y funciona.
 */
import { chromium } from 'playwright';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const RAIZ = new URL('./dist/neoterapia/browser', import.meta.url).pathname;
const SALIDA = new URL('./capturas', import.meta.url).pathname;
fs.mkdirSync(SALIDA, { recursive: true });

// El catálogo del mapa corporal se lee del propio seed, para que la prueba no
// se desincronice del esquema.
const SEED = fs.readFileSync(new URL('./supabase/seed.sql', import.meta.url), 'utf8');
const AREAS = [...SEED.matchAll(
  /\('([a-z0-9_]+)',\s*'([^']+)',\s*'(\w+)',\s*'(\w+)',\s*'(anterior|posterior)',\s*([\d.]+),\s*([\d.]+),\s*(\d+)\)/g,
)].map((m) => ({
  codigo: m[1], nombre: m[2], region: m[3], lado: m[4], vista: m[5],
  svg_x: Number(m[6]), svg_y: Number(m[7]), orden: Number(m[8]),
}));
if (AREAS.length < 40) {
  console.error('No se pudieron leer las areas del seed:', AREAS.length);
  process.exit(1);
}

const TIPOS = {
  '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css',
  '.ico': 'image/x-icon', '.json': 'application/json', '.svg': 'image/svg+xml',
};

const servidor = http.createServer((req, res) => {
  const url = req.url.split('?')[0];
  let archivo = path.join(RAIZ, url === '/' ? 'index.html' : url);
  if (!fs.existsSync(archivo) || fs.statSync(archivo).isDirectory()) {
    archivo = path.join(RAIZ, 'index.html');   // fallback SPA
  }
  res.writeHead(200, { 'content-type': TIPOS[path.extname(archivo)] ?? 'application/octet-stream' });
  fs.createReadStream(archivo).pipe(res);
});
await new Promise((r) => servidor.listen(4173, r));

const hoy = new Date();
const enCincoDias = new Date(hoy.getTime() + 5 * 864e5).toISOString().slice(0, 10);

const slots = ['08:00', '08:45', '09:30', '10:15', '11:00', '14:00', '14:45', '15:30']
  .map((h) => ({
    hora: `${h}:00`,
    inicio: `${enCincoDias}T${h}:00-06:00`,
    cupos_totales: 2,
    cupos_ocupados: h === '09:30' ? 2 : 0,
    disponible: h !== '09:30',
  }));

const navegador = await chromium.launch({ executablePath: process.env['CHROMIUM'] || undefined, args: ['--no-sandbox'] });
const ctx = await navegador.newContext({ viewport: { width: 1280, height: 900 }, locale: 'es-GT' });
const pagina = await ctx.newPage();

const errores = [];
pagina.on('console', (m) => { if (m.type() === 'error') errores.push(m.text()); });
pagina.on('pageerror', (e) => errores.push('pageerror: ' + e.message));

await pagina.route('**/rest/v1/rpc/**', async (ruta) => {
  const url = ruta.request().url();
  const json = (cuerpo) => ruta.fulfill({
    status: 200, contentType: 'application/json', body: JSON.stringify(cuerpo),
  });
  if (url.includes('areas_mapa')) return json(AREAS);
  if (url.includes('slots_disponibles')) return json(slots);
  if (url.includes('solicitar_cita')) {
    return json({
      ok: true, duplicada: false, codigo_referencia: 'NT-K4M-7XQ2',
      estado: 'solicitada', fecha_solicitada: enCincoDias, canal: 'whatsapp',
      mensaje: 'Su solicitud fue recibida. La clínica le confirmará por su canal preferido.',
    });
  }
  return json({});
});
await pagina.route('**/auth/v1/**', (r) =>
  r.fulfill({ status: 200, contentType: 'application/json', body: '{}' }));

const capturar = async (nombre) => {
  await pagina.waitForTimeout(450);
  await pagina.screenshot({ path: `${SALIDA}/${nombre}.png`, fullPage: true });
  console.log('  ✓', nombre);
};

const revisar = async (etiqueta, cond) => {
  console.log(cond ? `  OK    ${etiqueta}` : `  FALLO ${etiqueta}`);
  if (!cond) process.exitCode = 1;
};

console.log('\n== Sitio público ==');
await pagina.goto('http://localhost:4173/', { waitUntil: 'networkidle' });
await revisar('La portada carga', await pagina.locator('h1').first().isVisible());
await capturar('01-inicio');

console.log('\n== Paso 1: identificación ==');
await pagina.goto('http://localhost:4173/solicitar', { waitUntil: 'networkidle' });
await pagina.fill('#dpi', '6018159041102');
await revisar('El DPI se formatea al escribir', (await pagina.inputValue('#dpi')) === '6018 15904 1102');
await pagina.fill('#nombre', 'Juan Carlos Pérez López');
await pagina.fill('#tel', '5512-3456');
await capturar('02-solicitar-datos');

const continuar = pagina.getByRole('button', { name: 'Continuar' });
await revisar('El botón Continuar se habilita con datos válidos', await continuar.isEnabled());

// Un DPI con el dígito verificador alterado debe bloquear el paso.
await pagina.fill('#dpi', '6018159051102');
await pagina.locator('#nombre').click();
await pagina.waitForTimeout(150);
await revisar('Un DPI inválido bloquea el avance', !(await continuar.isEnabled()));
await revisar('Se muestra el mensaje de DPI inválido',
  await pagina.locator('text=El DPI no es válido').isVisible());
await capturar('03-dpi-invalido');

await pagina.fill('#dpi', '6018159041102');
await continuar.click();

console.log('\n== Paso 2: fecha y horario ==');
await pagina.waitForSelector('#fecha');
await pagina.fill('#fecha', enCincoDias);
await pagina.waitForTimeout(600);
const botonesHora = await pagina.locator('button:has-text("a.m."), button:has-text("p.m.")').count();
await revisar(`Se pintan los horarios disponibles (${botonesHora})`, botonesHora >= 6);
await pagina.locator('button:has-text("8:00 a.m.")').first().click();
await capturar('04-solicitar-fecha');
await continuar.click();

console.log('\n== Paso 3: mapa corporal ==');
await pagina.waitForSelector('app-mapa-corporal svg');
const zonas = await pagina.locator('app-mapa-corporal svg g[role="checkbox"]').count();
await revisar(`El mapa corporal dibuja las zonas de la vista frontal (${zonas})`, zonas > 20);
await revisar('Sin zonas marcadas no se puede continuar', !(await continuar.isEnabled()));

await pagina.locator('app-mapa-corporal svg g[role="checkbox"]').nth(16).click();
await pagina.locator('svg g[role="checkbox"]').nth(20).click();
await pagina.waitForTimeout(200);
await revisar('Se puede continuar tras marcar zonas', await continuar.isEnabled());
await pagina.fill('#motivo', 'Dolor lumbar al levantar peso en el trabajo');
await capturar('05-mapa-corporal');

// Vista posterior
await pagina.locator('button:has-text("Espalda")').first().click();
await pagina.waitForTimeout(250);
await capturar('06-mapa-espalda');
await pagina.locator('button:has-text("Frente")').first().click();

await continuar.click();

console.log('\n== Paso 4: revisión y envío ==');
await pagina.waitForSelector('text=Revise antes de enviar');
await capturar('07-revision');
const enviar = pagina.getByRole('button', { name: 'Enviar solicitud' });
await revisar('No se puede enviar sin aceptar la política', !(await enviar.isEnabled()));
await pagina.locator('input[type="checkbox"]').last().check();
await pagina.waitForTimeout(200);
await revisar('Al aceptar la política se habilita el envío', await enviar.isEnabled());
await enviar.click();

await pagina.waitForSelector('text=NT-K4M-7XQ2', { timeout: 5000 });
await revisar('Se muestra el código de referencia', true);
await revisar('Se advierte que la cita aún no está confirmada',
  await pagina.locator('text=no está confirmada').isVisible());
await capturar('08-codigo-referencia');

console.log('\n== Otras pantallas ==');
await pagina.goto('http://localhost:4173/acceso', { waitUntil: 'networkidle' });
await revisar('La pantalla de acceso del personal carga',
  await pagina.locator('text=Acceso del personal').first().isVisible());
await capturar('09-acceso');

await pagina.goto('http://localhost:4173/politica-de-datos', { waitUntil: 'networkidle' });
await capturar('10-politica');

await pagina.goto('http://localhost:4173/cita/confirmar?t=' + 'a'.repeat(64), { waitUntil: 'networkidle' });
await pagina.waitForTimeout(700);
await capturar('11-enlace-invalido');

// Móvil
await pagina.setViewportSize({ width: 390, height: 844 });
await pagina.goto('http://localhost:4173/solicitar', { waitUntil: 'networkidle' });
await capturar('12-movil-solicitar');

console.log('\n== Errores de consola ==');
const relevantes = errores.filter((e) => !/favicon|net::ERR|Failed to load resource/i.test(e));
if (relevantes.length) {
  console.log('  ' + relevantes.length + ' error(es):');
  relevantes.slice(0, 8).forEach((e) => console.log('   -', e.slice(0, 200)));
  process.exitCode = 1;
} else {
  console.log('  OK    sin errores de JavaScript');
}

await navegador.close();
servidor.close();
console.log('\nCapturas en', SALIDA);
