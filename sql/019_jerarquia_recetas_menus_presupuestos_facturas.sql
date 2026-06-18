-- 019_jerarquia_recetas_menus_presupuestos_facturas.sql
-- Jerarquia no destructiva: receta -> menu -> presupuesto/factura.
-- NO ejecutar automaticamente. Revisar y aplicar manualmente en Supabase.
-- Requiere las migraciones 013, 015, 016, 017 y 018.

-- ---------------------------------------------------------------------------
-- Recetas y menus: nombres explicitos sin eliminar columnas antiguas.
-- ---------------------------------------------------------------------------

alter table public.menu_recetas
  add column if not exists raciones_receta_en_menu numeric(12,3),
  add column if not exists observaciones text;

update public.menu_recetas
set raciones_receta_en_menu = raciones
where raciones_receta_en_menu is null;

alter table public.menus
  add column if not exists pax_referencia_menu integer;

-- TODO posterior a la migracion y verificacion:
-- - dejar de escribir menu_recetas.raciones desde la app;
-- - mantenerla temporalmente para compatibilidad con versiones antiguas;
-- - valorar retirar numero_comensales solo cuando todos los consumidores usen
--   pax_referencia_menu. No se elimina ni renombra ninguna columna aqui.

alter table public.recetas
  drop constraint if exists recetas_raciones_base_positivas;
alter table public.recetas
  add constraint recetas_raciones_base_positivas
  check (raciones_base > 0) not valid;

alter table public.recetas
  drop constraint if exists recetas_importes_no_negativos;
alter table public.recetas
  add constraint recetas_importes_no_negativos
  check (
    coste_total >= 0
    and precio_venta_sin_iva >= 0
    and precio_venta_con_iva >= 0
  ) not valid;

alter table public.receta_ingredientes
  drop constraint if exists receta_ingredientes_cantidad_positiva;
alter table public.receta_ingredientes
  add constraint receta_ingredientes_cantidad_positiva
  check (cantidad_bruta > 0) not valid;

alter table public.receta_ingredientes
  drop constraint if exists receta_ingredientes_importes_no_negativos;
alter table public.receta_ingredientes
  add constraint receta_ingredientes_importes_no_negativos
  check (precio_unidad >= 0 and coste_total >= 0) not valid;

alter table public.menu_recetas
  drop constraint if exists menu_recetas_raciones_positivas;
alter table public.menu_recetas
  add constraint menu_recetas_raciones_positivas
  check (raciones_receta_en_menu > 0) not valid;

alter table public.menus
  drop constraint if exists menus_importes_no_negativos;
alter table public.menus
  add constraint menus_importes_no_negativos
  check (coste_total >= 0 and precio_total >= 0) not valid;

-- ---------------------------------------------------------------------------
-- Presupuestos.
-- ---------------------------------------------------------------------------

create table if not exists public.presupuestos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  cliente_id uuid not null references public.clientes(id) on delete restrict,
  numero_presupuesto text,
  estado text not null default 'borrador',
  fecha_emision date not null default current_date,
  fecha_vencimiento date,
  concepto text,
  coste_total numeric(12,4) not null default 0,
  precio_total numeric(12,4) not null default 0,
  notas text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint presupuestos_importes_no_negativos
    check (coste_total >= 0 and precio_total >= 0)
);

create table if not exists public.presupuesto_menus (
  id uuid primary key default gen_random_uuid(),
  presupuesto_id uuid not null references public.presupuestos(id) on delete cascade,
  menu_id uuid not null references public.menus(id) on delete restrict,
  menu_nombre_snapshot text,
  cantidad_menu numeric(12,3) not null,
  coste_total_menu numeric(12,4) not null default 0,
  coste_linea_menu_presupuesto numeric(12,4) not null default 0,
  precio_total_menu numeric(12,4),
  precio_linea_menu_presupuesto numeric(12,4),
  observaciones text,
  orden integer not null default 0,
  created_at timestamptz not null default now(),
  constraint presupuesto_menus_cantidad_positiva check (cantidad_menu > 0),
  constraint presupuesto_menus_importes_no_negativos check (
    coste_total_menu >= 0
    and coste_linea_menu_presupuesto >= 0
    and (precio_total_menu is null or precio_total_menu >= 0)
    and (
      precio_linea_menu_presupuesto is null
      or precio_linea_menu_presupuesto >= 0
    )
  )
);

-- ---------------------------------------------------------------------------
-- Facturas: relacion congelada con menus y origen opcional en presupuesto.
-- ---------------------------------------------------------------------------

alter table public.facturas
  add column if not exists presupuesto_id uuid references public.presupuestos(id) on delete set null,
  add column if not exists coste_total numeric(12,4) not null default 0;

