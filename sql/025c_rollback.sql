-- =============================================================================
-- 025c_rollback.sql
-- Rollback de 025c_listar_destinos.sql.
-- Restaura listar_organizaciones_destino() sin parámetros (versión 025).
-- =============================================================================

begin;

-- Eliminar versión con parámetro (025c)
drop function if exists public.listar_organizaciones_destino(uuid);

-- Restaurar versión sin parámetro (025 original)
create or replace function public.listar_organizaciones_destino()
returns table (id uuid, nombre text, slug text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_orgs_gerente uuid[];
begin
  select array_agg(om.organizacion_id)
  into v_orgs_gerente
  from public.organizacion_miembros om
  where om.user_id = auth.uid()
    and om.rol      = 'gerente'
    and om.activo   = true;

  if v_orgs_gerente is null or array_length(v_orgs_gerente, 1) = 0 then
    raise exception 'Solo los gerentes pueden listar organizaciones destino.';
  end if;

  return query
  select o.id, o.nombre, o.slug
  from public.organizaciones o
  where o.activa = true
    and o.id <> all(v_orgs_gerente)
  order by o.nombre;
end;
$$;

revoke execute on function public.listar_organizaciones_destino() from public, anon;
grant  execute on function public.listar_organizaciones_destino() to authenticated;

-- Verificación: versión 025 restaurada (1 fila, pronargs=0)
select proname, pronargs from pg_proc
where pronamespace = 'public'::regnamespace
  and proname = 'listar_organizaciones_destino';

commit;
