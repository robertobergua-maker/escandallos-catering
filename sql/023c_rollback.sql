-- =============================================================================
-- 023c_rollback.sql
-- Rollback del PASO C de la Fase 2.
-- Restaura exactamente las políticas RLS de las migraciones 014, 016, 018
-- y 020, y revierte el NOT NULL a nullable.
-- =============================================================================
-- Cuándo ejecutar:
--   Si la prueba de aislamiento falla o la app tiene un problema grave
--   tras ejecutar 023c. Ejecutar INMEDIATAMENTE antes de que más datos
--   entren sin organizacion_id.
--
-- Lo que hace:
--   1. Revierte NOT NULL → nullable en recetas, menus, clientes, facturas.
--   2. Elimina las políticas _org creadas en 023c.
--   3. Restaura las políticas _propias/_own/_admin_all exactamente como
--      estaban en 014, 016 y 018.
--   4. Restaura las políticas de inventario exactamente como estaban en 020.
--
-- Lo que NO hace (y no debe hacer):
--   • No toca la tabla invitaciones ni las funciones crear/canjear_invitacion
--     (creadas en 023a, independientes del paso C).
--   • No toca las columnas organizacion_id (creadas en 023a); se dejan en
--     nullable para no perder el backfill de Samirarte.
--   • No toca organizaciones ni organizacion_miembros (022).
--   • No toca alergenos ni ingrediente_alergenos (021). ⚠️ seguridad alimentaria.
--
-- Tras este rollback la app antigua (basada en user_id) vuelve a funcionar.
-- La nueva versión de la app puede seguir en producción porque envía
-- organizacion_id igualmente; con columna nullable simplemente ya no es
-- obligatorio.
--
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

-- ===========================================================================
-- 1. REVERTIR NOT NULL → NULLABLE
-- ===========================================================================

alter table public.recetas  alter column organizacion_id drop not null;
alter table public.menus    alter column organizacion_id drop not null;
alter table public.clientes alter column organizacion_id drop not null;
alter table public.facturas alter column organizacion_id drop not null;
-- inventario ya era nullable; no se toca.


-- ===========================================================================
-- 2. ELIMINAR POLÍTICAS DEL PASO C
-- ===========================================================================

-- recetas
drop policy if exists recetas_select_org on public.recetas;
drop policy if exists recetas_insert_org on public.recetas;
drop policy if exists recetas_update_org on public.recetas;
drop policy if exists recetas_delete_org on public.recetas;
drop policy if exists recetas_admin_all  on public.recetas;

-- receta_ingredientes
drop policy if exists receta_ingredientes_select_org on public.receta_ingredientes;
drop policy if exists receta_ingredientes_insert_org on public.receta_ingredientes;
drop policy if exists receta_ingredientes_update_org on public.receta_ingredientes;
drop policy if exists receta_ingredientes_delete_org on public.receta_ingredientes;
drop policy if exists receta_ingredientes_admin_all  on public.receta_ingredientes;

-- menus
drop policy if exists menus_select_org on public.menus;
drop policy if exists menus_insert_org on public.menus;
drop policy if exists menus_update_org on public.menus;
drop policy if exists menus_delete_org on public.menus;
drop policy if exists menus_admin_all  on public.menus;

-- menu_recetas
drop policy if exists menu_recetas_select_org on public.menu_recetas;
drop policy if exists menu_recetas_insert_org on public.menu_recetas;
drop policy if exists menu_recetas_update_org on public.menu_recetas;
drop policy if exists menu_recetas_delete_org on public.menu_recetas;
drop policy if exists menu_recetas_admin_all  on public.menu_recetas;

-- clientes
drop policy if exists clientes_select_org on public.clientes;
drop policy if exists clientes_insert_org on public.clientes;
drop policy if exists clientes_update_org on public.clientes;
drop policy if exists clientes_delete_org on public.clientes;
drop policy if exists clientes_admin_all  on public.clientes;

