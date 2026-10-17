-- =============================================================================
-- 024_rollback.sql
-- Rollback COMPLETO de la Fase 3 (024).
-- Devuelve la BD al estado anterior a ejecutar 024, como si nunca se hubiera
-- aplicado.
-- =============================================================================
-- FUENTE DE VERDAD para restaurar políticas:
--   • politicas_actuales.csv  — exportación real de pg_policies en producción
--     ANTES de la Fase 3. Columnas: tablename, policyname, cmd, roles, qual,
--     with_check.
--   • sql/021_rls_alergenos.sql — políticas originales de ingrediente_alergenos.
--
-- Políticas reales ANTES de 024 (de las capturas):
--   inventario:
--     "Usuarios autenticados pueden leer ingredientes"  SELECT {authenticated} true
--     inventario_insert_authenticated                   INSERT {authenticated} with check(true)
--     inventario_select_authenticated                   SELECT {authenticated} true
--     inventario_select_invitado                        SELECT {anon}          true
--     (NO existía inventario_admin_all en esta tabla)
--   ingrediente_alergenos:
--     ingrediente_alergenos_admin_all        ALL   {authenticated} using(es_admin_app) / with check(es_admin_app)
--     ingrediente_alergenos_insert_authenticated  INSERT {authenticated} with check(true)
--     ingrediente_alergenos_select_authenticated  SELECT {authenticated} true
--     ingrediente_alergenos_select_invitado       SELECT {anon}          true
--
-- Qué hace este rollback:
--   1. Elimina todas las políticas nuevas de inventario (creadas en 024).
--   2. Restaura exactamente las 4 políticas originales de inventario.
--      NO crea inventario_admin_all (no existía antes de 024).
--   3. Elimina todas las políticas nuevas de ingrediente_alergenos.
--   4. Restaura exactamente las 4 políticas originales de ingrediente_alergenos.
--   5. Elimina los triggers nuevos de inventario e ingrediente_alergenos.
--   6. Elimina las funciones nuevas (marcar_alergenos_revisados,
--      crear_ingrediente_privado, obtener_inventario_para_org,
--      _trg_inventario_protect_revisado, _trg_inventario_privado_no_borrar,
--      _trg_inventario_privado_no_cambiar_codigo,
--      _trg_alergenos_delete_reset_revisado).
--      NO restaura resolver_precio_ingrediente ni resolver_merma_ingrediente
--      (tampoco existían antes de 024).
--   7. Elimina inventario_org (tabla + trigger + índices).
--   8. Quita las columnas alergenos_revisados / _por / _at de inventario.
--      Solo si NO hay ingredientes privados con revisados=true (verificar antes).
--
-- ⚠️  ALÉRGENOS: este rollback restaura ingrediente_alergenos_insert_authenticated
--    (with check true — cualquier autenticado puede insertar alérgenos).
--    Es el comportamiento que existía en producción antes de la Fase 3.
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
-- 2. RESTAURAR POLÍTICAS ORIGINALES DE INVENTARIO
--    Fuente: politicas_actuales.csv (captura real de producción antes de F3).
--
--    Rol {authenticated} en el CSV → TO authenticated en SQL.
--    Rol {anon}          en el CSV → TO anon en SQL.
--    NO se crea inventario_admin_all: no existía en producción antes de 024.
-- ===========================================================================

-- Política con nombre con espacios, presente en producción (SELECT authenticated, using true)
create policy "Usuarios autenticados pueden leer ingredientes"
  on public.inventario for select to authenticated
  using (true);

-- SELECT authenticated (duplicado que existía junto a la anterior)
create policy inventario_select_authenticated
  on public.inventario for select to authenticated
  using (true);

-- SELECT anon (modo invitado)
create policy inventario_select_invitado
  on public.inventario for select to anon
  using (true);

-- INSERT authenticated con with check(true) — cualquier autenticado podía insertar
create policy inventario_insert_authenticated
  on public.inventario for insert to authenticated
  with check (true);


-- ===========================================================================
-- 3. ELIMINAR TRIGGERS NUEVOS DE INVENTARIO
-- ===========================================================================

drop trigger if exists trg_inventario_protect_revisado           on public.inventario;
drop trigger if exists trg_inventario_privado_no_borrar          on public.inventario;
drop trigger if exists trg_inventario_privado_no_cambiar_codigo  on public.inventario;


-- ===========================================================================
-- 4. ELIMINAR TRIGGERS NUEVOS DE ingrediente_alergenos
-- ===========================================================================

drop trigger if exists trg_alergenos_delete_reset_revisado on public.ingrediente_alergenos;


-- ===========================================================================
-- 5. ELIMINAR POLÍTICAS NUEVAS DE ingrediente_alergenos
-- ===========================================================================

