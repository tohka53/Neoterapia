# NeoTerapia

Sistema de gestión para clínica de fisioterapia. **El paciente nunca crea cuenta
ni inicia sesión.** Pide su cita en un formulario público y el seguimiento ocurre
por correo o WhatsApp; el expediente clínico vive únicamente del lado de la clínica.

Angular 20 (standalone, signals, zoneless) + Supabase (Postgres, RLS, RPCs).

---

## Lo que define el diseño

| Decisión | Cómo está implementada |
|---|---|
| El paciente no tiene cuenta | No existen rutas de registro/login/portal. `auth.users` es exclusivo del personal. La única puerta pública es la RPC `solicitar_cita()`. |
| El DPI es el identificador principal | `pacientes.dpi_norm` (columna generada) con índice único parcial. El nombre solo se usa como comprobación. |
| El expediente se crea solo | `solicitar_cita()` busca el DPI; si existe, cuelga la cita de la ficha existente; si no, crea la ficha con `creado_por = null`. |
| Nombre que no cuadra → alerta | Se compara con `pg_trgm` sobre el nombre normalizado y ordenado; bajo el umbral se inserta una alerta `nombre_no_coincide`. El nombre de la ficha **no** se sobrescribe. |
| DPI enmascarado en listados | `dpi_mascara` es columna generada (`2960 ***** 0101`). La columna `dpi` está **revocada** para `anon` y `authenticated`. |
| Consultar el DPI completo deja rastro | Solo vía `ver_dpi_paciente()`, que valida el rol y escribe en `auditoria` con acción `consultar_sensible`. |
| Detección y fusión de duplicados | Trigger `detectar_duplicados()` al crear ficha; `fusionar_pacientes()` repunta citas, sesiones, pagos, mensajes y alertas, y deja la ficha origen marcada (nunca se borra). |
| Corregir un DPI mal digitado | `corregir_dpi()`: exige motivo, valida colisión con otra ficha y guarda el valor anterior **enmascarado** en el historial de identidad. |
| Comunicación sin portal | Cada cita tiene `codigo_referencia` (identifica, no autentica) y enlaces de un solo uso con token de 256 bits del que solo se guarda el hash SHA-256. |
| Alta de personal sin service_role | `crear_usuario_personal()` es `SECURITY DEFINER` y valida `es_superadmin()` contra el JWT. El navegador nunca ve una llave privilegiada. |
| Precios fuera del catálogo | El tratamiento no tiene precio fijo (varía por caso). El monto se escribe en `sesion_tratamientos.precio_aplicado` al aplicarlo, y de ahí sale el saldo del paciente. |
| Existencias que siempre cuadran | `inventario_articulos.existencia` no se edita: la calcula un trigger desde `inventario_movimientos`, que es bitácora inmutable. Un `UPDATE` directo a la existencia se rechaza. |
| Fisioterapeuta opcional al agendar | Se puede confirmar la hora sin saber quién atenderá; se asigna después con `asignar_fisioterapeuta()` (que no reenvía nada al paciente). Lo que sí exige autor es la **nota clínica**: `sesiones.fisioterapeuta_id` es `NOT NULL`. |
| El mapa corporal es por momento, no permanente | `sesion_areas` guarda el mapa de cada sesión. `historial_mapa_corporal()` devuelve un mapa por momento (la solicitud del paciente y cada sesión) para recorrer el historial. |
| Indicadores del negocio | `kpis_resumen()`, `kpis_serie()` y `kpis_sin_cobrar()` cuentan por fecha **local** de la clínica. «Cobrada» = la visita atendida tiene un pago ligado (`pagos.cita_id`), por eso el número de sin cobrar viene con la lista para ir a resolverlo. |
| Atender no es un rol | `perfiles.atiende` decide quién aparece en la agenda, recibe citas y firma notas; el rol decide qué administra. El fisioterapeuta atiende siempre, recepción nunca, y el superadministrador según se marque. |
| Roles | `superadmin`, `admin`, `recepcion` (coordina, **no ve nada clínico**), `fisioterapeuta` (ve la clínica de *sus* pacientes). |

---

## Puesta en marcha

### 1. Base de datos

