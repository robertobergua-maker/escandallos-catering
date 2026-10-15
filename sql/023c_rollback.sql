-- =============================================================================
-- 023c_rollback.sql
-- Rollback del PASO C de la Fase 2.
-- Restaura EXACTAMENTE las políticas del CSV politicas_actuales.csv
-- (exportación real de pg_policies en producción antes de la Fase 2).
-- =============================================================================
-- Qué hace:
--   1. Revierte NOT NULL → nullable en recetas, menus, clientes, facturas.
--   2. Elimina las políticas _org y _admin_all creadas en 023c.
--   3. Restaura las políticas originales del CSV con los mismos nombres,
--      roles (incluyendo {public} donde el CSV lo indica), USING y WITH CHECK.
--
-- Qué NO hace:
--   • No toca inventario (no se modificó en 023c).
--   • No toca invitaciones ni crear/canjear_invitacion (creadas en 023a).
--   • No toca organizaciones ni organizacion_miembros (022).
--   • No toca alergenos ni ingrediente_alergenos. ⚠️  seguridad alimentaria.
--   • No borra la columna organizacion_id (creada en 023a, queda nullable).
--
-- Diferencias entre el CSV y las migraciones originales (documentadas):
--   • clientes, facturas, factura_lineas: en producción el rol era {public}
--     (sin cláusula TO en la política), no {authenticated}. El rollback
--     restaura el rol {public} tal como estaba.
--   • No existían políticas _admin_all en clientes, facturas ni factura_lineas.
--   • En inventario existía la política
--     "Usuarios autenticados pueden leer ingredientes" que no estaba en
--     ninguna migración. Esta política NO se toca (inventario no cambió).
--
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

-- ===========================================================================
-- 1. REVERTIR NOT NULL → NULLABLE
-- ===========================================================================

alter table public.recetas   alter column organizacion_id drop not null;
alter table public.menus     alter column organizacion_id drop not null;
alter table public.clientes  alter column organizacion_id drop not null;
alter table public.facturas  alter column organizacion_id drop not null;
-- inventario ya era nullable y no se tocó; no se cambia.


-- ===========================================================================
-- 2. ELIMINAR POLÍTICAS CREADAS EN 023c
-- ===========================================================================

-- recetas
drop policy if exists recetas_select_org  on public.recetas;
drop policy if exists recetas_insert_org  on public.recetas;
drop policy if exists recetas_update_org  on public.recetas;
drop policy if exists recetas_delete_org  on public.recetas;
drop policy if exists recetas_admin_all   on public.recetas;

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


-- ===========================================================================
-- 3. RESTAURAR POLÍTICAS EXACTAS DEL CSV
--    Fuente: politicas_actuales.csv (pg_policies exportado de producción).
--    Rol {public} → sin cláusula TO (equivalente en PostgreSQL).
--    Rol {authenticated} → TO authenticated.
-- ===========================================================================

-- ---- recetas (rol: authenticated) -----------------------------------------

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

-- ---- receta_ingredientes (rol: authenticated) ------------------------------

create policy receta_ingredientes_select_por_receta_propia
  on public.receta_ingredientes for select to authenticated
  using (
    exists (
      select 1 from public.recetas
      where recetas.id = receta_ingredientes.receta_id
        and recetas.user_id = auth.uid()
    )
  );

create policy receta_ingredientes_insert_por_receta_propia
  on public.receta_ingredientes for insert to authenticated
  with check (
    exists (
      select 1 from public.recetas
      where recetas.id = receta_ingredientes.receta_id
        and recetas.user_id = auth.uid()
    )
  );

create policy receta_ingredientes_update_por_receta_propia
  on public.receta_ingredientes for update to authenticated
  using (
    exists (
      select 1 from public.recetas
      where recetas.id = receta_ingredientes.receta_id
        and recetas.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.recetas
      where recetas.id = receta_ingredientes.receta_id
        and recetas.user_id = auth.uid()
    )
  );

create policy receta_ingredientes_delete_por_receta_propia
  on public.receta_ingredientes for delete to authenticated
  using (
    exists (
      select 1 from public.recetas
      where recetas.id = receta_ingredientes.receta_id
        and recetas.user_id = auth.uid()
    )
  );

-- ---- menus (rol: authenticated) -------------------------------------------

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

-- ---- menu_recetas (rol: authenticated) ------------------------------------

