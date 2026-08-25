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
| Roles | `superadmin`, `admin`, `recepcion` (coordina, **no ve nada clínico**), `fisioterapeuta` (ve la clínica de *sus* pacientes). |

---

## Puesta en marcha

### 1. Base de datos

**La vía rápida:** pegar `supabase/instalar.sql` completo en el SQL Editor de
Supabase y darle Run. Contiene las 12 migraciones + el seed, es idempotente y
termina verificando que las 24 tablas queden con RLS activado.

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
```

Con la CLI de Supabase:

```bash
supabase link --project-ref bjqinqcnnvofdmhqwiwt
supabase db push
psql "$DATABASE_URL" -f supabase/seed.sql
```

### 2. Primer usuario

Los usuarios del personal se crean en **Authentication → Users → Add user**
(a propósito no hay auto-registro). Copiar el UUID y darle perfil:

```sql
insert into public.perfiles (id, nombre_completo, rol, email)
values ('<uuid-del-usuario>', 'Miguel Cabrera', 'superadmin', 'correo@dominio.com');
```

A partir de ahí, el superadministrador asigna roles al resto desde
**Panel → Administración → Personal**.

### 3. Configuración de la clínica

En **Panel → Administración → Ajustes**, o directamente:

```sql
update public.configuracion set valor = '"https://citas.suclinica.gt"'::jsonb
 where clave = 'url_publica';
```

`url_publica` es la base de los enlaces que se envían al paciente: si queda mal,
los enlaces de confirmar/cancelar no funcionarán.

### 4. Frontend

```bash
npm install
npm start          # http://localhost:4200
npm run build      # dist/neoterapia
```

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
  interno/                  acceso, panel, solicitudes, agenda, pacientes,
                            ficha, sesión clínica, pagos, alertas, administración
supabase/
  migrations/               esquema versionado
  seed.sql                  configuración, mapa corporal, tratamientos, horarios
  tests/                    bootstrap local + 71 pruebas funcionales
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
disponibilidad, RLS por rol, inmutabilidad de la auditoría y control de abuso.

### Frontend

```bash
npx playwright install chromium
npm run build
node verificar.mjs
```

Levanta `dist/`, simula las respuestas de Supabase y recorre el flujo público
completo dejando capturas en `capturas/`.

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

---

## Lo que deliberadamente NO existe

No hay `RegistroPaciente`, `LoginPaciente`, `MiPerfil` ni `PortalDelPaciente`.
Si en algún momento se agregan, se rompe el modelo de privacidad completo: los
enlaces de un solo uso, el enmascarado del DPI y la separación de roles están
construidos sobre el supuesto de que el paciente no tiene sesión.