alter table public.facturas
  drop constraint if exists facturas_cliente_obligatorio;
alter table public.facturas
  add constraint facturas_cliente_obligatorio
  check (cliente_id is not null) not valid;

alter table public.facturas
  drop constraint if exists facturas_importes_no_negativos;
alter table public.facturas
  add constraint facturas_importes_no_negativos
  check (
    coste_total >= 0
    and base_imponible >= 0
    and iva_importe >= 0
    and total >= 0
  ) not valid;

create table if not exists public.factura_menus (
  id uuid primary key default gen_random_uuid(),
  factura_id uuid not null references public.facturas(id) on delete cascade,
  menu_id uuid not null references public.menus(id) on delete restrict,
  menu_nombre_snapshot text,
  cantidad_menu numeric(12,3) not null,
  coste_total_menu numeric(12,4) not null default 0,
  coste_linea_menu_factura numeric(12,4) not null default 0,
  precio_total_menu numeric(12,4),
  precio_linea_menu_factura numeric(12,4),
  observaciones text,
  orden integer not null default 0,
  created_at timestamptz not null default now(),
  constraint factura_menus_cantidad_positiva check (cantidad_menu > 0),
  constraint factura_menus_importes_no_negativos check (
    coste_total_menu >= 0
    and coste_linea_menu_factura >= 0
    and (precio_total_menu is null or precio_total_menu >= 0)
    and (
      precio_linea_menu_factura is null
      or precio_linea_menu_factura >= 0
    )
  )
);

create index if not exists idx_presupuestos_user_id
  on public.presupuestos(user_id);
create index if not exists idx_presupuestos_cliente_id
  on public.presupuestos(cliente_id);
create index if not exists idx_presupuesto_menus_presupuesto_id
  on public.presupuesto_menus(presupuesto_id);
create index if not exists idx_presupuesto_menus_menu_id
  on public.presupuesto_menus(menu_id);
create index if not exists idx_factura_menus_factura_id
  on public.factura_menus(factura_id);
create index if not exists idx_factura_menus_menu_id
  on public.factura_menus(menu_id);

drop trigger if exists trg_presupuestos_set_updated_at on public.presupuestos;
create trigger trg_presupuestos_set_updated_at
before update on public.presupuestos
for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS: las lineas heredan el propietario de su cabecera.
-- ---------------------------------------------------------------------------

alter table public.presupuestos enable row level security;
alter table public.presupuesto_menus enable row level security;
alter table public.factura_menus enable row level security;

drop policy if exists presupuestos_usuario_all on public.presupuestos;
create policy presupuestos_usuario_all
on public.presupuestos
for all
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists presupuesto_menus_usuario_all on public.presupuesto_menus;
create policy presupuesto_menus_usuario_all
on public.presupuesto_menus
for all
using (
  exists (
    select 1 from public.presupuestos p
    where p.id = presupuesto_menus.presupuesto_id
      and p.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.presupuestos p
    where p.id = presupuesto_menus.presupuesto_id
      and p.user_id = auth.uid()
  )
);

drop policy if exists factura_menus_usuario_all on public.factura_menus;
create policy factura_menus_usuario_all
on public.factura_menus
for all
using (
  exists (
    select 1 from public.facturas f
    where f.id = factura_menus.factura_id
      and f.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.facturas f
    where f.id = factura_menus.factura_id
      and f.user_id = auth.uid()
  )
);

drop policy if exists presupuestos_admin_all on public.presupuestos;
create policy presupuestos_admin_all
on public.presupuestos
for all
to authenticated
using (public.es_admin_app(auth.uid()))
with check (public.es_admin_app(auth.uid()));

drop policy if exists presupuesto_menus_admin_all on public.presupuesto_menus;
create policy presupuesto_menus_admin_all
on public.presupuesto_menus
for all
to authenticated
using (public.es_admin_app(auth.uid()))
with check (public.es_admin_app(auth.uid()));

drop policy if exists factura_menus_admin_all on public.factura_menus;
create policy factura_menus_admin_all
on public.factura_menus
for all
to authenticated
using (public.es_admin_app(auth.uid()))
with check (public.es_admin_app(auth.uid()));

comment on column public.menu_recetas.raciones_receta_en_menu is
  'Raciones propias de esta receta dentro del menu; no depende del pax informativo.';
comment on column public.menus.pax_referencia_menu is
  'Estimacion informativa de asistentes; no multiplica ni sustituye raciones de recetas.';
comment on table public.presupuestos is
  'Presupuestos vinculados obligatoriamente a un cliente.';
comment on table public.presupuesto_menus is
  'Menus e importes congelados incluidos en un presupuesto.';
comment on table public.factura_menus is
  'Menus e importes congelados incluidos en una factura.';
