-- =============================================================================
-- 024_rollback.sql
-- Rollback completo de la Fase 3 (024).
-- Restaura EXACTAMENTE las políticas de inventario e ingrediente_alergenos
-- tal como estaban antes de ejecutar 024, usando como fuente de verdad:
--   • politicas_actuales.csv (exportación real de pg_policies antes de F3)
--   • sql/021_rls_alergenos.sql (políticas de ingrediente_alergenos)
--
-- ⚠️  ALÉRGENOS: este rollback restaura ingrediente_alergenos_insert_authenticated
--    (with check true). Asegúrate de que es el comportamiento deseado.
--
-- Qué hace:
--   1. Elimina las políticas nuevas de inventario e ingrediente_alergenos.
--   2. Restaura las políticas originales (CSV + 021).
--   3. Elimina las columnas de revisión de alérgenos de inventario.
--   4. Elimina la función crear_ingrediente_privado.
--   5. Restaura resolver_precio_ingrediente y resolver_merma_ingrediente.
--   6. Restaura obtener_inventario_para_org a la versión sin alergenos_revisados.
--   7. NO toca inventario_org (la tabla y sus datos se dejan; quitarla es
--      una decisión separada para no perder precios migrados).
--   8. NO toca los ingredientes privados creados (si los hay).
--
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

-- ===========================================================================
-- 1. ELIMINAR POLÍTICAS NUEVAS DE INVENTARIO (creadas en 024)
-- ===========================================================================

drop policy if exists inventario_select_authenticated      on public.inventario;
drop policy if exists inventario_select_invitado           on public.inventario;
drop policy if exists inventario_insert_gerente_o_admin    on public.inventario;
drop policy if exists inventario_update_gerente_o_admin    on public.inventario;
drop policy if exists inventario_delete_gerente_o_admin    on public.inventario;
drop policy if exists inventario_admin_all                 on public.inventario;


-- ===========================================================================
-- 2. RESTAURAR POLÍTICAS ORIGINALES DE INVENTARIO (del CSV)
--    Fuente: politicas_actuales.csv (exportación pre-F3)
--
--    Políticas del CSV para inventario:
--      "Usuarios autenticados pueden leer ingredientes" SELECT {authenticated} using(true)
--      inventario_insert_authenticated                  INSERT {authenticated} with check(true)
--      inventario_select_authenticated                  SELECT {authenticated} using(true)
--      inventario_select_invitado                       SELECT {anon}          using(true)
--
--    Nota: {public} en el CSV equivale a sin cláusula TO en PostgreSQL.
--    Nota: {authenticated} → TO authenticated.
-- ===========================================================================

-- Política duplicada presente en producción (nombre con espacios)
create policy "Usuarios autenticados pueden leer ingredientes"
  on public.inventario for select to authenticated
  using (true);

create policy inventario_select_authenticated
  on public.inventario for select to authenticated
  using (true);

create policy inventario_select_invitado
  on public.inventario for select to anon
  using (true);

create policy inventario_insert_authenticated
  on public.inventario for insert to authenticated
  with check (true);

-- inventario_admin_all (de la migración 018, presente en prod según 023c):
create policy inventario_admin_all
  on public.inventario for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));


-- ===========================================================================
-- 3. ELIMINAR POLÍTICAS NUEVAS DE ingrediente_alergenos (creadas en 024)
-- ===========================================================================

drop policy if exists ingrediente_alergenos_select_authenticated       on public.ingrediente_alergenos;
drop policy if exists ingrediente_alergenos_select_invitado            on public.ingrediente_alergenos;
drop policy if exists ingrediente_alergenos_insert_gerente_o_admin     on public.ingrediente_alergenos;
drop policy if exists ingrediente_alergenos_update_gerente_o_admin     on public.ingrediente_alergenos;
drop policy if exists ingrediente_alergenos_delete_gerente_o_admin     on public.ingrediente_alergenos;
drop policy if exists ingrediente_alergenos_admin_all                  on public.ingrediente_alergenos;


-- ===========================================================================
-- 4. RESTAURAR POLÍTICAS ORIGINALES DE ingrediente_alergenos (de 021)
--    Fuente: sql/021_rls_alergenos.sql
-- ===========================================================================

create policy ingrediente_alergenos_select_authenticated
  on public.ingrediente_alergenos for select to authenticated
  using (true);

create policy ingrediente_alergenos_admin_all
  on public.ingrediente_alergenos for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));

create policy ingrediente_alergenos_select_invitado
  on public.ingrediente_alergenos for select to anon
  using (true);

-- ⚠️  ALÉRGENOS: restaura el permiso de inserción abierto a todos los autenticados
create policy ingrediente_alergenos_insert_authenticated
  on public.ingrediente_alergenos for insert to authenticated
  with check (true);


