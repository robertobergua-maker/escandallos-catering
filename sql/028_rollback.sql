-- =============================================================================
-- 028_rollback.sql
-- Deshace 028_recetas_por_chef.sql: vuelve a las políticas de 023c (cualquier
-- miembro activo ve y edita todas las recetas de su organización).
--
-- ⚠️ Borra la tabla receta_permisos y todos los permisos concedidos.
--    Los propietarios asignados (recetas.user_id) NO se deshacen.
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

-- 1. Políticas de recetas (023c)
drop policy if exists recetas_select_org on public.recetas;
drop policy if exists recetas_insert_org on public.recetas;
drop policy if exists recetas_update_org on public.recetas;
drop policy if exists recetas_delete_org on public.recetas;

create policy recetas_select_org
  on public.recetas for select to authenticated
  using (public.es_miembro_org(organizacion_id));

create policy recetas_insert_org
  on public.recetas for insert to authenticated
  with check (public.es_miembro_org(organizacion_id));

create policy recetas_update_org
  on public.recetas for update to authenticated
  using    (public.es_miembro_org(organizacion_id))
  with check (public.es_miembro_org(organizacion_id));

create policy recetas_delete_org
  on public.recetas for delete to authenticated
  using (public.es_miembro_org(organizacion_id));

-- 2. Políticas de receta_ingredientes (023c)
drop policy if exists receta_ingredientes_select_org on public.receta_ingredientes;
drop policy if exists receta_ingredientes_insert_org on public.receta_ingredientes;
drop policy if exists receta_ingredientes_update_org on public.receta_ingredientes;
drop policy if exists receta_ingredientes_delete_org on public.receta_ingredientes;

create policy receta_ingredientes_select_org
  on public.receta_ingredientes for select to authenticated
  using (exists (select 1 from public.recetas r
                 where r.id = receta_ingredientes.receta_id
                   and public.es_miembro_org(r.organizacion_id)));

create policy receta_ingredientes_insert_org
  on public.receta_ingredientes for insert to authenticated
  with check (exists (select 1 from public.recetas r
                      where r.id = receta_ingredientes.receta_id
                        and public.es_miembro_org(r.organizacion_id)));

create policy receta_ingredientes_update_org
  on public.receta_ingredientes for update to authenticated
  using (exists (select 1 from public.recetas r
                 where r.id = receta_ingredientes.receta_id
                   and public.es_miembro_org(r.organizacion_id)))
  with check (exists (select 1 from public.recetas r
                      where r.id = receta_ingredientes.receta_id
                        and public.es_miembro_org(r.organizacion_id)));

create policy receta_ingredientes_delete_org
  on public.receta_ingredientes for delete to authenticated
  using (exists (select 1 from public.recetas r
                 where r.id = receta_ingredientes.receta_id
                   and public.es_miembro_org(r.organizacion_id)));

-- 3. Trigger y funciones
drop trigger if exists trg_recetas_proteger_propietario on public.recetas;
drop function if exists public._trg_recetas_proteger_propietario();
drop function if exists public.conceder_permisos_recetas(uuid, uuid[], uuid[], uuid[], text);
drop function if exists public.revocar_permisos_recetas(uuid, uuid[]);
drop function if exists public.asignar_propietario_recetas(uuid, uuid[], uuid);
drop function if exists public.puede_ver_receta(uuid);
drop function if exists public.puede_editar_receta(uuid);

-- 4. Tabla de permisos
drop table if exists public.receta_permisos;

commit;
