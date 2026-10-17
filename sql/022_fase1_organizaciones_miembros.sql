-- =============================================================================
-- 022_fase1_organizaciones_miembros.sql
-- Fase 1 — Infraestructura de organizaciones (sin cambios visibles en la app)
-- =============================================================================
-- Qué hace este script:
--   1. Crea las tablas `organizaciones` y `organizacion_miembros`.
--   2. Crea las funciones de rol es_miembro_org() y es_gerente_org().
--      Ambas leen auth.uid() internamente; no aceptan uid por parámetro para
--      que no puedan llamarse haciéndose pasar por otro usuario.
--   3. Revoca el permiso de ejecución a anon y public en todas las funciones
--      de rol (solo authenticated puede llamarlas).
--   4. Inserta la organización "Samirarte" y migra los usuarios actuales:
--      - Compara auth.users con usuarios_app e incluye a todos los usuarios
--        reales que existan en auth pero falten en usuarios_app.
--      - Los que tienen rol='admin' en usuarios_app → gerente en la org.
--      - El resto → chef.
--
-- Requisitos previos: migraciones 017 (usuarios_app, es_admin_app).
-- Impacto en la app actual: NINGUNO. La app sigue funcionando sin cambios.
-- Reversible: sí (ver sección ROLLBACK al final).
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. TABLA: organizaciones
-- ---------------------------------------------------------------------------

create table if not exists public.organizaciones (
  id          uuid        primary key default gen_random_uuid(),
  nombre      text        not null,
  slug        text        not null,
  descripcion text,
  activa      boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint organizaciones_slug_unique unique (slug),
  constraint organizaciones_nombre_not_empty check (trim(nombre) <> ''),
  constraint organizaciones_slug_formato check (slug ~ '^[a-z0-9\-]+$')
);

comment on table  public.organizaciones
  is 'Organizaciones (cocinas, obradores, empresas de catering) que usan la plataforma.';
comment on column public.organizaciones.slug
  is 'Identificador URL-friendly: solo minúsculas, números y guiones.';

create index if not exists idx_organizaciones_slug
  on public.organizaciones (slug);
create index if not exists idx_organizaciones_activa
  on public.organizaciones (activa);

drop trigger if exists trg_organizaciones_set_updated_at on public.organizaciones;
create trigger trg_organizaciones_set_updated_at
  before update on public.organizaciones
  for each row execute function public.set_updated_at();


-- ---------------------------------------------------------------------------
-- 2. TABLA: organizacion_miembros
-- ---------------------------------------------------------------------------

create table if not exists public.organizacion_miembros (
  id               uuid        primary key default gen_random_uuid(),
  organizacion_id  uuid        not null references public.organizaciones(id) on delete cascade,
  user_id          uuid        not null references auth.users(id) on delete cascade,
  rol              text        not null default 'chef',
  activo           boolean     not null default true,
  invited_at       timestamptz not null default now(),
  joined_at        timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  constraint organizacion_miembros_unique unique (organizacion_id, user_id),
  constraint organizacion_miembros_rol_check check (rol in ('gerente', 'chef'))
);

comment on table  public.organizacion_miembros
  is 'Pertenencia de un usuario a una organización con su rol.';
comment on column public.organizacion_miembros.rol
  is 'gerente: administra la organización. chef: accede a los datos.';
comment on column public.organizacion_miembros.joined_at
  is 'Fecha en que el usuario canjeó la invitación. NULL si fue dado de alta directamente por un gerente.';

-- Índice compuesto crítico: la función es_miembro_org lo usa en cada evaluación RLS.
create index if not exists idx_org_miembros_org_user_activo
  on public.organizacion_miembros (organizacion_id, user_id, activo);

create index if not exists idx_org_miembros_user_id
  on public.organizacion_miembros (user_id);

drop trigger if exists trg_org_miembros_set_updated_at on public.organizacion_miembros;
create trigger trg_org_miembros_set_updated_at
  before update on public.organizacion_miembros
  for each row execute function public.set_updated_at();


-- ---------------------------------------------------------------------------
-- 3. FUNCIONES DE ROL
-- ---------------------------------------------------------------------------
-- Normas de seguridad aplicadas a todas las funciones de rol:
--   a) Leen auth.uid() internamente. No aceptan uid como parámetro para
--      evitar que un usuario pueda suplantar a otro.
--   b) SECURITY DEFINER + search_path fijo: protege contra ataques de
--      search_path y permite que PostgreSQL las caché por transacción.
--   c) Después de crearlas se revoca EXECUTE a public y anon, y se concede
--      solo a authenticated.
-- ---------------------------------------------------------------------------

