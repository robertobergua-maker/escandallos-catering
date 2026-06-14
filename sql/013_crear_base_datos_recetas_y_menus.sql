-- Esquema base no destructivo para recetas y menus.
--
-- Reglas:
-- - No elimina datos ni tablas.
-- - No crea FK de codigo_ingrediente contra inventario.codigo todavia.
-- - Prepara user_id para un futuro sistema de usuarios.

create extension if not exists pgcrypto;

create table if not exists public.recetas (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  codigo_receta text,
  nombre text not null,
  categoria text,
  tipo_plato text,
  raciones_base numeric(12, 3) not null default 1,
  unidad_servicio text,
  descripcion text,
  elaboracion text,
  observaciones text,
  costes_indirectos_pct numeric(8, 4) not null default 0,
  margen_beneficio_pct numeric(8, 4) not null default 0,
  iva_pct numeric(8, 4) not null default 0,
  coste_total numeric(12, 4) not null default 0,
  precio_venta_sin_iva numeric(12, 4) not null default 0,
  precio_venta_con_iva numeric(12, 4) not null default 0,
  activa boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.receta_ingredientes (
  id uuid primary key default gen_random_uuid(),
  receta_id uuid not null references public.recetas(id) on delete cascade,
  codigo_ingrediente text,
  descripcion_ingrediente text,
  cantidad_bruta numeric(12, 4) not null default 0,
  unidad_medida text,
  merma numeric(8, 4) not null default 0,
  cantidad_neta numeric(12, 4) not null default 0,
  precio_unidad numeric(12, 4) not null default 0,
  coste_total numeric(12, 4) not null default 0,
  orden integer not null default 0,
  es_temporal boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.menus (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  nombre text not null,
  tipo_menu text,
  descripcion text,
  numero_comensales integer not null default 1,
  coste_total numeric(12, 4) not null default 0,
  precio_total numeric(12, 4) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.menu_recetas (
  id uuid primary key default gen_random_uuid(),
  menu_id uuid not null references public.menus(id) on delete cascade,
  receta_id uuid not null references public.recetas(id) on delete cascade,
  raciones numeric(12, 3) not null default 1,
  orden integer not null default 0,
  seccion text,
  created_at timestamptz not null default now()
);

-- Comprobacion:
-- select table_schema, table_name
-- from information_schema.tables
-- where table_schema = 'public'
--   and table_name in ('recetas', 'receta_ingredientes', 'menus', 'menu_recetas')
-- order by table_name;
