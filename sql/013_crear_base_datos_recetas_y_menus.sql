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

-- ============================================================================
-- Updated_at automatico
-- ============================================================================

create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_recetas_set_updated_at on public.recetas;
create trigger trg_recetas_set_updated_at
before update on public.recetas
for each row
execute function public.set_updated_at();

drop trigger if exists trg_receta_ingredientes_set_updated_at on public.receta_ingredientes;
create trigger trg_receta_ingredientes_set_updated_at
before update on public.receta_ingredientes
for each row
execute function public.set_updated_at();

drop trigger if exists trg_menus_set_updated_at on public.menus;
create trigger trg_menus_set_updated_at
before update on public.menus
for each row
execute function public.set_updated_at();

-- ============================================================================
-- Indices
-- ============================================================================

create index if not exists idx_recetas_user_id on public.recetas(user_id);
create index if not exists idx_recetas_codigo on public.recetas(codigo_receta);
create index if not exists idx_recetas_nombre on public.recetas(nombre);
create index if not exists idx_receta_ingredientes_receta_id on public.receta_ingredientes(receta_id);
create index if not exists idx_receta_ingredientes_codigo on public.receta_ingredientes(codigo_ingrediente);
create index if not exists idx_menus_user_id on public.menus(user_id);
create index if not exists idx_menus_nombre on public.menus(nombre);
create index if not exists idx_menu_recetas_menu_id on public.menu_recetas(menu_id);
create index if not exists idx_menu_recetas_receta_id on public.menu_recetas(receta_id);

-- ============================================================================
-- Comentarios
-- ============================================================================

comment on table public.recetas is 'Fichas de recetas base con informacion culinaria, costes y precios calculados.';
comment on table public.receta_ingredientes is 'Lineas de ingredientes asociadas a una receta, con cantidades, mermas y coste por linea.';
comment on table public.menus is 'Menus compuestos por una o varias recetas, pensados para presupuestos por comensales.';
comment on table public.menu_recetas is 'Relacion entre menus y recetas, con raciones y orden de presentacion.';

comment on column public.recetas.id is 'Identificador unico de la receta.';
comment on column public.recetas.user_id is 'Usuario propietario de la receta para el futuro sistema de cuentas; queda a null si se elimina el usuario.';
comment on column public.recetas.codigo_receta is 'Codigo interno o visible de la receta.';
comment on column public.recetas.nombre is 'Nombre principal de la receta.';
comment on column public.recetas.categoria is 'Categoria operativa de la receta.';
comment on column public.recetas.tipo_plato is 'Tipo de plato o servicio al que pertenece la receta.';
comment on column public.recetas.raciones_base is 'Numero de raciones para las que estan expresadas las cantidades base de la receta.';
comment on column public.recetas.unidad_servicio is 'Unidad en la que se sirve o vende la receta.';
comment on column public.recetas.descripcion is 'Descripcion general de la receta.';
comment on column public.recetas.elaboracion is 'Proceso de elaboracion de la receta.';
comment on column public.recetas.observaciones is 'Notas internas o consideraciones adicionales.';
comment on column public.recetas.costes_indirectos_pct is 'Porcentaje de costes indirectos aplicado al coste de ingredientes.';
comment on column public.recetas.margen_beneficio_pct is 'Porcentaje de margen de beneficio usado para calcular el precio de venta.';
comment on column public.recetas.iva_pct is 'Porcentaje de IVA aplicado al precio de venta.';
comment on column public.recetas.coste_total is 'Coste total calculado de la receta.';
comment on column public.recetas.precio_venta_sin_iva is 'Precio de venta calculado antes de IVA.';
comment on column public.recetas.precio_venta_con_iva is 'Precio de venta calculado con IVA incluido.';
comment on column public.recetas.activa is 'Indica si la receta esta disponible para uso habitual.';
comment on column public.recetas.created_at is 'Fecha y hora de creacion del registro.';
comment on column public.recetas.updated_at is 'Fecha y hora de la ultima actualizacion del registro.';

comment on column public.receta_ingredientes.id is 'Identificador unico de la linea de ingrediente.';
comment on column public.receta_ingredientes.receta_id is 'Receta a la que pertenece esta linea de ingrediente.';
comment on column public.receta_ingredientes.codigo_ingrediente is 'Codigo del ingrediente tomado del inventario o escrito manualmente; aun no tiene clave foranea contra inventario.';
comment on column public.receta_ingredientes.descripcion_ingrediente is 'Descripcion del ingrediente usada en la receta.';
comment on column public.receta_ingredientes.cantidad_bruta is 'Cantidad inicial del ingrediente antes de aplicar merma o rendimiento.';
comment on column public.receta_ingredientes.unidad_medida is 'Unidad de medida de la cantidad usada en la receta.';
comment on column public.receta_ingredientes.merma is 'Porcentaje o factor de merma aplicado para obtener la cantidad neta.';
comment on column public.receta_ingredientes.cantidad_neta is 'Cantidad aprovechable del ingrediente despues de aplicar la merma.';
comment on column public.receta_ingredientes.precio_unidad is 'Precio unitario usado para calcular el coste de la linea, normalmente procedente del inventario.';
comment on column public.receta_ingredientes.coste_total is 'Coste calculado de esta linea de ingrediente.';
comment on column public.receta_ingredientes.orden is 'Orden de aparicion del ingrediente dentro de la receta.';
comment on column public.receta_ingredientes.es_temporal is 'Marca ingredientes introducidos manualmente o pendientes de vincular definitivamente con inventario.';
comment on column public.receta_ingredientes.created_at is 'Fecha y hora de creacion del registro.';
comment on column public.receta_ingredientes.updated_at is 'Fecha y hora de la ultima actualizacion del registro.';

comment on column public.menus.id is 'Identificador unico del menu.';
comment on column public.menus.user_id is 'Usuario propietario del menu para el futuro sistema de cuentas; queda a null si se elimina el usuario.';
comment on column public.menus.nombre is 'Nombre principal del menu.';
comment on column public.menus.tipo_menu is 'Tipo de menu o servicio.';
comment on column public.menus.descripcion is 'Descripcion general del menu.';
comment on column public.menus.numero_comensales is 'Numero de comensales previsto para el menu.';
comment on column public.menus.coste_total is 'Coste total calculado del menu.';
comment on column public.menus.precio_total is 'Precio total calculado del menu.';
comment on column public.menus.created_at is 'Fecha y hora de creacion del registro.';
comment on column public.menus.updated_at is 'Fecha y hora de la ultima actualizacion del registro.';

comment on column public.menu_recetas.id is 'Identificador unico de la relacion entre menu y receta.';
comment on column public.menu_recetas.menu_id is 'Menu al que pertenece la receta.';
comment on column public.menu_recetas.receta_id is 'Receta incluida en el menu.';
comment on column public.menu_recetas.raciones is 'Numero de raciones de esta receta que se incluyen en el menu.';
comment on column public.menu_recetas.orden is 'Orden de aparicion de la receta dentro del menu.';
comment on column public.menu_recetas.seccion is 'Seccion del menu donde se presenta la receta.';
comment on column public.menu_recetas.created_at is 'Fecha y hora de creacion del registro.';

-- Comprobacion:
-- select table_schema, table_name
-- from information_schema.tables
-- where table_schema = 'public'
--   and table_name in ('recetas', 'receta_ingredientes', 'menus', 'menu_recetas')
-- order by table_name;
