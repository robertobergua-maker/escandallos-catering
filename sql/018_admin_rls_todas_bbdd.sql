-- 018_admin_rls_todas_bbdd.sql
-- Permite que los usuarios con rol admin en public.usuarios_app gestionen
-- todas las tablas operativas desde la pagina de Administracion.
--
-- Requiere haber ejecutado antes sql/017_usuarios_app_entorno.sql.

-- ============================================================================
-- Recetas
-- ============================================================================

drop policy if exists recetas_admin_all on public.recetas;
create policy recetas_admin_all
on public.recetas
for all
to authenticated
using (public.es_admin_app(auth.uid()))
with check (public.es_admin_app(auth.uid()));

drop policy if exists receta_ingredientes_admin_all on public.receta_ingredientes;
create policy receta_ingredientes_admin_all
on public.receta_ingredientes
for all
to authenticated
using (public.es_admin_app(auth.uid()))
with check (public.es_admin_app(auth.uid()));

drop policy if exists menus_admin_all on public.menus;
create policy menus_admin_all
on public.menus
for all
to authenticated
using (public.es_admin_app(auth.uid()))
with check (public.es_admin_app(auth.uid()));

drop policy if exists menu_recetas_admin_all on public.menu_recetas;
create policy menu_recetas_admin_all
on public.menu_recetas
for all
to authenticated
using (public.es_admin_app(auth.uid()))
with check (public.es_admin_app(auth.uid()));

-- ============================================================================
-- Facturacion
-- ============================================================================

drop policy if exists clientes_admin_all on public.clientes;
create policy clientes_admin_all
on public.clientes
for all
to authenticated
using (public.es_admin_app(auth.uid()))
with check (public.es_admin_app(auth.uid()));

drop policy if exists facturas_admin_all on public.facturas;
create policy facturas_admin_all
on public.facturas
for all
to authenticated
using (public.es_admin_app(auth.uid()))
with check (public.es_admin_app(auth.uid()));

drop policy if exists factura_lineas_admin_all on public.factura_lineas;
create policy factura_lineas_admin_all
on public.factura_lineas
for all
to authenticated
using (public.es_admin_app(auth.uid()))
with check (public.es_admin_app(auth.uid()));

-- ============================================================================
-- Inventario
-- ============================================================================
-- El inventario era comun en la app. Si en tu proyecto activas RLS sobre esta
-- tabla, estas politicas dejan acceso completo solo a administradores.

drop policy if exists inventario_admin_all on public.inventario;
create policy inventario_admin_all
on public.inventario
for all
to authenticated
using (public.es_admin_app(auth.uid()))
with check (public.es_admin_app(auth.uid()));
