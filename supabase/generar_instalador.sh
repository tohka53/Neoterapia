#!/usr/bin/env bash
# ============================================================================
#  Genera supabase/instalar.sql concatenando migraciones + seed.
#  Correr desde la raiz del repo:   bash supabase/generar_instalador.sh
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"

SALIDA=instalar.sql
N=$(ls migrations/*.sql | wc -l | tr -d ' ')

{
cat <<CABECERA
-- ============================================================================
--  NeoTerapia · INSTALACION COMPLETA
-- ----------------------------------------------------------------------------
--  Pegue TODO este archivo en:  Supabase → SQL Editor → New query → Run
--
--  Contiene, en orden, las ${N} migraciones + los datos base (seed).
--  Es idempotente: si algo falla a medio camino, corrija y vuelva a correrlo
--  completo sin problema.
--
--  Despues de correrlo faltan solo dos cosas (estan al final del archivo,
--  comentadas): crear su usuario y ajustar la URL publica.
-- ============================================================================

CABECERA

for f in migrations/*.sql; do
  echo ""
  echo "-- ####################  $(basename "$f")  ####################"
  echo ""
  cat "$f"
done

echo ""
echo "-- ####################  seed.sql  ####################"
echo ""
cat seed.sql

cat <<'PIE'

-- ============================================================================
--  QUE SIGUE (no se ejecuta solo: hay que editarlo)
-- ----------------------------------------------------------------------------
--  1. Cree su usuario en  Authentication → Users → Add user
--     (marque "Auto Confirm User" para no tener que confirmar el correo).
--
--  2. Copie el UUID que le asigno y descomente esto, cambiando los tres valores.
--     `atiende` en true si ademas de administrar usted pasa consulta: asi
--     aparece en la agenda y puede firmar notas clinicas.
--
--     insert into public.perfiles (id, nombre_completo, rol, email, atiende)
--     values ('PEGUE-AQUI-EL-UUID', 'Miguel Cabrera', 'superadmin', 'su@correo.com', true);
--
--  3. La URL base de los enlaces que se le envian al paciente ya queda en
--     https://neoterapia.vercel.app. Solo hay que tocarla si cambia de dominio:
--
--     update public.configuracion
--        set valor = '"https://su-dominio.com"'::jsonb
--      where clave = 'url_publica';
-- ============================================================================

-- Verificacion rapida: las dos cifras deben ser iguales (todas las tablas con RLS).
select count(*) filter (where rowsecurity)      as tablas_con_rls,
       count(*)                                  as tablas_totales
from pg_tables
where schemaname = 'public';
PIE
} > "$SALIDA"

echo "Generado $SALIDA con $N migraciones ($(wc -l < "$SALIDA") lineas)."
