-- ============================================================================
-- NeoTerapia · 19 · La URL publica deja de ser localhost
-- ----------------------------------------------------------------------------
-- El sitio ya esta desplegado en https://neoterapia.vercel.app. `url_publica`
-- es la base de TODO enlace que se le manda al paciente (confirmar, cancelar,
-- evaluacion, calendario); mientras apunte a localhost esos enlaces no le
-- sirven a nadie mas que al desarrollador.
--
-- Solo se corrige si sigue en el valor de desarrollo: si manana la clinica
-- compra su dominio y lo cambia desde Administracion, volver a correr esta
-- migracion no se lo pisa.
-- ============================================================================

set search_path = public, extensions;

update public.configuracion
   set valor = '"https://neoterapia.vercel.app"'::jsonb
 where clave = 'url_publica'
   and valor #>> '{}' in ('http://localhost:4200', 'http://localhost:4174', '', 'https://neoterapia.gt');

-- Si la fila no existia (instalacion vieja sin ese seed), se crea.
insert into public.configuracion (clave, valor, descripcion, editable_por)
values ('url_publica', '"https://neoterapia.vercel.app"'::jsonb,
        'Base para los enlaces enviados al paciente', 'superadmin')
on conflict (clave) do nothing;

do $$
begin
  raise notice 'url_publica = %', public.config('url_publica') #>> '{}';
end $$;
