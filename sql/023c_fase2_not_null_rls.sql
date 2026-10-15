-- =============================================================================
-- 023c_fase2_not_null_rls.sql
-- Fase 2 — PASO C: NOT NULL + swap completo de políticas RLS
-- =============================================================================
-- Cuándo ejecutar:
--   DESPUÉS de desplegar la nueva versión de la app (PASO B) que envía
--   organizacion_id en todos los inserts y filtra por él en los selects.
--   Si se ejecuta antes, los inserts de la app antigua fallarán por NOT NULL.
--
-- Fuente de verdad de las políticas eliminadas: politicas_actuales.csv
--   (exportación de pg_policies en producción antes de esta migración).
--
-- Qué hace:
--   1. Verifica que no hay NULLs en las cuatro tablas operativas.
--   2. Pone NOT NULL en recetas, menus, clientes, facturas.
--      INVENTARIO: se queda nullable permanentemente (catálogo global = NULL).
--   3. Elimina TODAS las políticas actuales de las 7 tablas operativas
--      (recetas, receta_ingredientes, menus, menu_recetas,
--       clientes, facturas, factura_lineas) usando los nombres exactos
--      del CSV de producción.
--   4. Crea las nuevas políticas basadas en es_miembro_org().
--
-- INVENTARIO: este script NO toca ninguna política de inventario.
--   Las políticas de inventario permanecen exactamente como están hoy.
--   El cambio de inventario es Fase 3 (024).
-- ⚠️  ALÉRGENOS: alergenos e ingrediente_alergenos no se tocan aquí.
--
-- Reversible: ejecutar 023c_rollback.sql.
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

-- ===========================================================================
-- VERIFICACIÓN PREVIA: abortar si quedan NULLs
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
-- 1. NOT NULL
--    inventario: NO se toca. Su organizacion_id queda nullable para siempre.
-- ===========================================================================

alter table public.recetas   alter column organizacion_id set not null;
alter table public.menus     alter column organizacion_id set not null;
alter table public.clientes  alter column organizacion_id set not null;
alter table public.facturas  alter column organizacion_id set not null;


-- ===========================================================================
-- 2. ELIMINAR POLÍTICAS ACTUALES (nombres exactos del CSV de producción)
--    Se usan DROP IF EXISTS para idempotencia.
-- ===========================================================================

-- ---- recetas ---------------------------------------------------------------
-- Política en producción: roles {authenticated}, cmd SELECT/INSERT/UPDATE/DELETE
drop policy if exists recetas_select_propias on public.recetas;
drop policy if exists recetas_insert_propias on public.recetas;
drop policy if exists recetas_update_propias on public.recetas;
drop policy if exists recetas_delete_propias on public.recetas;

-- ---- receta_ingredientes ---------------------------------------------------
drop policy if exists receta_ingredientes_select_por_receta_propia on public.receta_ingredientes;
drop policy if exists receta_ingredientes_insert_por_receta_propia on public.receta_ingredientes;
drop policy if exists receta_ingredientes_update_por_receta_propia on public.receta_ingredientes;
drop policy if exists receta_ingredientes_delete_por_receta_propia on public.receta_ingredientes;

-- ---- menus -----------------------------------------------------------------
drop policy if exists menus_select_propios on public.menus;
drop policy if exists menus_insert_propios on public.menus;
drop policy if exists menus_update_propios on public.menus;
drop policy if exists menus_delete_propios on public.menus;

-- ---- menu_recetas ----------------------------------------------------------
drop policy if exists menu_recetas_select_por_menu_propio on public.menu_recetas;
drop policy if exists menu_recetas_insert_por_menu_propio on public.menu_recetas;
drop policy if exists menu_recetas_update_por_menu_propio on public.menu_recetas;
drop policy if exists menu_recetas_delete_por_menu_propio on public.menu_recetas;

-- ---- clientes --------------------------------------------------------------
-- Nota: en producción (CSV) el rol es {public}, no {authenticated}.
-- No hay política clientes_admin_all en producción.
drop policy if exists clientes_select_own on public.clientes;
drop policy if exists clientes_insert_own on public.clientes;
drop policy if exists clientes_update_own on public.clientes;
drop policy if exists clientes_delete_own on public.clientes;

-- ---- facturas --------------------------------------------------------------
-- Nota: en producción (CSV) el rol es {public}, no {authenticated}.
-- No hay política facturas_admin_all en producción.
drop policy if exists facturas_select_own on public.facturas;
drop policy if exists facturas_insert_own on public.facturas;
drop policy if exists facturas_update_own on public.facturas;
drop policy if exists facturas_delete_own on public.facturas;