-- es_miembro_org: True si el usuario actual tiene membresía activa (cualquier rol).
create or replace function public.es_miembro_org(p_organizacion_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.organizacion_miembros
    where organizacion_id = p_organizacion_id
      and user_id          = auth.uid()
      and activo           = true
  );
$$;

-- es_gerente_org: True si el usuario actual es gerente activo de la organización.
create or replace function public.es_gerente_org(p_organizacion_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.organizacion_miembros
    where organizacion_id = p_organizacion_id
      and user_id          = auth.uid()
      and rol              = 'gerente'
      and activo           = true
  );
$$;

-- mis_organizaciones: devuelve los ids de las organizaciones activas del usuario actual.
create or replace function public.mis_organizaciones()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select om.organizacion_id
  from public.organizacion_miembros om
  join public.organizaciones o on o.id = om.organizacion_id
  where om.user_id = auth.uid()
    and om.activo  = true
    and o.activa   = true;
$$;

-- Permisos: revocar a public/anon, conceder solo a authenticated.
revoke execute on function public.es_miembro_org(uuid)   from public, anon;
revoke execute on function public.es_gerente_org(uuid)   from public, anon;
revoke execute on function public.mis_organizaciones()   from public, anon;

grant  execute on function public.es_miembro_org(uuid)   to authenticated;
grant  execute on function public.es_gerente_org(uuid)   to authenticated;
grant  execute on function public.mis_organizaciones()   to authenticated;

comment on function public.es_miembro_org(uuid)
  is 'True si el usuario actual (auth.uid()) tiene membresía activa en la organización.';
comment on function public.es_gerente_org(uuid)
  is 'True si el usuario actual (auth.uid()) es gerente activo de la organización.';
comment on function public.mis_organizaciones()
  is 'Devuelve los IDs de las organizaciones activas del usuario actual.';

-- También revocar es_admin_app a anon/public si no se hizo en 017:
revoke execute on function public.es_admin_app(uuid) from public, anon;
grant  execute on function public.es_admin_app(uuid) to authenticated;


-- ---------------------------------------------------------------------------
-- 4. RLS: organizaciones
-- ---------------------------------------------------------------------------

alter table public.organizaciones enable row level security;

drop policy if exists organizaciones_select_miembro on public.organizaciones;
create policy organizaciones_select_miembro
  on public.organizaciones
  for select to authenticated
  using (
    id in (select public.mis_organizaciones())
    or public.es_admin_app(auth.uid())
  );

drop policy if exists organizaciones_insert_admin on public.organizaciones;
create policy organizaciones_insert_admin
  on public.organizaciones
  for insert to authenticated
  with check (public.es_admin_app(auth.uid()));

drop policy if exists organizaciones_update_admin on public.organizaciones;
create policy organizaciones_update_admin
  on public.organizaciones
  for update to authenticated
  using    (public.es_admin_app(auth.uid()))
  with check (public.es_admin_app(auth.uid()));

-- No se elimina físicamente: se desactiva con activa=false.
drop policy if exists organizaciones_delete_admin on public.organizaciones;
create policy organizaciones_delete_admin
  on public.organizaciones
  for delete to authenticated
  using (public.es_admin_app(auth.uid()));


-- ---------------------------------------------------------------------------
-- 5. RLS: organizacion_miembros
-- ---------------------------------------------------------------------------

alter table public.organizacion_miembros enable row level security;

-- Cada usuario ve sus propias filas. Los gerentes ven a todos sus miembros.
drop policy if exists org_miembros_select on public.organizacion_miembros;
create policy org_miembros_select
  on public.organizacion_miembros
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.es_gerente_org(organizacion_id)
    or public.es_admin_app(auth.uid())
  );

-- Solo gerentes y admins pueden invitar (insertar) nuevos miembros.
drop policy if exists org_miembros_insert on public.organizacion_miembros;
create policy org_miembros_insert
  on public.organizacion_miembros
  for insert to authenticated
  with check (
    public.es_gerente_org(organizacion_id)
    or public.es_admin_app(auth.uid())
  );

-- Solo gerentes y admins pueden modificar miembros.
drop policy if exists org_miembros_update on public.organizacion_miembros;
create policy org_miembros_update
  on public.organizacion_miembros
  for update to authenticated
  using (
    public.es_gerente_org(organizacion_id)
    or public.es_admin_app(auth.uid())
  )
  with check (
    public.es_gerente_org(organizacion_id)
    or public.es_admin_app(auth.uid())
  );

-- Borrado físico solo para el admin de plataforma.
drop policy if exists org_miembros_delete on public.organizacion_miembros;
create policy org_miembros_delete
  on public.organizacion_miembros
  for delete to authenticated
  using (public.es_admin_app(auth.uid()));