create policy menu_recetas_select_por_menu_propio
  on public.menu_recetas for select to authenticated
  using (
    exists (
      select 1 from public.menus
      where menus.id = menu_recetas.menu_id
        and menus.user_id = auth.uid()
    )
  );

create policy menu_recetas_insert_por_menu_propio
  on public.menu_recetas for insert to authenticated
  with check (
    exists (
      select 1 from public.menus
      where menus.id = menu_recetas.menu_id
        and menus.user_id = auth.uid()
    )
  );

create policy menu_recetas_update_por_menu_propio
  on public.menu_recetas for update to authenticated
  using (
    exists (
      select 1 from public.menus
      where menus.id = menu_recetas.menu_id
        and menus.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.menus
      where menus.id = menu_recetas.menu_id
        and menus.user_id = auth.uid()
    )
  );

create policy menu_recetas_delete_por_menu_propio
  on public.menu_recetas for delete to authenticated
  using (
    exists (
      select 1 from public.menus
      where menus.id = menu_recetas.menu_id
        and menus.user_id = auth.uid()
    )
  );

-- ---- clientes (rol: public — sin cláusula TO, igual que en producción) ----
-- El rol {public} en el CSV corresponde a una política sin TO, que en
-- PostgreSQL aplica a todos los roles (equivalente a FOR ALL ROLES).
-- Esto es lo que hay en producción según el CSV; se restaura tal cual.

create policy clientes_select_own
  on public.clientes for select
  using (user_id = auth.uid());

create policy clientes_insert_own
  on public.clientes for insert
  with check (user_id = auth.uid());

create policy clientes_update_own
  on public.clientes for update
  using    (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy clientes_delete_own
  on public.clientes for delete
  using (user_id = auth.uid());

-- ---- facturas (rol: public) ------------------------------------------------

create policy facturas_select_own
  on public.facturas for select
  using (user_id = auth.uid());

create policy facturas_insert_own
  on public.facturas for insert
  with check (user_id = auth.uid());

create policy facturas_update_own
  on public.facturas for update
  using    (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy facturas_delete_own
  on public.facturas for delete
  using (user_id = auth.uid());

-- ---- factura_lineas (rol: public) ------------------------------------------

create policy factura_lineas_select_own
  on public.factura_lineas for select
  using (
    exists (
      select 1 from public.facturas
      where facturas.id = factura_lineas.factura_id
        and facturas.user_id = auth.uid()
    )
  );

create policy factura_lineas_insert_own
  on public.factura_lineas for insert
  with check (
    exists (
      select 1 from public.facturas
      where facturas.id = factura_lineas.factura_id
        and facturas.user_id = auth.uid()
    )
  );

create policy factura_lineas_update_own
  on public.factura_lineas for update
  using (
    exists (
      select 1 from public.facturas
      where facturas.id = factura_lineas.factura_id
        and facturas.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.facturas
      where facturas.id = factura_lineas.factura_id
        and facturas.user_id = auth.uid()
    )
  );

create policy factura_lineas_delete_own
  on public.factura_lineas for delete
  using (
    exists (
      select 1 from public.facturas
      where facturas.id = factura_lineas.factura_id
        and facturas.user_id = auth.uid()
    )
  );


-- ===========================================================================
-- VERIFICACIÓN POST-ROLLBACK
-- ===========================================================================

-- 1. Sin políticas _org ni _admin_all en las 7 tablas:
select count(*) as politicas_023c_restantes
from pg_policies
where schemaname = 'public'
  and tablename  in (
    'recetas','receta_ingredientes','menus','menu_recetas',
    'clientes','facturas','factura_lineas'
  )
  and (policyname like '%_org' or policyname like '%_admin_all');
-- Debe devolver 0.

-- 2. Políticas restauradas (deben coincidir con el CSV):
select tablename, policyname, cmd, roles
from pg_policies
where schemaname = 'public'
  and tablename  in (
    'recetas','receta_ingredientes','menus','menu_recetas',
    'clientes','facturas','factura_lineas'
  )
order by tablename, policyname;

-- 3. organizacion_id volvió a ser nullable:
select table_name, is_nullable
from information_schema.columns
where table_schema = 'public'
  and column_name  = 'organizacion_id'
  and table_name   in ('recetas','menus','clientes','facturas')
order by table_name;
-- Esperado: YES en las cuatro.

commit;
