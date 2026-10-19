-- =============================================================================
-- 025c_listar_destinos.sql
-- Cambia listar_organizaciones_destino() para recibir p_org_origen uuid:
-- solo excluye la org que comparte (no todas las orgs donde el usuario
-- es gerente), permitiendo que un gerente de varias orgs comparta desde
-- una a las demás.
--
-- Cambios:
--   1. DROP de la versión sin parámetro (firma distinta → no es CREATE OR
--      REPLACE; hay que borrarla explícitamente antes de crear la nueva).
--   2. CREATE de listar_organizaciones_destino(p_org_origen uuid):
--      · Exige es_gerente_org(p_org_origen).
--      · Devuelve id + nombre (sin slug) de las demás orgs activas.
--
-- Reversible: 025c_rollback.sql.
-- Requisito previo: 025_fase4_compartir_recetas.sql y 025b aplicados.
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

-- ===========================================================================
-- 1. Eliminar versión anterior (sin parámetros, firma diferente)
-- ===========================================================================

drop function if exists public.listar_organizaciones_destino();


-- ===========================================================================
-- 2. Nueva versión con p_org_origen
-- ===========================================================================

create or replace function public.listar_organizaciones_destino(
  p_org_origen uuid
)
returns table (id uuid, nombre text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  -- Solo el gerente de la org origen puede listar destinos para esa org
  if not public.es_gerente_org(p_org_origen) then
    raise exception 'Solo el gerente de la organización puede listar destinos.';
  end if;

  return query
  select o.id, o.nombre
  from public.organizaciones o
  where o.activa = true
    -- Excluir únicamente la org que comparte, no todas las del gerente
    and o.id <> p_org_origen
  order by o.nombre;
end;
$$;

revoke execute on function public.listar_organizaciones_destino(uuid) from public, anon;
grant  execute on function public.listar_organizaciones_destino(uuid) to authenticated;

comment on function public.listar_organizaciones_destino(uuid)
  is 'Devuelve id + nombre de las orgs activas distintas a p_org_origen. '
     'Exige es_gerente_org(p_org_origen). Sin slug (no necesario para la UI).';


-- ===========================================================================
-- AUDITORÍA
-- ===========================================================================

-- Versión sin parámetro eliminada (0 filas):
select proname, pronargs
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname = 'listar_organizaciones_destino'
  and pronargs = 0;

-- Nueva versión con 1 parámetro creada (1 fila):
select proname, pronargs, prosecdef
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname = 'listar_organizaciones_destino'
  and pronargs = 1;

commit;
