-- =============================================================================
-- 023c_fase2_not_null_rls.sql
-- Fase 2 — PASO C: NOT NULL + swap completo de políticas RLS
-- =============================================================================
-- Cuándo ejecutar este script:
--   DESPUÉS de desplegar la nueva versión de la app (PASO B) que envía
--   organizacion_id en todos los inserts y filtra por él en los selects.
--   Si se ejecuta antes del despliegue de la app, los inserts de la app
--   antigua fallarán por NOT NULL constraint.
--
-- Qué hace:
--   1. Verifica que no hay NULLs en las tablas operativas (aborta si los hay).
--   2. Pone NOT NULL en organizacion_id de recetas, menus, clientes, facturas.
--      INVENTARIO: se queda nullable (catálogo global = NULL es permanente).
--   3. Elimina las políticas RLS actuales (por user_id, de las migraciones
--      014, 016 y 018) y crea las nuevas (por es_miembro_org).
--   4. Las tablas hijas (receta_ingredientes, menu_recetas, factura_lineas)
--      heredan el aislamiento de su tabla madre vía EXISTS.
--   5. Inventario: actualiza las políticas para distinguir catálogo global
--      (organizacion_id IS NULL) de ingredientes privados (NOT NULL).
--      Esto NO cambia el comportamiento actual: todo el inventario es global.
--   6. Prueba de aislamiento documentada al final (ejecutar manualmente).
--
-- Requisitos previos: 022 y 023a aplicados, PASO B (app nueva) desplegado.
-- Reversible: sí — ejecutar 023c_rollback.sql.
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- ⚠️  ALÉRGENOS: este script no toca las tablas alergenos ni
--    ingrediente_alergenos. Sus políticas (migración 021) permanecen intactas.
-- =============================================================================

begin;

-- ===========================================================================
-- VERIFICACIÓN PREVIA: abortar si quedan NULLs
-- (significa que la app antigua todavía está escribiendo sin organizacion_id)
-- ===========================================================================

do $$
declare
  n_recetas   bigint;
  n_menus     bigint;
  n_clientes  bigint;
  n_facturas  bigint;
begin
  select count(*) into n_recetas  from public.recetas  where organizacion_id is null;
  select count(*) into n_menus    from public.menus    where organizacion_id is null;
  select count(*) into n_clientes from public.clientes where organizacion_id is null;
  select count(*) into n_facturas from public.facturas where organizacion_id is null;

  if n_recetas > 0 or n_menus > 0 or n_clientes > 0 or n_facturas > 0 then
    raise exception
      'Hay filas sin organizacion_id: recetas=%, menus=%, clientes=%, facturas=%. '
      'Ejecutar el backfill del 023a o esperar a que la app nueva haya escrito todos los datos.',
      n_recetas, n_menus, n_clientes, n_facturas;
  end if;

  raise notice 'Verificación OK: no hay NULLs en las tablas operativas.';
end;
$$;


-- ===========================================================================
-- 1. NOT NULL en recetas, menus, clientes, facturas
--    inventario: NO se pone NOT NULL (catálogo global = NULL es permanente).
-- ===========================================================================

alter table public.recetas   alter column organizacion_id set not null;
alter table public.menus     alter column organizacion_id set not null;
alter table public.clientes  alter column organizacion_id set not null;
alter table public.facturas  alter column organizacion_id set not null;

-- receta_ingredientes, menu_recetas, factura_lineas: sin organizacion_id propio.
-- Su aislamiento se hereda de la tabla madre (ver políticas más abajo).


-- ===========================================================================
-- 2. SWAP DE POLÍTICAS RLS — recetas
--    Elimina: recetas_select_propias, _insert_, _update_, _delete_ (de 014)
--             recetas_admin_all (de 018) → se recrea igual al final
--    Crea:    recetas_select_org, _insert_, _update_, _delete_
-- ===========================================================================

drop policy if exists recetas_select_propias on public.recetas;
drop policy if exists recetas_insert_propias on public.recetas;
drop policy if exists recetas_update_propias on public.recetas;
drop policy if exists recetas_delete_propias on public.recetas;
-- Nota: recetas_admin_all (018) se elimina y recrea para claridad;
-- su lógica no cambia.
drop policy if exists recetas_admin_all      on public.recetas;

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

-- Admin de plataforma: acceso total (igual que en 018)
create policy recetas_admin_all
  on public.recetas for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));


-- ===========================================================================
-- 3. SWAP — receta_ingredientes
--    Hereda de la receta madre vía EXISTS.
--    Elimina: receta_ingredientes_select_por_receta_propia etc. (014, 018)
-- ===========================================================================