-- facturas
drop policy if exists facturas_select_org on public.facturas;
drop policy if exists facturas_insert_org on public.facturas;
drop policy if exists facturas_update_org on public.facturas;
drop policy if exists facturas_delete_org on public.facturas;
drop policy if exists facturas_admin_all  on public.facturas;

-- factura_lineas
drop policy if exists factura_lineas_select_org on public.factura_lineas;
drop policy if exists factura_lineas_insert_org on public.factura_lineas;
drop policy if exists factura_lineas_update_org on public.factura_lineas;
drop policy if exists factura_lineas_delete_org on public.factura_lineas;
drop policy if exists factura_lineas_admin_all  on public.factura_lineas;

-- inventario (políticas del paso C)
drop policy if exists inventario_select_authenticated on public.inventario;
drop policy if exists inventario_select_invitado      on public.inventario;
drop policy if exists inventario_insert_authenticated on public.inventario;
drop policy if exists inventario_update_org           on public.inventario;
drop policy if exists inventario_delete_org           on public.inventario;
drop policy if exists inventario_admin_all            on public.inventario;


-- ===========================================================================
-- 3. RESTAURAR POLÍTICAS ORIGINALES DE 014 (recetas y menus)
-- ===========================================================================

-- ---- recetas (014) ---------------------------------------------------------
create policy recetas_select_propias
  on public.recetas for select to authenticated
  using (user_id = auth.uid());

create policy recetas_insert_propias
  on public.recetas for insert to authenticated
  with check (user_id = auth.uid());

