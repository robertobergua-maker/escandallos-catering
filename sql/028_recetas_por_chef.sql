-- =============================================================================
-- 028_recetas_por_chef.sql
-- Recetas por chef dentro de una organización, con permisos que concede el
-- gerente.
--
-- ⚠️ CAMBIA PERMISOS (RLS) DE recetas Y receta_ingredientes.
--   Antes (023c): cualquier miembro activo de la org ve y edita todas las
--   recetas de la org.
--   Después:
--     • VER una receta (y sus ingredientes):
--         - el gerente de la org: todas;
--         - el propietario (recetas.user_id = auth.uid());
--         - un chef con permiso (receta_permisos) sobre esa receta o sobre
--           todas las recetas de su propietario;
--         - cualquier miembro, si la receta está en algún menú de la org
--           (los menús siguen siendo de la organización; sin esto los
--           alérgenos y fichas del menú saldrían incompletos).
--     • CREAR: cualquier miembro, como propietario (user_id = auth.uid());
--       el gerente puede crearla a nombre de otro miembro.
--     • EDITAR (y sus ingredientes): gerente, propietario o chef con permiso
--       de nivel 'edicion'. Solo el gerente cambia el propietario (trigger).
--     • BORRAR: gerente o propietario.
--   Menús, clientes y facturas NO cambian (siguen siendo de la organización).
--
-- ⚠️ EFECTO SOBRE DATOS EXISTENTES:
--   Las recetas actuales quedan del usuario que figura en recetas.user_id.
--   Las que tengan user_id NULL (antiguas) solo las verá el gerente (y todos,
--   si están en un menú) hasta que el gerente les asigne propietario con
--   asignar_propietario_recetas(). Revisar antes de aplicar con:
--     select organizacion_id, user_id, count(*) from public.recetas
--     group by 1, 2 order by 1, 2;
--
-- Funciones nuevas (todas SECURITY DEFINER, solo authenticated):
--   puede_ver_receta(uuid), puede_editar_receta(uuid),
--   conceder_permisos_recetas(...), revocar_permisos_recetas(...),
--   asignar_propietario_recetas(...).
--
-- Requisitos previos: 013, 022, 023c/023d.
-- Reversible: 028_rollback.sql.
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

-- ===========================================================================
-- 1. Tabla receta_permisos
--    Un permiso da a un chef acceso a UNA receta (receta_id) o a TODAS las
--    recetas de un propietario (propietario_id). Exactamente uno de los dos.
-- ===========================================================================

create table if not exists public.receta_permisos (
  id               uuid primary key default gen_random_uuid(),
  organizacion_id  uuid not null references public.organizaciones(id) on delete cascade,
  chef_id          uuid not null references auth.users(id) on delete cascade,
  propietario_id   uuid references auth.users(id) on delete cascade,
  receta_id        uuid references public.recetas(id) on delete cascade,
  nivel            text not null check (nivel in ('lectura', 'edicion')),
  concedido_por    uuid references auth.users(id) on delete set null default auth.uid(),
  created_at       timestamptz not null default now(),
  constraint receta_permisos_un_objetivo
    check ((propietario_id is null) <> (receta_id is null)),
  constraint receta_permisos_no_a_si_mismo
    check (propietario_id is null or propietario_id <> chef_id)
);

create unique index if not exists receta_permisos_uq_propietario
  on public.receta_permisos (organizacion_id, chef_id, propietario_id)
  where propietario_id is not null;

create unique index if not exists receta_permisos_uq_receta
  on public.receta_permisos (organizacion_id, chef_id, receta_id)
  where receta_id is not null;

create index if not exists receta_permisos_chef_idx
  on public.receta_permisos (chef_id);

comment on table public.receta_permisos
  is 'Permisos de un chef sobre recetas de otros miembros de su organización '
     '(una receta concreta o todas las de un propietario). Solo los gestiona '
     'el gerente, mediante conceder_permisos_recetas / revocar_permisos_recetas.';

alter table public.receta_permisos enable row level security;

-- Lectura: el gerente ve los permisos de su org; cada chef ve los suyos.
-- Escritura: solo mediante las funciones SECURITY DEFINER de abajo (no hay
-- políticas de insert/update/delete, así que desde la API quedan denegadas).
drop policy if exists receta_permisos_select on public.receta_permisos;
create policy receta_permisos_select
  on public.receta_permisos for select to authenticated
  using (public.es_gerente_org(organizacion_id) or chef_id = auth.uid());

revoke all on public.receta_permisos from anon;
grant select on public.receta_permisos to authenticated;


-- ===========================================================================
-- 2. Funciones de acceso
-- ===========================================================================

create or replace function public.puede_editar_receta(p_receta_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.recetas r
    where r.id = p_receta_id
      and public.es_miembro_org(r.organizacion_id)
      and (
        public.es_gerente_org(r.organizacion_id)
        or r.user_id = auth.uid()
        or exists (
          select 1
          from public.receta_permisos p
          where p.organizacion_id = r.organizacion_id
            and p.chef_id = auth.uid()
            and p.nivel = 'edicion'
            and (p.receta_id = r.id
                 or (p.propietario_id is not null and p.propietario_id = r.user_id))
        )
      )
  );