drop policy if exists receta_ingredientes_select_por_receta_propia on public.receta_ingredientes;
drop policy if exists receta_ingredientes_insert_por_receta_propia on public.receta_ingredientes;
drop policy if exists receta_ingredientes_update_por_receta_propia on public.receta_ingredientes;
drop policy if exists receta_ingredientes_delete_por_receta_propia on public.receta_ingredientes;
drop policy if exists receta_ingredientes_admin_all                on public.receta_ingredientes;

create policy receta_ingredientes_select_org
  on public.receta_ingredientes for select to authenticated
  using (
    exists (
      select 1 from public.recetas r
      where r.id = receta_ingredientes.receta_id
        and public.es_miembro_org(r.organizacion_id)
    )
  );

create policy receta_ingredientes_insert_org
  on public.receta_ingredientes for insert to authenticated
  with check (
    exists (
      select 1 from public.recetas r
      where r.id = receta_ingredientes.receta_id
        and public.es_miembro_org(r.organizacion_id)
    )
  );

create policy receta_ingredientes_update_org
  on public.receta_ingredientes for update to authenticated
  using (
    exists (
      select 1 from public.recetas r
      where r.id = receta_ingredientes.receta_id
        and public.es_miembro_org(r.organizacion_id)
    )
  )
  with check (
    exists (
      select 1 from public.recetas r
      where r.id = receta_ingredientes.receta_id
        and public.es_miembro_org(r.organizacion_id)
    )
  );

create policy receta_ingredientes_delete_org
  on public.receta_ingredientes for delete to authenticated
  using (
    exists (
      select 1 from public.recetas r
      where r.id = receta_ingredientes.receta_id
        and public.es_miembro_org(r.organizacion_id)
    )
  );

create policy receta_ingredientes_admin_all
  on public.receta_ingredientes for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));


-- ===========================================================================
-- 4. SWAP — menus
-- ===========================================================================

drop policy if exists menus_select_propios on public.menus;
drop policy if exists menus_insert_propios on public.menus;
drop policy if exists menus_update_propios on public.menus;
drop policy if exists menus_delete_propios on public.menus;
drop policy if exists menus_admin_all      on public.menus;

create policy menus_select_org
  on public.menus for select to authenticated
  using (public.es_miembro_org(organizacion_id));

create policy menus_insert_org
  on public.menus for insert to authenticated
  with check (public.es_miembro_org(organizacion_id));

create policy menus_update_org
  on public.menus for update to authenticated
  using    (public.es_miembro_org(organizacion_id))
  with check (public.es_miembro_org(organizacion_id));

create policy menus_delete_org
  on public.menus for delete to authenticated
  using (public.es_miembro_org(organizacion_id));

create policy menus_admin_all
  on public.menus for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));


-- ===========================================================================
-- 5. SWAP — menu_recetas
-- ===========================================================================

drop policy if exists menu_recetas_select_por_menu_propio on public.menu_recetas;
drop policy if exists menu_recetas_insert_por_menu_propio on public.menu_recetas;
drop policy if exists menu_recetas_update_por_menu_propio on public.menu_recetas;
drop policy if exists menu_recetas_delete_por_menu_propio on public.menu_recetas;
drop policy if exists menu_recetas_admin_all              on public.menu_recetas;

create policy menu_recetas_select_org
  on public.menu_recetas for select to authenticated
  using (
    exists (
      select 1 from public.menus m
      where m.id = menu_recetas.menu_id
        and public.es_miembro_org(m.organizacion_id)
    )
  );

create policy menu_recetas_insert_org
  on public.menu_recetas for insert to authenticated
  with check (
    exists (
      select 1 from public.menus m
      where m.id = menu_recetas.menu_id
        and public.es_miembro_org(m.organizacion_id)
    )
  );

create policy menu_recetas_update_org
  on public.menu_recetas for update to authenticated
  using (
    exists (
      select 1 from public.menus m
      where m.id = menu_recetas.menu_id
        and public.es_miembro_org(m.organizacion_id)
    )
  )
  with check (
    exists (
      select 1 from public.menus m
      where m.id = menu_recetas.menu_id
        and public.es_miembro_org(m.organizacion_id)
    )
  );

create policy menu_recetas_delete_org
  on public.menu_recetas for delete to authenticated
  using (
    exists (
      select 1 from public.menus m
      where m.id = menu_recetas.menu_id
        and public.es_miembro_org(m.organizacion_id)
    )
  );

create policy menu_recetas_admin_all
  on public.menu_recetas for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));


-- ===========================================================================
-- 6. SWAP — clientes
-- ===========================================================================

drop policy if exists clientes_select_own on public.clientes;
drop policy if exists clientes_insert_own on public.clientes;
drop policy if exists clientes_update_own on public.clientes;
drop policy if exists clientes_delete_own on public.clientes;
drop policy if exists clientes_admin_all  on public.clientes;

create policy clientes_select_org
  on public.clientes for select to authenticated
  using (public.es_miembro_org(organizacion_id));

