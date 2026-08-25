-- ============================================================================
-- NeoTerapia · 01 · Extensiones, esquemas y tipos base
-- ----------------------------------------------------------------------------
-- Convenciones del proyecto:
--   * Todo el modelo vive en `public` (lo que PostgREST expone por defecto).
--   * Nada del paciente pasa por `auth.users`: el paciente NUNCA tiene cuenta.
--     `auth.users` se usa exclusivamente para el personal de la clinica.
--   * El DPI normalizado es el identificador natural del paciente.
-- ============================================================================

-- Resuelve pgcrypto / pg_trgm / unaccent vivan donde vivan (Supabase las pone
-- en `extensions`; un Postgres normal las deja en `public`).
set search_path = public, extensions;

create schema if not exists extensions;

create extension if not exists pgcrypto  with schema extensions;
create extension if not exists pg_trgm   with schema extensions;
create extension if not exists unaccent  with schema extensions;
create extension if not exists btree_gist with schema extensions;

-- ----------------------------------------------------------------------------
-- Tipos enumerados
-- ----------------------------------------------------------------------------

do $$ begin
  create type public.rol_usuario as enum (
    'superadmin',      -- control total, incluye configuracion y gestion de roles
    'admin',           -- administrador de la clinica
    'recepcion',       -- responsable de citas: coordina, no ve clinica ni notas
    'fisioterapeuta'   -- ve la clinica de SUS pacientes asignados
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.tipo_documento as enum ('dpi', 'pasaporte', 'otro');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.estado_paciente as enum ('activo', 'inactivo', 'fusionado');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.estado_cita as enum (
    'solicitada',    -- entro por el formulario publico, sin revisar
    'confirmada',    -- la clinica acepto y agendo
    'reprogramada',  -- se movio de fecha/hora (queda como estado terminal del registro previo)
    'rechazada',     -- la clinica no la acepto
    'cancelada',     -- cancelada por paciente o por la clinica
    'atendida',      -- el paciente asistio y hay sesion clinica
    'ausente'        -- no se presento
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.origen_cita as enum ('publico', 'telefono', 'whatsapp', 'presencial', 'interno');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.canal_contacto as enum ('email', 'whatsapp', 'telefono');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.lado_cuerpo as enum ('izquierdo', 'derecho', 'central');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.vista_cuerpo as enum ('anterior', 'posterior');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.region_cuerpo as enum ('cabeza_cuello', 'miembro_superior', 'tronco', 'columna', 'miembro_inferior');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.metodo_pago as enum ('efectivo', 'tarjeta', 'transferencia', 'deposito', 'otro');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.estado_pago as enum ('pendiente', 'pagado', 'anulado', 'reembolsado');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.tipo_enlace as enum ('confirmar', 'cancelar', 'evaluacion', 'calendario');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.canal_mensaje as enum ('email', 'whatsapp');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.tipo_mensaje as enum (
    'solicitud_recibida', 'confirmacion', 'rechazo', 'reprogramacion',
    'cancelacion', 'recordatorio', 'evaluacion'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.estado_mensaje as enum ('pendiente', 'enviado', 'fallido', 'omitido', 'cancelado');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.tipo_alerta as enum (
    'nombre_no_coincide',   -- el DPI ya existia con otro nombre
    'posible_duplicado',    -- dos fichas parecen la misma persona
    'dpi_sospechoso',       -- paso el formato pero fallo la validacion fuerte
    'contacto_cambiado',    -- el paciente reporto telefono/correo distinto
    'solicitud_sospechosa'  -- rate limit / patron de abuso
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.estado_alerta as enum ('pendiente', 'revisada', 'descartada');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.estado_duplicado as enum ('pendiente', 'descartado', 'fusionado');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.accion_auditoria as enum (
    'insertar', 'actualizar', 'eliminar',
    'consultar_sensible',   -- alguien destapo un DPI completo o un expediente
    'fusionar', 'corregir_dpi', 'cambiar_rol', 'exportar', 'acceso_publico'
  );
exception when duplicate_object then null; end $$;