$$;

create or replace function public.puede_ver_receta(p_receta_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.recetas r
    where r.id = p_receta_id
      and public.es_miembro_org(r.organizacion_id)
      and (
        public.es_gerente_org(r.organizacion_id)
        or r.user_id = auth.uid()
        or exists (
          select 1
          from public.receta_permisos p
          where p.organizacion_id = r.organizacion_id
            and p.chef_id = auth.uid()
            and (p.receta_id = r.id
                 or (p.propietario_id is not null and p.propietario_id = r.user_id))
        )
        -- Recetas usadas en menús de la organización: visibles (solo lectura)
        -- para todos los miembros, porque los menús son de la organización.
        or exists (
          select 1
          from public.menu_recetas mr
          join public.menus m on m.id = mr.menu_id
          where mr.receta_id = r.id
            and m.organizacion_id = r.organizacion_id
        )
      )
  );
$$;

revoke execute on function public.puede_ver_receta(uuid)    from public, anon;
revoke execute on function public.puede_editar_receta(uuid) from public, anon;
grant  execute on function public.puede_ver_receta(uuid)    to authenticated;
grant  execute on function public.puede_editar_receta(uuid) to authenticated;

comment on function public.puede_ver_receta(uuid)
  is 'True si auth.uid() puede ver la receta: gerente, propietario, chef con '
     'permiso, o receta usada en un menú de la organización.';
comment on function public.puede_editar_receta(uuid)
  is 'True si auth.uid() puede editar la receta: gerente, propietario o chef '
     'con permiso de nivel edicion.';


-- ===========================================================================
-- 3. RLS de recetas (sustituye las políticas *_org de 023c)
-- ===========================================================================

drop policy if exists recetas_select_org on public.recetas;
drop policy if exists recetas_insert_org on public.recetas;
drop policy if exists recetas_update_org on public.recetas;
drop policy if exists recetas_delete_org on public.recetas;

create policy recetas_select_org
  on public.recetas for select to authenticated
  using (public.puede_ver_receta(id));

create policy recetas_insert_org
  on public.recetas for insert to authenticated
  with check (
    public.es_miembro_org(organizacion_id)
    and (user_id = auth.uid() or public.es_gerente_org(organizacion_id))
  );

create policy recetas_update_org
  on public.recetas for update to authenticated
  using      (public.puede_editar_receta(id))
  with check (public.es_miembro_org(organizacion_id));

create policy recetas_delete_org
  on public.recetas for delete to authenticated
  using (
    public.es_miembro_org(organizacion_id)
    and (public.es_gerente_org(organizacion_id) or user_id = auth.uid())
  );


-- ===========================================================================
-- 4. RLS de receta_ingredientes (heredan el acceso de la receta)
-- ===========================================================================

drop policy if exists receta_ingredientes_select_org on public.receta_ingredientes;
drop policy if exists receta_ingredientes_insert_org on public.receta_ingredientes;
drop policy if exists receta_ingredientes_update_org on public.receta_ingredientes;
drop policy if exists receta_ingredientes_delete_org on public.receta_ingredientes;

create policy receta_ingredientes_select_org
  on public.receta_ingredientes for select to authenticated
  using (public.puede_ver_receta(receta_id));

create policy receta_ingredientes_insert_org
  on public.receta_ingredientes for insert to authenticated
  with check (public.puede_editar_receta(receta_id));

create policy receta_ingredientes_update_org
  on public.receta_ingredientes for update to authenticated
  using      (public.puede_editar_receta(receta_id))
  with check (public.puede_editar_receta(receta_id));

create policy receta_ingredientes_delete_org
  on public.receta_ingredientes for delete to authenticated
  using (public.puede_editar_receta(receta_id));


-- ===========================================================================
-- 5. Trigger: solo el gerente cambia el propietario de una receta.
--    Sin sesión de usuario (SQL Editor / servicio) no se bloquea.
-- ===========================================================================

create or replace function public._trg_recetas_proteger_propietario()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null
     and new.user_id is distinct from old.user_id
     and not public.es_gerente_org(old.organizacion_id) then
    raise exception 'Solo el gerente puede cambiar el propietario de una receta.';
  end if;
  return new;
end;
$$;

revoke execute on function public._trg_recetas_proteger_propietario() from public, anon;

drop trigger if exists trg_recetas_proteger_propietario on public.recetas;
create trigger trg_recetas_proteger_propietario
  before update of user_id on public.recetas
  for each row
  execute function public._trg_recetas_proteger_propietario();


-- ===========================================================================
-- 6. Gestión de permisos (solo gerente), en bloque
-- ===========================================================================