-- ---- factura_lineas --------------------------------------------------------
-- Nota: en producción (CSV) el rol es {public}, no {authenticated}.
-- No hay política factura_lineas_admin_all en producción.
drop policy if exists factura_lineas_select_own on public.factura_lineas;
drop policy if exists factura_lineas_insert_own on public.factura_lineas;
drop policy if exists factura_lineas_update_own on public.factura_lineas;
drop policy if exists factura_lineas_delete_own on public.factura_lineas;


-- ===========================================================================
-- 3. CREAR NUEVAS POLÍTICAS POR es_miembro_org()
--    Todas usan to authenticated; los admins de plataforma tienen acceso
--    total a través de la política _admin_all donde corresponda.
-- ===========================================================================

-- ---- recetas ---------------------------------------------------------------

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

create policy recetas_admin_all
  on public.recetas for all to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));

-- ---- receta_ingredientes ---------------------------------------------------
-- Hereda la organización de la receta madre vía EXISTS.

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

-- ---- menus -----------------------------------------------------------------

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

-- ---- menu_recetas ----------------------------------------------------------

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

-- ---- clientes --------------------------------------------------------------
-- Las políticas antiguas usaban rol {public} (sin cláusula TO en producción).
-- Las nuevas usan to authenticated, que es más restrictivo y correcto.

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

-- ---- facturas --------------------------------------------------------------

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

-- ---- factura_lineas --------------------------------------------------------

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
-- AUDITORÍA POST-PASO C
-- ===========================================================================

-- 1. NOT NULL activo en las cuatro tablas:
select table_name, column_name, is_nullable
from information_schema.columns
where table_schema = 'public'
  and column_name  = 'organizacion_id'
  and table_name   in ('recetas','menus','clientes','facturas','inventario')
order by table_name;
-- Esperado: recetas/menus/clientes/facturas → NO; inventario → YES

-- 2. Ninguna política antigua debe quedar:
select tablename, policyname
from pg_policies
where schemaname = 'public'
  and tablename  in (
    'recetas','receta_ingredientes','menus','menu_recetas',
    'clientes','facturas','factura_lineas'
  )
  and policyname not like '%_org'
  and policyname not like '%_admin_all';
-- Debe devolver 0 filas.

-- 3. Políticas nuevas creadas:
select tablename, policyname, cmd
from pg_policies
where schemaname = 'public'
  and tablename  in (
    'recetas','receta_ingredientes','menus','menu_recetas',
    'clientes','facturas','factura_lineas'
  )
order by tablename, cmd;


-- ===========================================================================
-- PRUEBA DE AISLAMIENTO (ejecutar DESPUÉS del commit, manualmente)
-- ===========================================================================
-- Requisitos:
--   a) Organización "Pruebas" (slug 'pruebas') creada desde la app.
--   b) Un usuario de prueba miembro de "Pruebas" (no de Samirarte).
--   c) Ese usuario ha creado al menos una receta y un cliente.
--   d) Un usuario chef de Samirarte para el test inverso.
-- Sustituir UUIDs reales antes de ejecutar.
-- ===========================================================================
/*
-- ── TEST 1: usuario de Pruebas no ve datos de Samirarte ──────────────────
set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"<uid_usuario_pruebas>","role":"authenticated"}';

select count(*) from public.recetas;    -- 0
select count(*) from public.menus;      -- 0
select count(*) from public.clientes;   -- 0
select count(*) from public.facturas;   -- 0

-- Intento de insertar en Samirarte → policy violation:
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

-- ── TEST 3: chef de Samirarte ve TODO lo de Samirarte ────────────────────
set local "request.jwt.claims" to
  '{"sub":"<uid_chef_samirarte>","role":"authenticated"}';

select count(*) from public.recetas;    -- total recetas de Samirarte
select count(*) from public.menus;
select count(*) from public.clientes;
select count(*) from public.facturas;

-- ── TEST 4: inventario global visible para ambas organizaciones ──────────
set local "request.jwt.claims" to
  '{"sub":"<uid_usuario_pruebas>","role":"authenticated"}';
select count(*) from public.inventario;   -- total catálogo (> 0)

-- ── TEST 5: anon solo ve inventario ──────────────────────────────────────
set local role anon;
select count(*) from public.inventario;   -- > 0
select count(*) from public.recetas;      -- 0 (sin política para anon)
*/

commit;