create policy clientes_insert_org
  on public.clientes for insert to authenticated
  with check (public.es_miembro_org(organizacion_id));

create policy clientes_update_org
  on public.clientes for update to authenticated
  using    (public.es_miembro_org(organizacion_id))
  with check (public.es_miembro_org(organizacion_id));

create policy clientes_delete_org
  on public.clientes for delete to authenticated
  using (public.es_miembro_org(organizacion_id));

create policy clientes_admin_all
  on public.clientes for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));


-- ===========================================================================
-- 7. SWAP — facturas
-- ===========================================================================

drop policy if exists facturas_select_own on public.facturas;
drop policy if exists facturas_insert_own on public.facturas;
drop policy if exists facturas_update_own on public.facturas;
drop policy if exists facturas_delete_own on public.facturas;
drop policy if exists facturas_admin_all  on public.facturas;

create policy facturas_select_org
  on public.facturas for select to authenticated
  using (public.es_miembro_org(organizacion_id));

create policy facturas_insert_org
  on public.facturas for insert to authenticated
  with check (public.es_miembro_org(organizacion_id));

create policy facturas_update_org
  on public.facturas for update to authenticated
  using    (public.es_miembro_org(organizacion_id))
  with check (public.es_miembro_org(organizacion_id));

create policy facturas_delete_org
  on public.facturas for delete to authenticated
  using (public.es_miembro_org(organizacion_id));

create policy facturas_admin_all
  on public.facturas for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));


-- ===========================================================================
-- 8. SWAP — factura_lineas
-- ===========================================================================

drop policy if exists factura_lineas_select_own on public.factura_lineas;
drop policy if exists factura_lineas_insert_own on public.factura_lineas;
drop policy if exists factura_lineas_update_own on public.factura_lineas;
drop policy if exists factura_lineas_delete_own on public.factura_lineas;
drop policy if exists factura_lineas_admin_all  on public.factura_lineas;

create policy factura_lineas_select_org
  on public.factura_lineas for select to authenticated
  using (
    exists (
      select 1 from public.facturas f
      where f.id = factura_lineas.factura_id
        and public.es_miembro_org(f.organizacion_id)
    )
  );

create policy factura_lineas_insert_org
  on public.factura_lineas for insert to authenticated
  with check (
    exists (
      select 1 from public.facturas f
      where f.id = factura_lineas.factura_id
        and public.es_miembro_org(f.organizacion_id)
    )
  );

create policy factura_lineas_update_org
  on public.factura_lineas for update to authenticated
  using (
    exists (
      select 1 from public.facturas f
      where f.id = factura_lineas.factura_id
        and public.es_miembro_org(f.organizacion_id)
    )
  )
  with check (
    exists (
      select 1 from public.facturas f
      where f.id = factura_lineas.factura_id
        and public.es_miembro_org(f.organizacion_id)
    )
  );

create policy factura_lineas_delete_org
  on public.factura_lineas for delete to authenticated
  using (
    exists (
      select 1 from public.facturas f
      where f.id = factura_lineas.factura_id
        and public.es_miembro_org(f.organizacion_id)
    )
  );

create policy factura_lineas_admin_all
  on public.factura_lineas for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));


-- ===========================================================================
-- 9. INVENTARIO: actualizar políticas para catálogo global / ingredientes privados
--    Sustituye las políticas de la migración 020 (inventario_select_authenticated,
--    inventario_select_invitado, inventario_insert_authenticated, inventario_admin_all).
--    El comportamiento ACTUAL no cambia: todo el inventario tiene
--    organizacion_id = NULL, así que todos los authenticated siguen viendo todo.
--    La distinción global/privado será visible solo cuando se añadan ingredientes
--    privados en la Fase 3.
-- ⚠️  ALÉRGENOS: alergenos e ingrediente_alergenos NO se tocan aquí.
-- ===========================================================================

drop policy if exists inventario_select_authenticated on public.inventario;
drop policy if exists inventario_select_invitado      on public.inventario;
drop policy if exists inventario_insert_authenticated on public.inventario;
drop policy if exists inventario_admin_all            on public.inventario;
-- Precaución: las de update/delete no existen en 020; se crean nuevas.
drop policy if exists inventario_update_org           on public.inventario;
drop policy if exists inventario_delete_org           on public.inventario;

-- Lectura: catálogo global (NULL) visible para todos los autenticados;
-- ingredientes privados solo para miembros de esa organización.
create policy inventario_select_authenticated
  on public.inventario for select to authenticated
  using (
    organizacion_id is null
    or public.es_miembro_org(organizacion_id)
  );

-- Modo invitado (anon): solo catálogo global → solo inventario + alérgenos.
create policy inventario_select_invitado
  on public.inventario for select to anon
  using (organizacion_id is null);

