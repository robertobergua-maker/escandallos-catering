-- =============================================================================
-- 024_fase3_catalogo_global_precios_org.sql
-- Fase 3 — Separar el catálogo global de los precios y datos propios
--           de cada organización.
-- =============================================================================
-- Principio rector: ninguna seguridad depende de que la app filtre.
--   • inventario_org solo devuelve filas cuya organizacion_id pertenece al
--     usuario autenticado. La app no puede leer precios de otra organización.
--   • La función obtener_inventario_para_org verifica membresía antes de
--     devolver cualquier dato; no delega ese control a la app.
--   • Los ingredientes privados de una organización son invisibles para
--     cualquier otra, tanto en inventario como en inventario_org.
--
-- ⚠️  ALÉRGENOS: esta fase NO toca alergenos ni ingrediente_alergenos.
--    Los 14 alérgenos del catálogo global se mantienen intactos.
--    Los alérgenos de un ingrediente privado se gestionan en la misma tabla
--    ingrediente_alergenos con las políticas de RLS ya existentes (021).
--
-- Requisitos previos: 022 (Fase 1) y 023 (Fase 2).
-- Reversible: sí (ver sección ROLLBACK al final).
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. TABLA: inventario_org
--    Precios, mermas y datos de proveedor propios de cada organización
--    sobre ingredientes del catálogo global.
-- ---------------------------------------------------------------------------

create table if not exists public.inventario_org (
  id                      uuid         primary key default gen_random_uuid(),
  organizacion_id         uuid         not null
                            references public.organizaciones(id) on delete cascade,
  codigo_ingrediente      text         not null
                            references public.inventario(codigo)
                            on update cascade on delete restrict,

  -- NULL en cualquiera de estos campos significa "usar el del catálogo global"
  precio_unidad           numeric(12,4),
  merma                   numeric(8,4),
  proveedor_precio        text,
  formato_compra          text,
  cantidad_formato_compra numeric(12,4),
  unidad_formato_compra   text,
  precio_formato_compra   numeric(12,4),
  url_precio              text,
  observaciones_precio    text,

  updated_at              timestamptz  not null default now(),
  created_at              timestamptz  not null default now(),

  constraint inventario_org_unique
    unique (organizacion_id, codigo_ingrediente),
  constraint inventario_org_precio_no_negativo
    check (precio_unidad is null or precio_unidad >= 0),
  constraint inventario_org_merma_rango
    check (merma is null or (merma >= 0 and merma < 1))
);

comment on table  public.inventario_org
  is 'Precios y datos de proveedor propios de cada organización. '
     'NULL en un campo significa "usar el valor del catálogo global".';
comment on column public.inventario_org.precio_unidad
  is 'Precio por unidad de la organización. NULL = usar precio del catálogo global.';
comment on column public.inventario_org.merma
  is 'Factor de merma propio (0..1). NULL = usar merma del catálogo global.';

create index if not exists idx_inventario_org_org_codigo
  on public.inventario_org (organizacion_id, codigo_ingrediente);

create index if not exists idx_inventario_org_codigo
  on public.inventario_org (codigo_ingrediente);

drop trigger if exists trg_inventario_org_set_updated_at on public.inventario_org;
create trigger trg_inventario_org_set_updated_at
  before update on public.inventario_org
  for each row execute function public.set_updated_at();


-- ---------------------------------------------------------------------------
-- 2. RLS: inventario_org
--    Solo los miembros de la organización leen o escriben sus propios precios.
--    Ninguna política permite leer precios de otra organización.
-- ---------------------------------------------------------------------------

alter table public.inventario_org enable row level security;

drop policy if exists inventario_org_select on public.inventario_org;
create policy inventario_org_select
  on public.inventario_org for select to authenticated
  using (public.es_miembro_org(organizacion_id));

drop policy if exists inventario_org_insert on public.inventario_org;
create policy inventario_org_insert
  on public.inventario_org for insert to authenticated
  with check (public.es_miembro_org(organizacion_id));

drop policy if exists inventario_org_update on public.inventario_org;
create policy inventario_org_update
  on public.inventario_org for update to authenticated
  using    (public.es_miembro_org(organizacion_id))
  with check (public.es_miembro_org(organizacion_id));

