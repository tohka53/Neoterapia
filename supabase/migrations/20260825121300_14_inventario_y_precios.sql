-- ============================================================================
-- NeoTerapia · 14 · Inventario, y el precio fuera del catalogo de tratamientos
-- ============================================================================

set search_path = public, extensions;

-- ----------------------------------------------------------------------------
-- 1. El tratamiento deja de tener precio fijo
-- ----------------------------------------------------------------------------
-- El costo varia por caso (paciente, convenio, duracion real), asi que el
-- catalogo ya no lo dicta. `sesion_tratamientos.precio_aplicado` se conserva y
-- se escribe a mano al aplicarlo: de ahi sigue saliendo el saldo del paciente.

drop trigger if exists tg_sesion_trat_precio on public.sesion_tratamientos;
drop function if exists public.tg_heredar_precio_tratamiento();

alter table public.tratamientos drop column if exists precio;

comment on column public.sesion_tratamientos.precio_aplicado is
  'Monto cobrado por ESTA aplicacion. Se escribe en la sesion; el catalogo ya no sugiere precio.';

-- ----------------------------------------------------------------------------
-- 2. Tipos del inventario
-- ----------------------------------------------------------------------------

do $$ begin
  create type public.categoria_articulo as enum (
    'insumo',      -- electrodos, gel, kinesiotape, algodon
    'equipo',      -- ultrasonido, TENS, camillas
    'medicamento', -- topicos, analgesicos de uso en clinica
    'limpieza',
    'papeleria',
    'otro'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.tipo_movimiento as enum (
    'entrada',   -- compra, donacion, devolucion  -> suma
    'salida',    -- consumo, uso en terapia       -> resta
    'merma',     -- vencido, danado, extraviado   -> resta
    'ajuste'     -- conteo fisico                 -> FIJA la existencia
  );
exception when duplicate_object then null; end $$;

-- ----------------------------------------------------------------------------
-- 3. Articulos
-- ----------------------------------------------------------------------------

create table if not exists public.inventario_articulos (
  id             uuid primary key default gen_random_uuid(),
  codigo         text not null unique check (length(btrim(codigo)) >= 2),
  nombre         text not null check (length(btrim(nombre)) >= 3),
  descripcion    text,
  categoria      public.categoria_articulo not null default 'insumo',
  unidad         text not null default 'unidad',   -- unidad, caja, rollo, par, ml, g
  -- `existencia` NO se edita a mano: la mantiene el trigger de movimientos,
  -- para que el saldo siempre cuadre con la bitacora.
  existencia     numeric(12,2) not null default 0,
  minimo         numeric(12,2) not null default 0 check (minimo >= 0),
  ubicacion      text,
  activo         boolean not null default true,
  creado_en      timestamptz not null default now(),
  creado_por     uuid references public.perfiles(id),
  actualizado_en timestamptz not null default now()
);

comment on table public.inventario_articulos is
  'Existencias de la clinica. La columna `existencia` la calcula el trigger de movimientos.';

create index if not exists ix_inv_articulos_activos on public.inventario_articulos (nombre)
  where activo;
create index if not exists ix_inv_articulos_categoria on public.inventario_articulos (categoria)
  where activo;
create index if not exists ix_inv_articulos_bajos on public.inventario_articulos (existencia)
  where activo and existencia <= minimo;

drop trigger if exists tg_inv_articulos_actualizado on public.inventario_articulos;
create trigger tg_inv_articulos_actualizado before update on public.inventario_articulos
  for each row execute function public.tg_actualizar_timestamp();

-- ----------------------------------------------------------------------------
-- 4. Movimientos (bitacora inmutable)
-- ----------------------------------------------------------------------------

create table if not exists public.inventario_movimientos (
  id                    uuid primary key default gen_random_uuid(),
  articulo_id           uuid not null references public.inventario_articulos(id) on delete restrict,
  tipo                  public.tipo_movimiento not null,
  cantidad              numeric(12,2) not null check (cantidad >= 0),
  existencia_anterior   numeric(12,2) not null,
  existencia_resultante numeric(12,2) not null,
  motivo                text,
  referencia            text,          -- factura, orden de compra, no. de lote
  realizado_por         uuid references public.perfiles(id),
  creado_en             timestamptz not null default now()
);

create index if not exists ix_inv_mov_articulo on public.inventario_movimientos (articulo_id, creado_en desc);
create index if not exists ix_inv_mov_fecha    on public.inventario_movimientos (creado_en desc);

-- Aplica el movimiento y recalcula la existencia. Bloquea el articulo para que
-- dos movimientos simultaneos no dejen el saldo torcido.
create or replace function public.tg_inventario_aplicar_movimiento()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actual numeric(12,2);
  v_nueva  numeric(12,2);
  v_nombre text;
begin
  select a.existencia, a.nombre into v_actual, v_nombre
  from public.inventario_articulos a
  where a.id = new.articulo_id
  for update;

  if v_actual is null then
    raise exception 'Articulo de inventario no encontrado.' using errcode = 'no_data_found';
  end if;

  v_nueva := case new.tipo
    when 'entrada' then v_actual + new.cantidad
    when 'salida'  then v_actual - new.cantidad
    when 'merma'   then v_actual - new.cantidad
    when 'ajuste'  then new.cantidad        -- conteo fisico: fija el valor
  end;

  if v_nueva < 0 then
    raise exception
      'No hay existencia suficiente de "%": hay % y se intentan sacar %. Registre un ajuste por conteo fisico si el dato esta desfasado.',
      v_nombre, v_actual, new.cantidad
      using errcode = 'check_violation';
  end if;

  new.existencia_anterior   := v_actual;
  new.existencia_resultante := v_nueva;
  new.realizado_por         := coalesce(new.realizado_por, auth.uid());

  update public.inventario_articulos
     set existencia = v_nueva, actualizado_en = now()
   where id = new.articulo_id;

  return new;
end;
$$;

drop trigger if exists tg_inv_movimiento on public.inventario_movimientos;
create trigger tg_inv_movimiento before insert on public.inventario_movimientos
  for each row execute function public.tg_inventario_aplicar_movimiento();

-- La bitacora no se corrige: se registra un movimiento nuevo.
create or replace function public.tg_inventario_inmutable()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Los movimientos de inventario no se editan ni se borran. Registre un ajuste.'
    using errcode = 'insufficient_privilege';
end;
$$;

drop trigger if exists tg_inv_mov_sin_cambios on public.inventario_movimientos;
create trigger tg_inv_mov_sin_cambios before update or delete on public.inventario_movimientos
  for each row execute function public.tg_inventario_inmutable();

-- La existencia solo cambia por movimientos, nunca por un UPDATE directo.
create or replace function public.tg_inventario_existencia_protegida()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.existencia is distinct from old.existencia
     and current_setting('neoterapia.movimiento_inventario', true) is distinct from 'on' then
    raise exception 'La existencia se cambia registrando un movimiento, no editando el articulo.'
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. Vistas
-- ----------------------------------------------------------------------------

create or replace view public.v_inventario
with (security_invoker = true) as
select
  a.*,
  (a.activo and a.existencia <= a.minimo)                        as bajo_minimo,
  (a.activo and a.existencia = 0)                                as agotado,
  ult.ultimo_movimiento,
  ult.ultimo_tipo,
  p.nombre_completo                                              as creado_por_nombre
from public.inventario_articulos a
left join public.perfiles p on p.id = a.creado_por
left join lateral (
  select m.creado_en as ultimo_movimiento, m.tipo as ultimo_tipo
  from public.inventario_movimientos m
  where m.articulo_id = a.id
  order by m.creado_en desc limit 1
) ult on true;

create or replace view public.v_inventario_movimientos
with (security_invoker = true) as
select
  m.*,
  a.codigo   as articulo_codigo,
  a.nombre   as articulo_nombre,
  a.unidad,
  p.nombre_completo as responsable
from public.inventario_movimientos m
join public.inventario_articulos a on a.id = m.articulo_id
left join public.perfiles p on p.id = m.realizado_por;

-- ----------------------------------------------------------------------------
-- 6. Seguridad
-- ----------------------------------------------------------------------------

alter table public.inventario_articulos   enable row level security;
alter table public.inventario_movimientos enable row level security;

grant select                         on public.inventario_articulos   to authenticated;
grant insert, update, delete         on public.inventario_articulos   to authenticated;
grant select, insert                 on public.inventario_movimientos to authenticated;
grant select on public.v_inventario             to authenticated;
grant select on public.v_inventario_movimientos to authenticated;

-- Todo el personal consulta las existencias...
drop policy if exists inv_articulos_select on public.inventario_articulos;
create policy inv_articulos_select on public.inventario_articulos
  for select to authenticated using (public.es_staff());

-- ...pero solo administracion las administra.
drop policy if exists inv_articulos_write on public.inventario_articulos;
create policy inv_articulos_write on public.inventario_articulos
  for all to authenticated using (public.es_admin()) with check (public.es_admin());

drop policy if exists inv_mov_select on public.inventario_movimientos;
create policy inv_mov_select on public.inventario_movimientos
  for select to authenticated using (public.es_staff());

drop policy if exists inv_mov_insert on public.inventario_movimientos;
create policy inv_mov_insert on public.inventario_movimientos
  for insert to authenticated with check (public.es_admin());

-- El trigger que protege `existencia` se instala despues de las politicas para
-- que la funcion de movimientos pueda seguir escribiendola.
create or replace function public.registrar_movimiento_inventario(
  p_articulo_id uuid,
  p_tipo        public.tipo_movimiento,
  p_cantidad    numeric,
  p_motivo      text default null,
  p_referencia  text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id  uuid;
  v_res numeric(12,2);
begin
  if not public.es_admin() then
    raise exception 'Su rol no permite mover el inventario.' using errcode = 'insufficient_privilege';
  end if;
  if p_cantidad is null or p_cantidad < 0 then
    return jsonb_build_object('ok', false, 'error', 'cantidad_invalida',
      'mensaje', 'La cantidad debe ser un numero positivo.');
  end if;
  if p_tipo <> 'ajuste' and p_cantidad = 0 then
    return jsonb_build_object('ok', false, 'error', 'cantidad_invalida',
      'mensaje', 'La cantidad debe ser mayor que cero.');
  end if;

  perform set_config('neoterapia.movimiento_inventario', 'on', true);

  insert into public.inventario_movimientos
    (articulo_id, tipo, cantidad, motivo, referencia, realizado_por)
  values
    (p_articulo_id, p_tipo, p_cantidad,
     nullif(btrim(coalesce(p_motivo, '')), ''),
     nullif(btrim(coalesce(p_referencia, '')), ''),
     auth.uid())
  returning id, existencia_resultante into v_id, v_res;

  perform set_config('neoterapia.movimiento_inventario', 'off', true);

  return jsonb_build_object('ok', true, 'movimiento_id', v_id, 'existencia', v_res);
exception
  when check_violation then
    return jsonb_build_object('ok', false, 'error', 'sin_existencia', 'mensaje', sqlerrm);
end;
$$;

drop trigger if exists tg_inv_existencia_protegida on public.inventario_articulos;
create trigger tg_inv_existencia_protegida before update on public.inventario_articulos
  for each row execute function public.tg_inventario_existencia_protegida();

revoke execute on function public.registrar_movimiento_inventario(
  uuid, public.tipo_movimiento, numeric, text, text) from public, anon;
grant execute on function public.registrar_movimiento_inventario(
  uuid, public.tipo_movimiento, numeric, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 7. Resumen para el panel
-- ----------------------------------------------------------------------------

create or replace function public.resumen_inventario()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'articulos',    (select count(*) from public.inventario_articulos where activo),
    'bajo_minimo',  (select count(*) from public.inventario_articulos
                      where activo and existencia <= minimo),
    'agotados',     (select count(*) from public.inventario_articulos
                      where activo and existencia = 0),
    'movimientos_semana', (select count(*) from public.inventario_movimientos
                            where creado_en >= now() - interval '7 days')
  )
  where public.es_staff()
$$;

revoke execute on function public.resumen_inventario() from public, anon;
grant execute on function public.resumen_inventario() to authenticated;

-- ----------------------------------------------------------------------------
-- 8. El tablero y el menu lateral necesitan el contador de bajo minimo
-- ----------------------------------------------------------------------------

create or replace function public.metricas_tablero()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'solicitudes_pendientes', (select count(*) from public.citas where estado = 'solicitada'),
    'citas_hoy',              (select count(*) from public.citas
                                where estado = 'confirmada'
                                  and inicio_programado::date = current_date),
    'citas_semana',           (select count(*) from public.citas
                                where estado in ('confirmada', 'atendida')
                                  and inicio_programado >= date_trunc('week', now())
                                  and inicio_programado <  date_trunc('week', now()) + interval '7 days'),
    'alertas_pendientes',     (select count(*) from public.alertas where estado = 'pendiente'),
    'duplicados_pendientes',  (select count(*) from public.posibles_duplicados where estado = 'pendiente'),
    'pacientes_activos',      (select count(*) from public.pacientes where estado = 'activo'),
    'sesiones_sin_firmar',    (select count(*) from public.sesiones where firmada_en is null),
    'mensajes_en_cola',       (select count(*) from public.mensajes where estado = 'pendiente'),
    'inventario_bajo',        (select count(*) from public.inventario_articulos
                                where activo and existencia <= minimo)
  )
  where public.es_staff()
$$;

grant execute on function public.metricas_tablero() to authenticated;