**La vía rápida:** pegar `supabase/instalar.sql` completo en el SQL Editor de
Supabase y darle Run. Contiene las 19 migraciones + el seed, es idempotente y
termina verificando que las 26 tablas queden con RLS activado. Si agrega
migraciones, `bash supabase/generar_instalador.sh` regenera ese archivo.

Si prefiere migración por migración, ejecutar en orden el contenido de
`supabase/migrations/` (SQL Editor o `supabase db push`), y después `supabase/seed.sql`:

```
20260825120000_01_extensiones_tipos.sql
20260825120100_02_funciones_base.sql
20260825120200_03_personal_y_catalogos.sql
20260825120300_04_pacientes.sql
20260825120400_05_citas.sql
20260825120500_06_clinico.sql
20260825120600_07_pagos.sql
20260825120700_08_auditoria_enlaces_mensajes.sql
20260825120800_09_rls.sql
20260825120900_10_rpc_publicas.sql
20260825121000_11_rpc_internas.sql
20260825121100_12_vistas_y_privilegios.sql
20260825121200_13_gestion_usuarios.sql
20260825121300_14_inventario_y_precios.sql
20260825121400_15_fisioterapeuta_opcional.sql
20260825121500_16_mapa_por_sesion.sql
20260825121600_17_indicadores.sql
20260825121700_18_quien_atiende.sql
20260825121800_19_url_publica.sql
```

Con la CLI de Supabase:

```bash
supabase link --project-ref bjqinqcnnvofdmhqwiwt
supabase db push
psql "$DATABASE_URL" -f supabase/seed.sql
```

### 2. Primer usuario

Solo el primero se crea a mano; los demás salen del panel. En
**Authentication → Users → Add user** (marcando *Auto Confirm User*), y luego:

```sql
insert into public.perfiles (id, nombre_completo, rol, email, atiende)
select u.id, 'Miguel Cabrera', 'superadmin', u.email, true
from auth.users u where u.email = 'correo@dominio.com'
on conflict (id) do nothing;
```

`atiende = true` si además de administrar usted pasa consulta: así aparece en la
agenda, se le pueden asignar citas y firma notas clínicas. Se cambia cuando
quiera desde **Administración → Personal**, columna *Atiende*.

A partir de ahí, **Panel → Administración → Personal → Crear usuario** da de alta
al resto del equipo con correo, contraseña y rol, sin pasar por Supabase.

Ojo con el trigger `tg_perfiles_rol`: bloquea cambios de rol a quien no sea
superadmin, y en el SQL Editor `auth.uid()` es `null`. El `insert` de arriba
pasa; un `update ... set rol = ...` desde SQL no. Para forzarlo:

```sql
alter table public.perfiles disable trigger tg_perfiles_rol;
update public.perfiles set rol = 'admin' where email = '...';
alter table public.perfiles enable trigger tg_perfiles_rol;
```

### 3. Inventario

El seed deja 14 artículos con existencia en **cero** a propósito: se cargan
registrando movimientos de entrada, para que la bitácora cuadre desde el primer
día. **Panel → Inventario → Mover → Entrada.**

Los cuatro tipos de movimiento:

| Tipo | Efecto | Cuándo |
|---|---|---|
| Entrada | suma | compra, donación, devolución |
| Salida | resta | consumo, uso en terapia |
| Merma | resta | vencido, dañado, extraviado |
| Ajuste | **fija** la existencia | conteo físico |

### 4. Configuración de la clínica

En **Panel → Administración → Ajustes**, o directamente:

```sql
update public.configuracion set valor = '"https://neoterapia.vercel.app"'::jsonb
 where clave = 'url_publica';
```

`url_publica` es la base de los enlaces que se envían al paciente: si queda mal,
los enlaces de confirmar/cancelar no funcionarán. El seed ya lo deja apuntando
al dominio publicado; solo hay que tocarlo si mañana se cambia de dominio.

### 5. Indicadores

**Panel → Indicadores** (superadmin, admin y recepción). Responde: cuántos
pacientes se atendieron, cuántos cancelaron, cuántas visitas se cobraron y
cuántas no, y cuánto dinero entró por día, semana o mes.