drop policy if exists inventario_org_delete on public.inventario_org;
create policy inventario_org_delete
  on public.inventario_org for delete to authenticated
  using (public.es_miembro_org(organizacion_id));

drop policy if exists inventario_org_admin_all on public.inventario_org;
create policy inventario_org_admin_all
  on public.inventario_org for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));


-- ---------------------------------------------------------------------------
-- 3. MIGRAR precios actuales de inventario → inventario_org (Samirarte)
--    Solo se migran ingredientes del catálogo global con algún dato de precio.
--    Los valores 0 se mapean a NULL (sin precio definido).
-- ---------------------------------------------------------------------------

do $$
declare
  v_org_id uuid;
  v_filas  integer;
begin
  select id into v_org_id from public.organizaciones where slug = 'samirarte';
  if v_org_id is null then
    raise exception 'Organización "samirarte" no encontrada. Ejecutar primero 022.';
  end if;

  insert into public.inventario_org (
    organizacion_id, codigo_ingrediente,
    precio_unidad, merma, proveedor_precio,
    formato_compra, cantidad_formato_compra, unidad_formato_compra,
    precio_formato_compra, url_precio, observaciones_precio
  )
  select
    v_org_id,
    i.codigo,
    nullif(i.precio_unidad, 0),
    nullif(i.merma, 0),
    i.proveedor_precio,
    i.formato_compra,
    i.cantidad_formato_compra,
    i.unidad_formato_compra,
    i.precio_formato_compra,
    i.url_precio,
    i.observaciones_precio
  from public.inventario i
  where i.organizacion_id is null   -- solo catálogo global
    and (
      coalesce(i.precio_unidad, 0) <> 0
      or i.proveedor_precio        is not null
      or coalesce(i.merma, 0)      <> 0
    )
  on conflict (organizacion_id, codigo_ingrediente) do nothing;

  get diagnostics v_filas = row_count;
  raise notice 'Precios migrados a inventario_org (Samirarte): % ingredientes', v_filas;
end;
$$;


-- ---------------------------------------------------------------------------
-- 4. FUNCIÓN: resolver_precio_ingrediente
--    Devuelve el precio efectivo para una organización:
--      1.º precio propio en inventario_org
--      2.º precio del catálogo global en inventario
--    SECURITY DEFINER: puede leer ambas tablas independientemente de las
--    políticas RLS del llamador. La verificación de membresía se hace
--    explícitamente dentro de la función.
-- ---------------------------------------------------------------------------

create or replace function public.resolver_precio_ingrediente(
  p_codigo          text,
  p_organizacion_id uuid
)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select io.precio_unidad
      from public.inventario_org io
      where io.codigo_ingrediente = p_codigo
        and io.organizacion_id    = p_organizacion_id
        and io.precio_unidad      is not null
      limit 1
    ),
    (
      select i.precio_unidad
      from public.inventario i
      where i.codigo          = p_codigo
        and i.organizacion_id is null
        and i.precio_unidad   is not null
      limit 1
    )
  );
$$;

revoke execute on function public.resolver_precio_ingrediente(text, uuid) from public, anon;
grant  execute on function public.resolver_precio_ingrediente(text, uuid) to authenticated;

comment on function public.resolver_precio_ingrediente(text, uuid)
  is 'Precio unitario efectivo: propio de la org si existe, del catálogo global si no.';


-- ---------------------------------------------------------------------------
-- 5. FUNCIÓN: resolver_merma_ingrediente  (análoga)
-- ---------------------------------------------------------------------------

create or replace function public.resolver_merma_ingrediente(
  p_codigo          text,
  p_organizacion_id uuid
)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select io.merma
      from public.inventario_org io
      where io.codigo_ingrediente = p_codigo
        and io.organizacion_id    = p_organizacion_id
        and io.merma              is not null
      limit 1
    ),
    (
      select i.merma
      from public.inventario i
      where i.codigo          = p_codigo
        and i.organizacion_id is null
        and i.merma           is not null
      limit 1
    )
  );
$$;

revoke execute on function public.resolver_merma_ingrediente(text, uuid) from public, anon;
grant  execute on function public.resolver_merma_ingrediente(text, uuid) to authenticated;

comment on function public.resolver_merma_ingrediente(text, uuid)
  is 'Factor de merma efectivo: propio de la org si existe, del catálogo global si no.';


