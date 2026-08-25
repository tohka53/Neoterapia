-- ============================================================================
-- Solo para pruebas locales en un Postgres limpio (NO se ejecuta en Supabase).
-- Reproduce lo minimo del entorno Supabase: roles, esquema auth y auth.uid().
-- ============================================================================

do $$ begin
  create role anon nologin noinherit;
exception when duplicate_object then null; end $$;

do $$ begin
  create role authenticated nologin noinherit;
exception when duplicate_object then null; end $$;

do $$ begin
  create role service_role nologin noinherit bypassrls;
exception when duplicate_object then null; end $$;

create schema if not exists auth;

create table if not exists auth.users (
  id    uuid primary key default gen_random_uuid(),
  email text unique
);

-- En Supabase auth.uid() lee el JWT. Aqui se lee una variable de sesion
-- para poder simular a cada rol desde las pruebas.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('neoterapia.test_uid', true), '')::uuid
$$;

grant usage on schema auth to anon, authenticated, service_role;
grant select on auth.users to authenticated, service_role;
