-- 017_usuarios_app_entorno.sql
-- Perfiles internos de la app y permisos para el entorno de administracion.
--
-- Flujo recomendado:
-- 1. Ejecuta este script en Supabase SQL.
-- 2. Inicia sesion una vez desde la app con el usuario que sera administrador.
-- 3. Promociona ese usuario con:
--    update public.usuarios_app
--    set rol = 'admin', activo = true
--    where email = 'admin@tu-dominio.com';
--
-- A partir de ahi, los admins podran gestionar roles desde la app.

create table if not exists public.usuarios_app (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  nombre text,
  rol text not null default 'usuario',
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint usuarios_app_rol_check check (rol in ('usuario', 'admin'))
);

create index if not exists usuarios_app_email_idx
on public.usuarios_app (lower(email));

create or replace function public.set_usuarios_app_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_usuarios_app_updated_at on public.usuarios_app;
create trigger set_usuarios_app_updated_at
before update on public.usuarios_app
for each row
execute function public.set_usuarios_app_updated_at();

create or replace function public.es_admin_app(uid uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.usuarios_app
    where user_id = uid
      and rol = 'admin'
      and activo = true
  );
$$;

alter table public.usuarios_app enable row level security;

drop policy if exists usuarios_app_select_self_or_admin on public.usuarios_app;
create policy usuarios_app_select_self_or_admin
on public.usuarios_app
for select
to authenticated
using (
  user_id = auth.uid()
  or public.es_admin_app(auth.uid())
);

drop policy if exists usuarios_app_insert_self on public.usuarios_app;
create policy usuarios_app_insert_self
on public.usuarios_app
for insert
to authenticated
with check (
  user_id = auth.uid()
  and rol = 'usuario'
  and activo = true
);

drop policy if exists usuarios_app_update_admin on public.usuarios_app;
create policy usuarios_app_update_admin
on public.usuarios_app
for update
to authenticated
using (public.es_admin_app(auth.uid()))
with check (public.es_admin_app(auth.uid()));

drop policy if exists usuarios_app_delete_admin on public.usuarios_app;
create policy usuarios_app_delete_admin
on public.usuarios_app
for delete
to authenticated
using (public.es_admin_app(auth.uid()));