-- Concede a varios chefs, a la vez, acceso a todas las recetas de varios
-- propietarios y/o a varias recetas concretas. Si el permiso ya existe, se
-- actualiza el nivel. Devuelve el número de permisos creados o actualizados.
create or replace function public.conceder_permisos_recetas(
  p_org          uuid,
  p_chefs        uuid[],
  p_propietarios uuid[],
  p_recetas      uuid[],
  p_nivel        text
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total integer := 0;
  v_n     integer := 0;
begin
  if not public.es_gerente_org(p_org) then
    raise exception 'Solo el gerente de la organización puede conceder permisos.';
  end if;
  if p_nivel is null or p_nivel not in ('lectura', 'edicion') then
    raise exception 'Nivel no válido: usa lectura o edicion.';
  end if;
  if coalesce(array_length(p_chefs, 1), 0) = 0 then
    raise exception 'Elige al menos un chef.';
  end if;
  if coalesce(array_length(p_propietarios, 1), 0) = 0
     and coalesce(array_length(p_recetas, 1), 0) = 0 then
    raise exception 'Elige al menos un propietario o una receta.';
  end if;

  -- Los chefs deben ser miembros activos de la organización.
  if exists (
    select 1 from unnest(p_chefs) c(id)
    where not exists (
      select 1 from public.organizacion_miembros om
      where om.organizacion_id = p_org and om.user_id = c.id and om.activo
    )
  ) then
    raise exception 'Algún chef elegido no es miembro activo de la organización.';
  end if;

  -- Las recetas deben ser de la organización.
  if exists (
    select 1 from unnest(coalesce(p_recetas, '{}')) x(id)
    where not exists (
      select 1 from public.recetas r where r.id = x.id and r.organizacion_id = p_org
    )
  ) then
    raise exception 'Alguna receta elegida no pertenece a la organización.';
  end if;

  -- Por propietario (se omite el caso chef = propietario).
  insert into public.receta_permisos (organizacion_id, chef_id, propietario_id, nivel)
  select p_org, c.id, pr.id, p_nivel
  from unnest(p_chefs) c(id)
  cross join unnest(coalesce(p_propietarios, '{}')) pr(id)
  where c.id <> pr.id
  on conflict (organizacion_id, chef_id, propietario_id) where propietario_id is not null
  do update set nivel = excluded.nivel, concedido_por = auth.uid();
  get diagnostics v_n = row_count;
  v_total := v_total + v_n;

  -- Por receta (se omite si el chef ya es su propietario).
  insert into public.receta_permisos (organizacion_id, chef_id, receta_id, nivel)
  select p_org, c.id, r.id, p_nivel
  from unnest(p_chefs) c(id)
  cross join unnest(coalesce(p_recetas, '{}')) x(id)
  join public.recetas r on r.id = x.id
  where r.user_id is distinct from c.id
  on conflict (organizacion_id, chef_id, receta_id) where receta_id is not null
  do update set nivel = excluded.nivel, concedido_por = auth.uid();
  get diagnostics v_n = row_count;
  v_total := v_total + v_n;

  return v_total;
end;
$$;

-- Quita varios permisos a la vez. Devuelve cuántos se han borrado.
create or replace function public.revocar_permisos_recetas(
  p_org uuid,
  p_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n integer := 0;
begin
  if not public.es_gerente_org(p_org) then
    raise exception 'Solo el gerente de la organización puede quitar permisos.';
  end if;
  delete from public.receta_permisos
  where organizacion_id = p_org
    and id = any(coalesce(p_ids, '{}'));
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- Asigna un propietario a varias recetas a la vez (p. ej. recetas antiguas
-- sin propietario). Devuelve cuántas recetas se han actualizado.
create or replace function public.asignar_propietario_recetas(
  p_org         uuid,
  p_recetas     uuid[],
  p_propietario uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n integer := 0;
begin
  if not public.es_gerente_org(p_org) then
    raise exception 'Solo el gerente de la organización puede asignar propietarios.';
  end if;
  if not exists (
    select 1 from public.organizacion_miembros om
    where om.organizacion_id = p_org and om.user_id = p_propietario and om.activo
  ) then
    raise exception 'El nuevo propietario no es miembro activo de la organización.';
  end if;
  update public.recetas
     set user_id = p_propietario
   where organizacion_id = p_org
     and id = any(coalesce(p_recetas, '{}'));
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke execute on function public.conceder_permisos_recetas(uuid, uuid[], uuid[], uuid[], text) from public, anon;
revoke execute on function public.revocar_permisos_recetas(uuid, uuid[])                      from public, anon;
revoke execute on function public.asignar_propietario_recetas(uuid, uuid[], uuid)              from public, anon;
grant  execute on function public.conceder_permisos_recetas(uuid, uuid[], uuid[], uuid[], text) to authenticated;
grant  execute on function public.revocar_permisos_recetas(uuid, uuid[])                      to authenticated;
grant  execute on function public.asignar_propietario_recetas(uuid, uuid[], uuid)              to authenticated;

comment on function public.conceder_permisos_recetas(uuid, uuid[], uuid[], uuid[], text)
  is 'Gerente: concede en bloque a varios chefs acceso (lectura/edicion) a todas '
     'las recetas de varios propietarios y/o a recetas concretas.';
comment on function public.revocar_permisos_recetas(uuid, uuid[])
  is 'Gerente: quita en bloque permisos de receta_permisos de su organización.';
comment on function public.asignar_propietario_recetas(uuid, uuid[], uuid)
  is 'Gerente: asigna en bloque un propietario (miembro activo) a recetas de su organización.';

commit;
