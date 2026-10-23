-- =============================================================================
-- 027_rollback.sql
-- Rollback de 027_listar_miembros_org.sql.
-- =============================================================================

begin;

drop function if exists public.listar_miembros_org(uuid);

-- Verificación: función eliminada (0 filas)
select proname
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname = 'listar_miembros_org';

commit;