create policy recetas_update_propias
  on public.recetas for update to authenticated
  using    (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy recetas_delete_propias
  on public.recetas for delete to authenticated
  using (user_id = auth.uid());

-- ---- receta_ingredientes (014) ---------------------------------------------
create policy receta_ingredientes_select_por_receta_propia
  on public.receta_ingredientes for select to authenticated
  using (
    exists (
      select 1 from public.recetas r
      where r.id = receta_ingredientes.receta_id
        and r.user_id = auth.uid()
    )
  );

create policy receta_ingredientes_insert_por_receta_propia
  on public.receta_ingredientes for insert to authenticated
  with check (
    exists (
      select 1 from public.recetas r
      where r.id = receta_ingredientes.receta_id
        and r.user_id = auth.uid()
    )
  );

create policy receta_ingredientes_update_por_receta_propia
  on public.receta_ingredientes for update to authenticated
  using (
    exists (
      select 1 from public.recetas r
      where r.id = receta_ingredientes.receta_id
        and r.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.recetas r
      where r.id = receta_ingredientes.receta_id
        and r.user_id = auth.uid()
    )
  );

create policy receta_ingredientes_delete_por_receta_propia
  on public.receta_ingredientes for delete to authenticated
  using (
    exists (
      select 1 from public.recetas r
      where r.id = receta_ingredientes.receta_id
        and r.user_id = auth.uid()
    )
  );

-- ---- menus (014) -----------------------------------------------------------
create policy menus_select_propios
  on public.menus for select to authenticated
  using (user_id = auth.uid());

create policy menus_insert_propios
  on public.menus for insert to authenticated
  with check (user_id = auth.uid());

create policy menus_update_propios
  on public.menus for update to authenticated
  using    (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy menus_delete_propios
  on public.menus for delete to authenticated
  using (user_id = auth.uid());

-- ---- menu_recetas (014) ----------------------------------------------------
create policy menu_recetas_select_por_menu_propio
  on public.menu_recetas for select to authenticated
  using (
    exists (
      select 1 from public.menus m
      where m.id = menu_recetas.menu_id
        and m.user_id = auth.uid()
    )
  );

create policy menu_recetas_insert_por_menu_propio
  on public.menu_recetas for insert to authenticated
  with check (
    exists (
      select 1 from public.menus m
      where m.id = menu_recetas.menu_id
        and m.user_id = auth.uid()
    )
  );

create policy menu_recetas_update_por_menu_propio
  on public.menu_recetas for update to authenticated
  using (
    exists (
      select 1 from public.menus m
      where m.id = menu_recetas.menu_id
        and m.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.menus m
      where m.id = menu_recetas.menu_id
        and m.user_id = auth.uid()
    )
  );

create policy menu_recetas_delete_por_menu_propio
  on public.menu_recetas for delete to authenticated
  using (
    exists (
      select 1 from public.menus m
      where m.id = menu_recetas.menu_id
        and m.user_id = auth.uid()
    )
  );


-- ===========================================================================
-- 4. RESTAURAR POLÍTICAS ORIGINALES DE 016 (clientes, facturas, factura_lineas)
-- ===========================================================================

-- ---- clientes (016) --------------------------------------------------------
create policy clientes_select_own
  on public.clientes for select to authenticated
  using (user_id = auth.uid());

create policy clientes_insert_own
  on public.clientes for insert to authenticated
  with check (user_id = auth.uid());

create policy clientes_update_own
  on public.clientes for update to authenticated
  using    (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy clientes_delete_own
  on public.clientes for delete to authenticated
  using (user_id = auth.uid());

-- ---- facturas (016) --------------------------------------------------------
create policy facturas_select_own
  on public.facturas for select to authenticated
  using (user_id = auth.uid());

create policy facturas_insert_own
  on public.facturas for insert to authenticated
  with check (user_id = auth.uid());

create policy facturas_update_own
  on public.facturas for update to authenticated
  using    (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy facturas_delete_own
  on public.facturas for delete to authenticated
  using (user_id = auth.uid());

-- ---- factura_lineas (016) --------------------------------------------------
create policy factura_lineas_select_own
  on public.factura_lineas for select to authenticated
  using (
    exists (
      select 1 from public.facturas f
      where f.id = factura_lineas.factura_id
        and f.user_id = auth.uid()
    )
  );

create policy factura_lineas_insert_own
  on public.factura_lineas for insert to authenticated
  with check (
    exists (
      select 1 from public.facturas f
      where f.id = factura_lineas.factura_id
        and f.user_id = auth.uid()
    )
  );

create policy factura_lineas_update_own
  on public.factura_lineas for update to authenticated
  using (
    exists (
      select 1 from public.facturas f
      where f.id = factura_lineas.factura_id
        and f.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.facturas f
      where f.id = factura_lineas.factura_id
        and f.user_id = auth.uid()
    )
  );

create policy factura_lineas_delete_own
  on public.factura_lineas for delete to authenticated
  using (
    exists (
      select 1 from public.facturas f
      where f.id = factura_lineas.factura_id
        and f.user_id = auth.uid()
    )
  );


-- ===========================================================================
-- 5. RESTAURAR POLÍTICAS ORIGINALES DE 018 (admin_all en todas las tablas)
-- ===========================================================================

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


-- ===========================================================================
-- 6. RESTAURAR POLÍTICAS ORIGINALES DE 020 (inventario)
-- ===========================================================================

create policy inventario_select_authenticated
  on public.inventario for select to authenticated
  using (true);

create policy inventario_select_invitado
  on public.inventario for select to anon
  using (true);

create policy inventario_insert_authenticated
  on public.inventario for insert to authenticated
  with check (true);

create policy inventario_admin_all
  on public.inventario for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));


-- ===========================================================================
-- VERIFICACIÓN POST-ROLLBACK
-- ===========================================================================

-- Confirmar que las políticas _org ya no existen:
select count(*) as politicas_org_restantes
from pg_policies
where schemaname = 'public'
  and policyname like '%_org';
-- Debe devolver 0.

-- Confirmar que las políticas originales están de vuelta:
select tablename, policyname
from pg_policies
where schemaname = 'public'
  and tablename in (
    'recetas','receta_ingredientes','menus','menu_recetas',
    'clientes','facturas','factura_lineas','inventario'
  )
order by tablename, policyname;

-- Confirmar que organizacion_id volvió a ser nullable:
select table_name, column_name, is_nullable
from information_schema.columns
where table_schema = 'public'
  and column_name  = 'organizacion_id'
  and table_name   in ('recetas','menus','clientes','facturas')
order by table_name;
-- Esperado: is_nullable = YES en las cuatro.

commit;