Una visita cuenta como **cobrada** cuando tiene un pago ligado a ella. Al
registrar el pago, elegir la cita en el campo *Cita*: un pago suelto suma a los
ingresos pero deja la visita marcada como no cobrada. Por eso la tarjeta de
«Sin cobrar» viene con la lista de esas visitas y un botón para ir a resolverlas.

Todo se cuenta en hora de Guatemala, no en UTC: una cita de las 7 p.m. del lunes
es martes en UTC, y contarla ahí desalinearía el corte con lo que ve recepción.

### 6. Frontend

```bash
npm install
npm start          # http://localhost:4200
npm run build      # dist/neoterapia/browser
```

### 7. Despliegue en Vercel

Publicado en **https://neoterapia.vercel.app**.

`vercel.json` ya trae lo necesario: el `outputDirectory` correcto para el builder
`application` de Angular y —lo importante— el *rewrite* que manda todo a
`index.html`. Sin ese rewrite, cualquier ruta que no sea `/` da 404: el enlace
que recibe el paciente (`/cita/confirmar?t=…`) y todo `/panel/*` incluidos.

También manda `X-Robots-Tag: noindex` y `Referrer-Policy: no-referrer` en
`/cita/*`: los enlaces de un solo uso del paciente no deben terminar indexados
ni filtrar su token por la cabecera `Referer`. `public/robots.txt` dice lo mismo,
pero robots.txt es una petición y la cabecera es una orden.

Después de desplegar hay **tres sitios** donde ajustar la URL, y los tres importan:

1. **`configuracion.url_publica`** — la base de los enlaces que se le envían al
   paciente. Si queda en `localhost`, esos enlaces no sirven para nadie. El seed
   y la migración 19 ya lo dejan en el dominio publicado; esto es para cuando se
   cambie de dominio:

   ```sql
   update public.configuracion set valor = '"https://neoterapia.vercel.app"'::jsonb
    where clave = 'url_publica';
   ```

2. **Supabase → Authentication → URL Configuration** — *Site URL* y *Redirect
   URLs* deben incluir el dominio. Sin eso, el enlace de «¿olvidó su contraseña?»
   (que apunta a `/panel/clave`) lo rechaza Supabase.

3. **Supabase → Settings → API → CORS** — normalmente Supabase acepta cualquier
   origen, pero si lo restringió, agregue el dominio.

Las llaves viven en `src/environments/environment.ts`. La *publishable key*
(antes *anon key*) está diseñada para viajar en el cliente y no otorga permisos
por sí sola: toda la autorización real está en RLS y en las funciones
`SECURITY DEFINER`. **La `service_role` / secret key no debe aparecer nunca en
este proyecto.**

---

## Estructura

```
src/app/
  core/
    supabase.service.ts     cliente único + helper de RPC
    auth.service.ts         sesión del personal (signals) y permisos derivados
    guards.ts               guardas de ruta por sesión y por rol
    modelos.ts              tipos del dominio
    api/                    catálogos, citas, pacientes, clínica/pagos
    util/                   formato de fechas/DPI/teléfono, avisos
  shared/
    mapa-corporal.ts        SVG de silueta con zonas seleccionables
    ui.ts                   diálogo, chips de estado, escala de dolor, vacíos
  publico/                  portada, formulario de cita, enlaces, política
  interno/                  acceso, panel, solicitudes, agenda (día/semana/mes),
                            pacientes, ficha, sesión clínica, pagos, inventario,
                            indicadores, alertas, administración (personal,
                            catálogos, duplicados, auditoría, ajustes)
supabase/
  migrations/               esquema versionado
  seed.sql                  configuración, mapa corporal, tratamientos, horarios
  tests/                    bootstrap local + 194 pruebas funcionales
```

---

## Pruebas

### Backend

Contra un Postgres local (no necesita Supabase):

```bash
createdb neoterapia_test
psql -d neoterapia_test -f supabase/tests/00_bootstrap_local.sql   # simula roles y auth.uid()
for f in supabase/migrations/*.sql; do psql -d neoterapia_test -v ON_ERROR_STOP=1 -f "$f"; done
psql -d neoterapia_test -f supabase/seed.sql
psql -d neoterapia_test -v ON_ERROR_STOP=1 -f supabase/tests/01_pruebas.sql
```

