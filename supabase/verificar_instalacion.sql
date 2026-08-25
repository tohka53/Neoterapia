select 'tablas en public'                as que, count(*)::text as valor from pg_tables where schemaname='public'
union all select 'tablas con RLS activo',      count(*)::text from pg_tables where schemaname='public' and rowsecurity
union all select 'politicas RLS',              count(*)::text from pg_policies where schemaname='public'
union all select 'funciones',                  count(*)::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
union all select 'vistas',                     count(*)::text from pg_views where schemaname='public'
union all select 'areas del mapa corporal',    count(*)::text from public.areas_cuerpo
union all select 'tratamientos',               count(*)::text from public.tratamientos
union all select 'bloques de horario',         count(*)::text from public.horarios_atencion
union all select 'llaves de configuracion',    count(*)::text from public.configuracion
union all select '--- seguridad ---',          ''
union all select 'valida un DPI real',         (public.validar_dpi('6018159041102')->>'valido')
union all select 'anon lee pacientes',
  case when has_table_privilege('anon','public.pacientes','select') then 'SI <-- MAL' else 'no (correcto)' end
union all select 'staff ve la columna dpi',
  case when has_column_privilege('authenticated','public.pacientes','dpi','select') then 'SI <-- MAL' else 'no (correcto)' end
union all select 'staff ve dpi_mascara',
  case when has_column_privilege('authenticated','public.pacientes','dpi_mascara','select') then 'si (correcto)' else 'NO <-- MAL' end
union all select 'anon llama solicitar_cita',
  case when has_function_privilege('anon','public.solicitar_cita(jsonb)','execute') then 'si (correcto)' else 'NO <-- MAL' end
union all select 'anon llama fusionar_pacientes',
  case when has_function_privilege('anon','public.fusionar_pacientes(uuid,uuid,text)','execute') then 'SI <-- MAL' else 'no (correcto)' end;
