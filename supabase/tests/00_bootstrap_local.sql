-- ============================================================================
-- Solo para pruebas locales en un Postgres limpio (NO se ejecuta en Supabase).
-- Reproduce lo minimo del entorno Supabase: roles, esquema auth, auth.uid()
-- y una version reducida de auth.users / auth.identities con las columnas que
-- toca `crear_usuario_personal()`.
-- ============================================================================

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

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
  instance_id             uuid,
  id                      uuid primary key default gen_random_uuid(),
  aud                     varchar(255),
  role                    varchar(255),
  email                   varchar(255) unique,
  encrypted_password      varchar(255),
  email_confirmed_at      timestamptz,
  raw_app_meta_data       jsonb,
  raw_user_meta_data      jsonb,
  created_at              timestamptz default now(),
  updated_at              timestamptz default now(),
  confirmation_token      varchar(255) default '',
  recovery_token          varchar(255) default '',
  email_change            varchar(255) default '',
  email_change_token_new  varchar(255) default ''
);

create table if not exists auth.identities (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  provider_id     text not null,
  identity_data   jsonb not null,
  provider        text not null,
  last_sign_in_at timestamptz,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
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
