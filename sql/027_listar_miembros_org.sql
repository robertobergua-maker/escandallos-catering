-- =============================================================================
-- 027_listar_miembros_org.sql
-- Función para que un GERENTE liste los miembros de su organización con el
-- email y nombre de cada uno.
--
-- MOTIVO: la política RLS de public.usuarios_app (017) solo deja leer la propia
-- fila (user_id = auth.uid()) o todas si eres admin de plataforma. Por eso, en
-- Gerente → Miembros, un gerente que no es admin ve el user_id en lugar del
-- email de los demás miembros. Esta función (SECURITY DEFINER) resuelve el
-- email/nombre sin cambiar el RLS de usuarios_app.
--
-- NO cambia el RLS de usuarios_app. Solo añade una función de lectura acotada a
-- los miembros de una organización de la que el llamador es GERENTE.
--
-- Requisitos previos: 017 (usuarios_app), 022 (organizaciones, es_gerente_org).
-- Reversible: 027_rollback.sql.
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

create or replace function public.listar_miembros_org(
  p_org uuid
)
returns table (
  id        uuid,
  user_id   uuid,
  email     text,
  nombre    text,
  rol       text,
  activo    boolean,
  joined_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  -- Solo el gerente de la organización puede listar sus miembros
  if not public.es_gerente_org(p_org) then
    raise exception 'Solo el gerente de la organización puede listar sus miembros.';
  end if;

  return query
  select
    om.id,
    om.user_id,
    ua.email,
    ua.nombre,
    om.rol,
    om.activo,
    om.joined_at
  from public.organizacion_miembros om
  left join public.usuarios_app ua on ua.user_id = om.user_id
  where om.organizacion_id = p_org
  order by om.joined_at;
end;
$$;

revoke execute on function public.listar_miembros_org(uuid) from public, anon;
grant  execute on function public.listar_miembros_org(uuid) to authenticated;

comment on function public.listar_miembros_org(uuid)
  is 'Lista los miembros de una organización (id, user_id, email, nombre, rol, '
     'activo, joined_at). SECURITY DEFINER: resuelve email/nombre de usuarios_app '
     'sin cambiar su RLS. Exige es_gerente_org(p_org). Solo authenticated.';

commit;
