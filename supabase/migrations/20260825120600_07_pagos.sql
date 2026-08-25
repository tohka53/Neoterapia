-- ============================================================================
-- NeoTerapia · 07 · Pagos y comprobantes
-- ----------------------------------------------------------------------------
-- Lo maneja recepcion y administracion. El fisioterapeuta no ve pagos.
-- ============================================================================

-- Resuelve pgcrypto / pg_trgm / unaccent vivan donde vivan (Supabase las pone
-- en `extensions`; un Postgres normal las deja en `public`).
set search_path = public, extensions;

create table if not exists public.pagos (
  id              uuid primary key default gen_random_uuid(),
  paciente_id     uuid not null references public.pacientes(id) on delete cascade,
  cita_id         uuid references public.citas(id) on delete set null,
  sesion_id       uuid references public.sesiones(id) on delete set null,

  monto           numeric(10,2) not null check (monto > 0),
  moneda          text not null default 'GTQ' check (moneda ~ '^[A-Z]{3}$'),
  metodo          public.metodo_pago not null default 'efectivo',
  estado          public.estado_pago  not null default 'pagado',

  referencia      text,                    -- boleta, autorizacion, no. de transferencia
  comprobante_path text,                   -- ruta en Storage (bucket `comprobantes`)
  descripcion     text,

  fecha           timestamptz not null default now(),
  registrado_por  uuid references public.perfiles(id),

  anulado_en      timestamptz,
  anulado_por     uuid references public.perfiles(id),
  motivo_anulacion text,

  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),

  constraint ck_pago_anulacion check (
    (estado = 'anulado') = (anulado_en is not null)
  )
);

create index if not exists ix_pagos_paciente on public.pagos (paciente_id, fecha desc);
create index if not exists ix_pagos_cita     on public.pagos (cita_id);
create index if not exists ix_pagos_fecha    on public.pagos (fecha desc) where estado = 'pagado';

drop trigger if exists tg_pagos_actualizado on public.pagos;
create trigger tg_pagos_actualizado before update on public.pagos
  for each row execute function public.tg_actualizar_timestamp();

-- Un pago pagado no se edita en monto/metodo: se anula y se registra otro.
create or replace function public.tg_pago_inmutable()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.estado = 'pagado' and new.estado = 'pagado'
     and (new.monto is distinct from old.monto or new.metodo is distinct from old.metodo)
  then
    raise exception 'Un pago aplicado no puede modificarse. Anulelo y registre uno nuevo.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists tg_pagos_inmutable on public.pagos;
create trigger tg_pagos_inmutable before update on public.pagos
  for each row execute function public.tg_pago_inmutable();

-- ----------------------------------------------------------------------------
-- Saldo por paciente (tratamientos aplicados vs. pagos aplicados)
-- ----------------------------------------------------------------------------

-- security_invoker: la vista respeta las politicas RLS de quien consulta,
-- no las del dueno de la vista (postgres). Sin esto, cualquier vista seria
-- un agujero para saltarse RLS.
create or replace view public.v_saldos_paciente
with (security_invoker = true) as
select
  p.id                                      as paciente_id,
  coalesce(cargos.total, 0)                 as total_cargos,
  coalesce(abonos.total, 0)                 as total_pagado,
  coalesce(cargos.total, 0) - coalesce(abonos.total, 0) as saldo
from public.pacientes p
left join lateral (
  select sum(st.precio_aplicado * st.cantidad) as total
  from public.sesion_tratamientos st
  join public.sesiones s on s.id = st.sesion_id
  where s.paciente_id = p.id
) cargos on true
left join lateral (
  select sum(pg.monto) as total
  from public.pagos pg
  where pg.paciente_id = p.id and pg.estado = 'pagado'
) abonos on true;