Cubre: validación del CUI guatemalteco, alta automática por DPI, reutilización
de ficha, alerta por nombre que no coincide, validaciones del formulario,
confirmación/asistencia/firma, traslape de agenda, enlaces de un solo uso,
detección y fusión de duplicados, corrección de DPI, acceso auditado al DPI,
disponibilidad, RLS por rol, inmutabilidad de la auditoría, control de abuso,
inventario, mapa corporal por sesión, indicadores de cobro y quién atiende.

### Frontend

```bash
npx playwright install chromium
npm run build
node verificar.mjs         # flujo público: solicitud de cita de punta a punta
node verificar-panel.mjs   # panel: agenda, usuarios, inventario, mapa, KPIs
```

Levantan `dist/`, simulan las respuestas de Supabase y dejan capturas en
`capturas/`. El de panel simula además una sesión de superadmin.

---

## Notificaciones

**Desactivadas por ahora.** No hay proveedor de correo ni de WhatsApp conectado.

Los mensajes sí se generan y se guardan renderizados en `public.mensajes` con
estado `pendiente`, lo que además sirve de bitácora de comunicación. Mientras
tanto, el botón **«Copiar enlaces»** de cada cita confirmada entrega las URLs de
confirmar/cancelar para pegarlas manualmente en WhatsApp o correo.

Para activarlas más adelante basta con una Edge Function que drene la tabla:

```sql
select * from public.mensajes
where estado = 'pendiente' and programado_para <= now()
order by programado_para limit 50;
```

…enviar por el proveedor elegido y marcar `estado = 'enviado'`, `enviado_en = now()`.
Nada más del sistema necesita cambiar.

---

## Notas de seguridad

- **RLS activado en las 24 tablas.** `anon` no tiene privilegios sobre ninguna
  tabla salvo `SELECT` en el catálogo de áreas del cuerpo.
- **`FORCE ROW LEVEL SECURITY` no se usa** deliberadamente: el dueño de las
  tablas debe poder saltarse RLS para que funcionen las RPC `SECURITY DEFINER`
  que sostienen el flujo público. `anon` y `authenticated` no son dueños de nada.
- **Todas las vistas usan `security_invoker = true`**, si no serían un atajo para
  esquivar RLS.
- **`EXECUTE` revocado de `public`** y concedido función por función en la
  migración 12. `emitir_enlace_accion`, `encolar_mensaje`, `registrar_auditoria`,
  `hash_token` y `control_intento` quedan sin `GRANT`: solo se invocan desde
  dentro de otras funciones.
- **La auditoría es inmutable**: un trigger rechaza `UPDATE` y `DELETE`.
- **Control de abuso** del formulario público por IP (10/hora) y por documento
  (5/día), leyendo `request.headers` que inyecta PostgREST.
- **Las notas clínicas firmadas no se editan**: se corrigen con adendas.
- **Los pagos aplicados no se editan**: se anulan y se registra otro.
- **Crear usuarios y restablecer contraseñas** solo lo puede hacer un
  superadministrador; ni siquiera un `admin`. Ambas acciones quedan auditadas.
- **El inventario lo mueve administración** (admin y superadmin); recepción y
  fisioterapeutas solo consultan. Los movimientos no se editan ni se borran, y
  una salida que dejaría la existencia en negativo se rechaza con un mensaje que
  sugiere hacer primero un ajuste por conteo físico.
- **Una nota clínica siempre tiene autor.** Si la cita no trae fisioterapeuta y
  quien marca la asistencia sí lo es, queda registrado él. Si lo marca recepción,
  el sistema pide asignar uno primero en vez de inventar un autor.

---

## Lo que deliberadamente NO existe

No hay `RegistroPaciente`, `LoginPaciente`, `MiPerfil` ni `PortalDelPaciente`.
Si en algún momento se agregan, se rompe el modelo de privacidad completo: los
enlaces de un solo uso, el enmascarado del DPI y la separación de roles están
construidos sobre el supuesto de que el paciente no tiene sesión.