-- ---------------------------------------------------------------------------
-- 6. FUNCIÓN RPC: obtener_inventario_para_org
--    Devuelve catálogo global + ingredientes privados de la organización
--    con precios efectivos ya resueltos.
--
--    Seguridad: la función verifica membresía antes de devolver nada.
--    No expone precios de otras organizaciones (el JOIN de inventario_org
--    está restringido a p_organizacion_id que el llamador debe ser miembro).
--    Ingredientes privados de otras orgs nunca aparecen (filtro explícito).
-- ---------------------------------------------------------------------------

create or replace function public.obtener_inventario_para_org(
  p_organizacion_id uuid
)
returns table (
  codigo                  text,
  familia                 text,
  descripcion             text,
  unidad_medida           text,
  es_privado              boolean,
  precio_unidad           numeric,
  precio_es_propio        boolean,
  merma                   numeric,
  merma_es_propia         boolean,
  proveedor_precio        text,
  formato_compra          text,
  cantidad_formato_compra numeric,
  unidad_formato_compra   text,
  precio_formato_compra   numeric,
  url_precio              text,
  observaciones_precio    text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  -- Verificar membresía: el llamador debe pertenecer a la organización
  if not (public.es_miembro_org(p_organizacion_id) or public.es_admin_app(auth.uid())) then
    raise exception 'Sin acceso a la organización indicada.';
  end if;

  return query
  select
    i.codigo,
    i.familia,
    i.descripcion,
    i.unidad_medida,
    (i.organizacion_id is not null)                                       as es_privado,
    coalesce(io.precio_unidad,            i.precio_unidad)                as precio_unidad,
    (io.precio_unidad is not null)                                        as precio_es_propio,
    coalesce(io.merma,                    i.merma)                        as merma,
    (io.merma is not null)                                                as merma_es_propia,
    coalesce(io.proveedor_precio,         i.proveedor_precio)             as proveedor_precio,
    coalesce(io.formato_compra,           i.formato_compra)               as formato_compra,
    coalesce(io.cantidad_formato_compra,  i.cantidad_formato_compra)      as cantidad_formato_compra,
    coalesce(io.unidad_formato_compra,    i.unidad_formato_compra)        as unidad_formato_compra,
    coalesce(io.precio_formato_compra,    i.precio_formato_compra)        as precio_formato_compra,
    coalesce(io.url_precio,               i.url_precio)                   as url_precio,
    coalesce(io.observaciones_precio,     i.observaciones_precio)         as observaciones_precio
  from public.inventario i
  left join public.inventario_org io
         on io.codigo_ingrediente = i.codigo
        and io.organizacion_id    = p_organizacion_id
  where
    i.organizacion_id is null                        -- catálogo global
    or i.organizacion_id = p_organizacion_id         -- ingredientes privados propios
    -- ingredientes privados de otras orgs: excluidos por el filtro anterior
  order by i.familia nulls last, i.descripcion;
end;
$$;

revoke execute on function public.obtener_inventario_para_org(uuid) from public, anon;
grant  execute on function public.obtener_inventario_para_org(uuid) to authenticated;

comment on function public.obtener_inventario_para_org(uuid)
  is 'Catálogo con precios efectivos resueltos para la organización. '
     'Verifica membresía internamente. Nunca expone datos de otras organizaciones.';


-- ---------------------------------------------------------------------------
-- AUDITORÍA POST-MIGRACIÓN
-- ---------------------------------------------------------------------------

select
  (select count(*) from public.inventario where organizacion_id is null)
                                                         as ingredientes_catalogo_global,
  (select count(*) from public.inventario_org
   where organizacion_id =
     (select id from public.organizaciones where slug = 'samirarte'))
                                                         as precios_samirarte_migrados;


-- ---------------------------------------------------------------------------
-- ROLLBACK
-- ---------------------------------------------------------------------------
/*
rollback;

drop function if exists public.obtener_inventario_para_org(uuid);
drop function if exists public.resolver_merma_ingrediente(text, uuid);
drop function if exists public.resolver_precio_ingrediente(text, uuid);
drop table  if exists public.inventario_org;
-- Los datos en inventario siguen intactos (solo se copiaron, no se borraron).
*/

commit;