-- ---------------------------------------------------------------------------
-- 6. DATOS: crear organización "Samirarte" y migrar usuarios
-- ---------------------------------------------------------------------------
-- Idempotente: puede ejecutarse varias veces sin duplicar datos.
--
-- Estrategia de migración completa:
--   a) Inserta en usuarios_app a cualquier usuario de auth.users que no esté
--      ya registrado (por si hay usuarios de Supabase Auth sin perfil interno).
--   b) Asigna todos los usuarios activos de usuarios_app a la org Samirarte.
-- ---------------------------------------------------------------------------

do $$
declare
  v_org_id    uuid;
  v_nuevos    integer := 0;
  v_migrados  integer := 0;
begin
  -- 6.a Crear la organización Samirarte si no existe
  insert into public.organizaciones (nombre, slug, descripcion, activa)
  values (
    'Samirarte',
    'samirarte',
    'Organización original migrada desde el sistema monousuario',
    true
  )
  on conflict (slug) do nothing;

  select id into v_org_id
  from public.organizaciones
  where slug = 'samirarte';

  -- 6.b Insertar en usuarios_app los usuarios de auth.users que falten.
  --     Rol por defecto: 'usuario'. Así aparecerán como 'chef' en la org.
  --     El administrador puede promocionarlos manualmente si procede.
  insert into public.usuarios_app (user_id, email, rol, activo)
  select
    au.id,
    au.email,
    'usuario',
    true
  from auth.users au
  where not exists (
    select 1 from public.usuarios_app ua where ua.user_id = au.id
  )
    and au.email is not null;

  get diagnostics v_nuevos = row_count;
  if v_nuevos > 0 then
    raise notice 'usuarios_app: % usuarios nuevos añadidos desde auth.users', v_nuevos;
  end if;

  -- 6.c Migrar todos los usuarios activos de usuarios_app a organizacion_miembros.
  --     - rol='admin' en usuarios_app → 'gerente' en la org
  --       (siguen siendo admin de plataforma a través de usuarios_app).
  --     - rol='usuario' → 'chef'.
  insert into public.organizacion_miembros
    (organizacion_id, user_id, rol, activo, joined_at)
  select
    v_org_id,
    ua.user_id,
    case when ua.rol = 'admin' then 'gerente' else 'chef' end,
    ua.activo,
    ua.created_at
  from public.usuarios_app ua
  where ua.activo = true
  on conflict (organizacion_id, user_id) do nothing;

  get diagnostics v_migrados = row_count;

  raise notice 'Organización Samirarte id = %', v_org_id;
  raise notice 'Miembros migrados (nuevos en esta ejecución): %', v_migrados;
  raise notice 'Total miembros en Samirarte: %',
    (select count(*) from public.organizacion_miembros where organizacion_id = v_org_id);
end;
$$;


-- ---------------------------------------------------------------------------
-- 7. AUDITORÍA POST-MIGRACIÓN
-- ---------------------------------------------------------------------------

-- Comparar auth.users vs usuarios_app: no debe quedar nadie fuera.
select
  au.email,
  ua.rol,
  ua.activo,
  (select count(*) from public.organizacion_miembros om
   where om.user_id = au.id) as orgs
from auth.users au
left join public.usuarios_app ua on ua.user_id = au.id
order by ua.rol desc, au.email;

-- Distribución por organización y rol:
select
  o.nombre,
  om.rol,
  count(*) as miembros
from public.organizacion_miembros om
join public.organizaciones o on o.id = om.organizacion_id
group by o.nombre, om.rol
order by o.nombre, om.rol;


-- ---------------------------------------------------------------------------
-- TESTS DE RLS
-- ---------------------------------------------------------------------------
/*
-- Como usuario chef de Samirarte — debe ver la org:
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"<uid_chef>","role":"authenticated"}';
select * from public.organizaciones;

-- Como usuario sin membresía — debe devolver 0 filas:
set local "request.jwt.claims" to '{"sub":"<uid_sin_org>","role":"authenticated"}';
select * from public.organizaciones;  -- 0 filas

-- Intento de insertar una organización → fallo de política:
insert into public.organizaciones(nombre, slug) values ('Hack', 'hack');

-- Como anon — las funciones de rol no deben ser ejecutables:
set local role anon;
select public.es_miembro_org('<uuid>');  -- permission denied
*/


-- ---------------------------------------------------------------------------
-- ROLLBACK
-- ---------------------------------------------------------------------------
/*
rollback;  -- si se ejecuta dentro de la misma transacción

-- O de forma destructiva:
drop table if exists public.organizacion_miembros;
drop table if exists public.organizaciones;
drop function if exists public.es_miembro_org(uuid);
drop function if exists public.es_gerente_org(uuid);
drop function if exists public.mis_organizaciones();
*/

commit;
