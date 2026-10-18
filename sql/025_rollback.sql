-- =============================================================================
-- 025_rollback.sql
-- Rollback completo de la Fase 4 (025_fase4_compartir_recetas.sql).
-- Devuelve la BD al estado anterior sin comparticiones ni columnas de trazabilidad.
-- =============================================================================
-- Qué hace:
--   1. Elimina las funciones creadas en 025.
--   2. Elimina la tabla comparticiones (y sus índices/políticas en cascada).
--   3. Elimina la columna inventario.copiado_de_codigo.
--   4. Elimina la columna recetas.copiada_de.
--
-- Qué NO hace:
--   • No toca tablas operativas (recetas, receta_ingredientes, inventario)
--     más allá de las columnas añadidas. Las filas copiadas permanecen.
--   • No revierte las copias ya hechas: las recetas copiadas quedan en la
--     org destino con copiada_de = NULL tras el DROP COLUMN.
--   • No revierte los ingredientes privados creados durante la copia.
--
-- ⚠️  DATOS: los ingredientes privados creados en la org destino durante
--    la copia (con copiado_de_codigo relleno) conservarán sus datos pero
--    perderán la trazabilidad al eliminarse la columna. Exportar antes si
--    hay que conservar esa información.
--
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

-- ===========================================================================
-- 1. ELIMINAR FUNCIONES
-- ===========================================================================

drop function if exists public.copiar_receta_a_org(uuid, uuid);
drop function if exists public.ver_receta_compartida(uuid, uuid);
drop function if exists public.listar_recetas_compartidas_conmigo(uuid);
drop function if exists public.listar_organizaciones_destino();
drop function if exists public._comparticion_activa_para_org(uuid, uuid);


-- ===========================================================================
-- 2. ELIMINAR TABLA comparticiones (con sus políticas e índices en cascada)
-- ===========================================================================

drop index  if exists public.idx_comparticiones_activa;
drop index  if exists public.idx_comparticiones_origen;
drop index  if exists public.idx_comparticiones_destino_org;
drop index  if exists public.idx_comparticiones_objeto;
drop table  if exists public.comparticiones;


-- ===========================================================================
-- 3. ELIMINAR COLUMNA inventario.copiado_de_codigo
-- ===========================================================================

drop index  if exists public.idx_inventario_copiado_de_codigo;
alter table public.inventario drop column if exists copiado_de_codigo;


-- ===========================================================================
-- 4. ELIMINAR COLUMNA recetas.copiada_de
-- ===========================================================================

drop index  if exists public.idx_recetas_copiada_de;
alter table public.recetas drop column if exists copiada_de;


-- ===========================================================================
-- VERIFICACIÓN POST-ROLLBACK
-- ===========================================================================

-- Tabla comparticiones eliminada (0 filas):
select count(*) as tablas_comparticiones
from information_schema.tables
where table_schema = 'public' and table_name = 'comparticiones';

-- Columnas eliminadas (0 filas):
select table_name, column_name
from information_schema.columns
where table_schema = 'public'
  and (
    (table_name = 'recetas'    and column_name = 'copiada_de')
    or (table_name = 'inventario' and column_name = 'copiado_de_codigo')
  );

-- Funciones eliminadas (0 filas):
select proname
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname in (
    '_comparticion_activa_para_org',
    'listar_organizaciones_destino',
    'listar_recetas_compartidas_conmigo',
    'ver_receta_compartida',
    'copiar_receta_a_org'
  );

commit;