-- Insert: catálogo global solo admin; ingrediente privado cualquier miembro.
create policy inventario_insert_authenticated
  on public.inventario for insert to authenticated
  with check (
    (organizacion_id is null     and public.es_admin_app(auth.uid()))
    or
    (organizacion_id is not null and public.es_miembro_org(organizacion_id))
  );

create policy inventario_update_org
  on public.inventario for update to authenticated
  using (
    (organizacion_id is null     and public.es_admin_app(auth.uid()))
    or
    (organizacion_id is not null and public.es_miembro_org(organizacion_id))
  )
  with check (
    (organizacion_id is null     and public.es_admin_app(auth.uid()))
    or
    (organizacion_id is not null and public.es_miembro_org(organizacion_id))
  );

create policy inventario_delete_org
  on public.inventario for delete to authenticated
  using (
    (organizacion_id is null     and public.es_admin_app(auth.uid()))
    or
    (organizacion_id is not null and public.es_miembro_org(organizacion_id))
  );

create policy inventario_admin_all
  on public.inventario for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));


-- ===========================================================================
-- AUDITORÍA POST-PASO C
-- ===========================================================================

-- 1. Confirmar NOT NULL activo en las cuatro tablas:
select
  table_name,
  column_name,
  is_nullable
from information_schema.columns
where table_schema = 'public'
  and column_name  = 'organizacion_id'
  and table_name   in ('recetas', 'menus', 'clientes', 'facturas', 'inventario')
order by table_name;
-- Esperado: recetas/menus/clientes/facturas → NO; inventario → YES

-- 2. Confirmar que las políticas nuevas están activas:
select tablename, policyname
from pg_policies
where schemaname = 'public'
  and tablename in (
    'recetas','receta_ingredientes','menus','menu_recetas',
    'clientes','facturas','factura_lineas','inventario'
  )
order by tablename, policyname;
-- No debe aparecer ninguna política con sufijo _propias, _propios ni _own.
-- Sí deben aparecer las _org y _admin_all.


-- ===========================================================================
-- PRUEBA DE AISLAMIENTO (ejecutar DESPUÉS del commit, manualmente)
-- ===========================================================================
-- Requisitos:
--   a) Organización "Pruebas" (slug 'pruebas') creada desde la app.
--   b) Un usuario de prueba miembro de "Pruebas" (no de Samirarte).
--   c) Ese usuario ha creado al menos una receta y un cliente desde la app.
--   d) Un usuario chef de Samirarte para el test en sentido inverso.
--
-- Sustituir los UUIDs reales antes de ejecutar.
-- ===========================================================================
/*
-- ── TEST 1: usuario de Pruebas no ve datos de Samirarte ──────────────────
set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"<uid_usuario_pruebas>","role":"authenticated"}';

-- Debe devolver 0:
select count(*) from public.recetas;    -- 0 (no es miembro de Samirarte)
select count(*) from public.menus;      -- 0
select count(*) from public.clientes;   -- 0
select count(*) from public.facturas;   -- 0

-- Intento de leer con organizacion_id de Samirarte → 0 filas (no error):
select count(*) from public.recetas
where organizacion_id = (select id from public.organizaciones where slug='samirarte');

-- Intento de insertar en Samirarte → debe fallar con policy violation:
insert into public.recetas (organizacion_id, nombre, raciones_base)
values (
  (select id from public.organizaciones where slug='samirarte'),
  'Receta trampa', 1
);

-- ── TEST 2: usuario de Samirarte no ve datos de Pruebas ──────────────────
set local "request.jwt.claims" to
  '{"sub":"<uid_chef_samirarte>","role":"authenticated"}';

select count(*) from public.recetas
where organizacion_id = (select id from public.organizaciones where slug='pruebas');
-- Debe devolver 0.

-- ── TEST 3: chef de Samirarte ve TODOS los datos de Samirarte ────────────
set local "request.jwt.claims" to
  '{"sub":"<uid_chef_samirarte>","role":"authenticated"}';

select count(*) from public.recetas;    -- debe devolver el total de recetas de Samirarte
select count(*) from public.menus;
select count(*) from public.clientes;
select count(*) from public.facturas;

-- ── TEST 4: inventario global visible para todos ─────────────────────────
-- Como usuario de Pruebas:
set local "request.jwt.claims" to
  '{"sub":"<uid_usuario_pruebas>","role":"authenticated"}';
select count(*) from public.inventario where organizacion_id is null;
-- Debe devolver el total del catálogo (> 0).

-- ── TEST 5: modo invitado (anon) solo ve inventario ──────────────────────
set local role anon;
select count(*) from public.inventario;  -- > 0 (catálogo global)
select count(*) from public.recetas;     -- 0 (sin política para anon)
select count(*) from public.clientes;    -- 0
*/

commit;
