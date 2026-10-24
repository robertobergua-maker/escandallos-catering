-- =============================================================================
-- 028b_rollback.sql
-- Revierte 028b_bloquear_cambio_org_receta.sql:
-- elimina el trigger y la función.
-- =============================================================================

begin;

drop trigger if exists trg_bloquear_cambio_org_receta on public.recetas;
drop function if exists public.bloquear_cambio_organizacion_receta();

commit;