drop policy if exists ingrediente_alergenos_select_authenticated     on public.ingrediente_alergenos;
drop policy if exists ingrediente_alergenos_select_invitado          on public.ingrediente_alergenos;
drop policy if exists ingrediente_alergenos_insert_gerente_o_admin   on public.ingrediente_alergenos;
drop policy if exists ingrediente_alergenos_update_gerente_o_admin   on public.ingrediente_alergenos;
drop policy if exists ingrediente_alergenos_delete_gerente_o_admin   on public.ingrediente_alergenos;
drop policy if exists ingrediente_alergenos_admin_all                on public.ingrediente_alergenos;


-- ===========================================================================
-- 6. RESTAURAR POLÍTICAS ORIGINALES DE ingrediente_alergenos
--    Fuente: sql/021_rls_alergenos.sql + politicas_actuales.csv.
-- ===========================================================================

-- SELECT authenticated: true (todos los autenticados ven alérgenos)
create policy ingrediente_alergenos_select_authenticated
  on public.ingrediente_alergenos for select to authenticated
  using (true);

-- SELECT anon: true (modo invitado también ve alérgenos)
create policy ingrediente_alergenos_select_invitado
  on public.ingrediente_alergenos for select to anon
  using (true);

-- ALL admin: solo el admin de plataforma puede escribir/borrar
create policy ingrediente_alergenos_admin_all
  on public.ingrediente_alergenos for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));

-- ⚠️  INSERT authenticated: restaura el permiso abierto original.
-- Cualquier autenticado podía insertar alérgenos a un ingrediente.
create policy ingrediente_alergenos_insert_authenticated
  on public.ingrediente_alergenos for insert to authenticated
  with check (true);


-- ===========================================================================
-- 7. ELIMINAR FUNCIONES CREADAS EN 024
--    NO se recrean resolver_precio_ingrediente ni resolver_merma_ingrediente:
--    tampoco existían antes de 024.
-- ===========================================================================

drop function if exists public.marcar_alergenos_revisados(text, boolean);
drop function if exists public.crear_ingrediente_privado(uuid, text, text, text);
drop function if exists public.obtener_inventario_para_org(uuid);
drop function if exists public._trg_inventario_protect_revisado();
drop function if exists public._trg_inventario_privado_no_borrar();
drop function if exists public._trg_inventario_privado_no_cambiar_codigo();
drop function if exists public._trg_alergenos_delete_reset_revisado();


-- ===========================================================================
-- 8. ELIMINAR inventario_org (tabla, trigger e índices)
--    Los precios migrados se pierden. Verificar antes si son necesarios.
-- ===========================================================================

drop trigger  if exists trg_inventario_org_set_updated_at on public.inventario_org;
drop index    if exists public.idx_inventario_org_org_codigo;
drop index    if exists public.idx_inventario_org_codigo;
drop table    if exists public.inventario_org;


-- ===========================================================================
-- 9. QUITAR COLUMNAS DE REVISIÓN DE ALÉRGENOS DE INVENTARIO
--    Verificar antes que no hay ingredientes privados con revisados = true
--    que se quiera conservar:
--      SELECT codigo, descripcion FROM inventario
--      WHERE organizacion_id IS NOT NULL AND alergenos_revisados = true;
--    Si hay filas con valor relevante, exportar antes de continuar.
-- ===========================================================================

alter table public.inventario
  drop column if exists alergenos_revisados,
  drop column if exists alergenos_revisados_por,
  drop column if exists alergenos_revisados_at;


-- ===========================================================================
-- VERIFICACIÓN POST-ROLLBACK
-- ===========================================================================

-- Políticas de inventario deben coincidir exactamente con las capturas:
select tablename, policyname, cmd, roles
from pg_policies
where schemaname = 'public'
  and tablename in ('inventario', 'ingrediente_alergenos')
order by tablename, policyname;
-- Esperado inventario (4 filas):
--   "Usuarios autenticados pueden leer ingredientes" SELECT {authenticated}
--   inventario_insert_authenticated                  INSERT {authenticated}
--   inventario_select_authenticated                  SELECT {authenticated}
--   inventario_select_invitado                       SELECT {anon}
-- Esperado ingrediente_alergenos (4 filas):
--   ingrediente_alergenos_admin_all              ALL    {authenticated}
--   ingrediente_alergenos_insert_authenticated   INSERT {authenticated}
--   ingrediente_alergenos_select_authenticated   SELECT {authenticated}
--   ingrediente_alergenos_select_invitado        SELECT {anon}

-- Columnas de revisión eliminadas (debe devolver 0 filas):
select column_name
from information_schema.columns
where table_schema = 'public'
  and table_name   = 'inventario'
  and column_name  in ('alergenos_revisados','alergenos_revisados_por','alergenos_revisados_at');

-- inventario_org eliminada (debe devolver 0 filas):
select table_name
from information_schema.tables
where table_schema = 'public' and table_name = 'inventario_org';

commit;
