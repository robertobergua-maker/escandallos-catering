-- =============================================================================
-- 023d_rollback.sql
-- Rollback de 023d: restaura las 7 políticas *_admin_all.
-- =============================================================================
-- Ejecutar si hay que volver al estado en que los admins de plataforma
-- tienen acceso total a todas las tablas operativas.
-- =============================================================================

begin;

create policy recetas_admin_all
  on public.recetas for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));

create policy receta_ingredientes_admin_all
  on public.receta_ingredientes for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));

create policy menus_admin_all
  on public.menus for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));

create policy menu_recetas_admin_all
  on public.menu_recetas for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));

create policy clientes_admin_all
  on public.clientes for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));

create policy facturas_admin_all
  on public.facturas for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));

create policy factura_lineas_admin_all
  on public.factura_lineas for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));

-- Verificación:
select tablename, policyname
from pg_policies
where schemaname = 'public'
  and policyname like '%_admin_all'
  and tablename in (
    'recetas','receta_ingredientes','menus','menu_recetas',
    'clientes','facturas','factura_lineas'
  )
order by tablename;
-- Debe mostrar 7 filas.

commit;