-- ===========================================================================
-- 5. ELIMINAR COLUMNAS DE REVISIÓN DE ALÉRGENOS
--    Solo si NO hay ingredientes privados que dependan de ellas.
--    Si hay ingredientes privados con alergenos_revisados = true,
--    esto pierde esa información: valorar antes de ejecutar.
-- ===========================================================================

alter table public.inventario
  drop column if exists alergenos_revisados,
  drop column if exists alergenos_revisados_por,
  drop column if exists alergenos_revisados_at;


-- ===========================================================================
-- 6. ELIMINAR FUNCIÓN crear_ingrediente_privado
-- ===========================================================================

drop function if exists public.crear_ingrediente_privado(uuid, text, text, text);


-- ===========================================================================
-- 7. RESTAURAR resolver_precio_ingrediente y resolver_merma_ingrediente
--    (versiones originales de 024, sin verificación de membresía)
-- ===========================================================================

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
    (select io.precio_unidad from public.inventario_org io
     where io.codigo_ingrediente = p_codigo
       and io.organizacion_id    = p_organizacion_id
       and io.precio_unidad      is not null
     limit 1),
    (select i.precio_unidad from public.inventario i
     where i.codigo          = p_codigo
       and i.organizacion_id is null
       and i.precio_unidad   is not null
     limit 1)
  );
$$;

revoke execute on function public.resolver_precio_ingrediente(text, uuid) from public, anon;
grant  execute on function public.resolver_precio_ingrediente(text, uuid) to authenticated;

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
    (select io.merma from public.inventario_org io
     where io.codigo_ingrediente = p_codigo
       and io.organizacion_id    = p_organizacion_id
       and io.merma              is not null
     limit 1),
    (select i.merma from public.inventario i
     where i.codigo          = p_codigo
       and i.organizacion_id is null
       and i.merma           is not null
     limit 1)
  );
$$;

revoke execute on function public.resolver_merma_ingrediente(text, uuid) from public, anon;
grant  execute on function public.resolver_merma_ingrediente(text, uuid) to authenticated;


-- ===========================================================================
-- 8. RESTAURAR obtener_inventario_para_org (sin alergenos_revisados)
-- ===========================================================================

create or replace function public.obtener_inventario_para_org(
  p_organizacion_id uuid
)
returns table (
  codigo text, familia text, descripcion text, unidad_medida text,
  es_privado boolean,
  precio_unidad numeric, precio_es_propio boolean,
  merma numeric, merma_es_propia boolean,
  proveedor_precio text, formato_compra text,
  cantidad_formato_compra numeric, unidad_formato_compra text,
  precio_formato_compra numeric, url_precio text, observaciones_precio text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not (public.es_miembro_org(p_organizacion_id) or public.es_admin_app(auth.uid())) then
    raise exception 'Sin acceso a la organización indicada.';
  end if;
  return query
  select
    i.codigo, i.familia, i.descripcion, i.unidad_medida,
    (i.organizacion_id is not null),
    coalesce(io.precio_unidad, i.precio_unidad), (io.precio_unidad is not null),
    coalesce(io.merma, i.merma), (io.merma is not null),
    coalesce(io.proveedor_precio, i.proveedor_precio),
    coalesce(io.formato_compra, i.formato_compra),
    coalesce(io.cantidad_formato_compra, i.cantidad_formato_compra),
    coalesce(io.unidad_formato_compra, i.unidad_formato_compra),
    coalesce(io.precio_formato_compra, i.precio_formato_compra),
    coalesce(io.url_precio, i.url_precio),
    coalesce(io.observaciones_precio, i.observaciones_precio)
  from public.inventario i
  left join public.inventario_org io
         on io.codigo_ingrediente = i.codigo
        and io.organizacion_id    = p_organizacion_id
  where i.organizacion_id is null or i.organizacion_id = p_organizacion_id
  order by i.familia nulls last, i.descripcion;
end;
$$;

revoke execute on function public.obtener_inventario_para_org(uuid) from public, anon;
grant  execute on function public.obtener_inventario_para_org(uuid) to authenticated;


-- ===========================================================================
-- VERIFICACIÓN POST-ROLLBACK
-- ===========================================================================

-- Políticas de inventario restauradas (deben coincidir con el CSV):
select policyname, cmd, roles
from pg_policies
where schemaname = 'public' and tablename = 'inventario'
order by policyname;

-- Políticas de ingrediente_alergenos restauradas (deben coincidir con 021):
select policyname, cmd, roles
from pg_policies
where schemaname = 'public' and tablename = 'ingrediente_alergenos'
order by policyname;

-- Columnas de revisión eliminadas:
select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'inventario'
  and column_name in ('alergenos_revisados','alergenos_revisados_por','alergenos_revisados_at');
-- Debe devolver 0 filas.

commit;
