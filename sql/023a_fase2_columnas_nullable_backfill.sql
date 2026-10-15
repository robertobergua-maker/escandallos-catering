-- =============================================================================
-- 023a_fase2_columnas_nullable_backfill.sql
-- Fase 2 — PASO A: columnas organizacion_id (nullable) + backfill a Samirarte
--           + índices + tabla invitaciones + funciones crear/canjear_invitacion.
-- =============================================================================
-- Qué hace este script:
--   1. Añade organizacion_id NULLABLE a recetas, menus, clientes, facturas e
--      inventario. La columna es nullable para que la app actual siga funcionando
--      sin cambios mientras se despliega la nueva versión.
--   2. Rellena (backfill) todas las filas existentes de recetas, menus, clientes
--      y facturas con el id de Samirarte.
--      INVENTARIO: se queda con organizacion_id = NULL (catálogo global).
--      No se backfillea ninguna fila de inventario.
--   3. Crea índices por organizacion_id (necesarios para RLS eficiente).
--   4. Crea la tabla invitaciones con RLS hermético (solo gerentes/admins acceden).
--   5. Crea las funciones crear_invitacion() y canjear_invitacion().
--
-- Requisitos previos: 022 (organizaciones, organizacion_miembros, funciones de rol).
-- Impacto en la app actual: NINGUNO. Las columnas son nullable; la app existente
--   no envía organizacion_id y sigue funcionando exactamente igual.
-- Siguientes pasos:
--   → Desplegar la nueva versión de la app (PASO B, sin SQL).
--   → Ejecutar 023c para poner NOT NULL y cambiar las políticas RLS.
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

-- ===========================================================================
-- 1. COLUMNAS organizacion_id NULLABLE
-- ===========================================================================

alter table public.recetas
  add column if not exists organizacion_id uuid
    references public.organizaciones(id) on delete restrict;

alter table public.menus
  add column if not exists organizacion_id uuid
    references public.organizaciones(id) on delete restrict;

alter table public.clientes
  add column if not exists organizacion_id uuid
    references public.organizaciones(id) on delete restrict;

alter table public.facturas
  add column if not exists organizacion_id uuid
    references public.organizaciones(id) on delete restrict;

-- inventario: la columna se añade para completar el esquema, pero todas las filas
-- existentes son catálogo global y se DEJAN con organizacion_id = NULL.
-- No hay backfill de inventario. Los ingredientes privados por organización
-- son Fase 3 (024).
alter table public.inventario
  add column if not exists organizacion_id uuid
    references public.organizaciones(id) on delete restrict;

comment on column public.inventario.organizacion_id
  is 'NULL = catálogo global (lectura libre, escritura solo admin de plataforma). '
     'NOT NULL = ingrediente privado de esa organización (Fase 3).';


-- ===========================================================================
-- 2. BACKFILL: asignar datos existentes a Samirarte
--    Solo recetas, menus, clientes y facturas.
--    Inventario NO se toca (queda global, organizacion_id = NULL).
-- ===========================================================================

do $$
declare
  v_org_id uuid;
begin
  select id into v_org_id
  from public.organizaciones
  where slug = 'samirarte';

  if v_org_id is null then
    raise exception
      'Organización "samirarte" no encontrada. Ejecutar primero la migración 022.';
  end if;

  update public.recetas
    set organizacion_id = v_org_id
    where organizacion_id is null;

  update public.menus
    set organizacion_id = v_org_id
    where organizacion_id is null;

  update public.clientes
    set organizacion_id = v_org_id
    where organizacion_id is null;

  update public.facturas
    set organizacion_id = v_org_id
    where organizacion_id is null;

  -- inventario: NO se actualiza. Todas las filas siguen con organizacion_id = NULL.

  raise notice 'Backfill completado para org Samirarte (id = %)', v_org_id;
  raise notice '  recetas:   %',
    (select count(*) from public.recetas  where organizacion_id = v_org_id);
  raise notice '  menus:     %',
    (select count(*) from public.menus    where organizacion_id = v_org_id);
  raise notice '  clientes:  %',
    (select count(*) from public.clientes where organizacion_id = v_org_id);
  raise notice '  facturas:  %',
    (select count(*) from public.facturas where organizacion_id = v_org_id);
  raise notice '  inventario (global, sin backfill): %',
    (select count(*) from public.inventario where organizacion_id is null);
end;
$$;


-- ===========================================================================
-- 3. ÍNDICES por organizacion_id
--    Imprescindibles antes del paso C: las evaluaciones RLS con es_miembro_org
--    hacen seq scan sin ellos, lo que en plan gratuito de Supabase es crítico.
-- ===========================================================================

create index if not exists idx_recetas_organizacion_id
  on public.recetas (organizacion_id);

-- Compuesto: las consultas más frecuentes filtran org + activa
create index if not exists idx_recetas_org_activa
  on public.recetas (organizacion_id, activa);

create index if not exists idx_menus_organizacion_id
  on public.menus (organizacion_id);

create index if not exists idx_clientes_organizacion_id
  on public.clientes (organizacion_id);

create index if not exists idx_facturas_organizacion_id
  on public.facturas (organizacion_id);

create index if not exists idx_inventario_organizacion_id
  on public.inventario (organizacion_id);

-- Índice parcial para catálogo global: es la consulta más frecuente
create index if not exists idx_inventario_catalogo_global
  on public.inventario (codigo)
  where organizacion_id is null;


-- ===========================================================================
-- 4. TABLA: invitaciones
--    Diseño de seguridad:
--    • El código nunca se guarda en claro: solo el hash bcrypt (extensions.crypt).
--    • Sin política SELECT para anon ni authenticated genérico.
--    • El canje va exclusivamente por la función canjear_invitacion().
--    • Solo gerentes/admins pueden leer, crear y revocar invitaciones.
-- ===========================================================================

create table if not exists public.invitaciones (
  id               uuid        primary key default gen_random_uuid(),
  organizacion_id  uuid        not null
                     references public.organizaciones(id) on delete cascade,
  email            text        not null,
  rol              text        not null default 'chef',
  -- El código en texto plano NUNCA se guarda; solo el hash bcrypt.
  codigo_hash      text        not null,
  creado_por       uuid        references auth.users(id) on delete set null,
  canjeada         boolean     not null default false,
  expires_at       timestamptz not null default (now() + interval '7 days'),
  created_at       timestamptz not null default now(),

  constraint invitaciones_rol_check
    check (rol in ('gerente', 'chef')),
  constraint invitaciones_email_formato
    check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);

comment on table  public.invitaciones
  is 'Invitaciones para unirse a una organización. '
     'El código se almacena como hash bcrypt; nunca en texto plano.';
comment on column public.invitaciones.codigo_hash
  is 'Hash bcrypt del código. El texto plano se entrega al invitado y no se guarda.';

create index if not exists idx_invitaciones_organizacion_id
  on public.invitaciones (organizacion_id);

-- Búsqueda por email en canjear_invitacion() (lower para insensibilidad a mayúsculas)
create index if not exists idx_invitaciones_email_lower
  on public.invitaciones (lower(email));

-- No se indexa codigo_hash: bcrypt no es apto para B-tree.
-- La búsqueda filtra primero por email (índice), luego compara el hash en memoria.

alter table public.invitaciones enable row level security;

-- Solo gerentes de la organización y admins de plataforma pueden ver invitaciones.
drop policy if exists invitaciones_select on public.invitaciones;
create policy invitaciones_select
  on public.invitaciones for select to authenticated
  using (
    public.es_gerente_org(organizacion_id)
    or public.es_admin_app(auth.uid())
  );

-- Solo gerentes y admins pueden crear invitaciones.
drop policy if exists invitaciones_insert on public.invitaciones;
create policy invitaciones_insert
  on public.invitaciones for insert to authenticated
  with check (
    public.es_gerente_org(organizacion_id)
    or public.es_admin_app(auth.uid())
  );

-- Gerentes y admins pueden revocar (update canjeada=true, etc.).
-- Los usuarios normales NO tienen política de UPDATE: el canje va por función.
drop policy if exists invitaciones_update on public.invitaciones;
create policy invitaciones_update
  on public.invitaciones for update to authenticated
  using (
    public.es_gerente_org(organizacion_id)
    or public.es_admin_app(auth.uid())
  )
  with check (
    public.es_gerente_org(organizacion_id)
    or public.es_admin_app(auth.uid())
  );

drop policy if exists invitaciones_delete on public.invitaciones;
create policy invitaciones_delete
  on public.invitaciones for delete to authenticated
  using (
    public.es_gerente_org(organizacion_id)
    or public.es_admin_app(auth.uid())
  );

-- Sin política para anon: la tabla es inaccesible sin sesión autenticada.


-- ===========================================================================
-- 5. FUNCIÓN: crear_invitacion
--    Genera un código aleatorio de 32 bytes (hex), lo hashea con bcrypt y
--    guarda solo el hash. Devuelve el código en texto plano una sola vez
--    para que el gerente lo envíe al invitado.
--    pgcrypto está en el esquema extensions de Supabase (no se crea aquí).
-- ===========================================================================

create or replace function public.crear_invitacion(
  p_organizacion_id uuid,
  p_email           text,
  p_rol             text    default 'chef',
  p_dias_validez    integer default 7
)
returns text    -- código en texto plano: único momento en que está disponible
language plpgsql
security definer
set search_path = public
as $$
declare
  v_codigo      text;
  v_codigo_hash text;
begin
  if not (public.es_gerente_org(p_organizacion_id) or public.es_admin_app(auth.uid())) then
    raise exception 'Sin permiso para crear invitaciones en esta organización.';
  end if;

  if p_rol not in ('gerente', 'chef') then
    raise exception 'Rol inválido: %. Solo se permite gerente o chef.', p_rol;
  end if;

  if p_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Formato de email inválido.';
  end if;

  -- 32 bytes aleatorios → 64 hex chars. extensions.gen_random_bytes vive en Supabase.
  v_codigo      := encode(extensions.gen_random_bytes(32), 'hex');
  v_codigo_hash := extensions.crypt(v_codigo, extensions.gen_salt('bf', 10));

  insert into public.invitaciones
    (organizacion_id, email, rol, codigo_hash, creado_por, expires_at)
  values (
    p_organizacion_id,
    lower(trim(p_email)),
    p_rol,
    v_codigo_hash,
    auth.uid(),
    now() + (p_dias_validez || ' days')::interval
  );

  return v_codigo;  -- texto plano: entregar al invitado, no persistir
end;
$$;

revoke execute on function public.crear_invitacion(uuid, text, text, integer)
  from public, anon;
grant  execute on function public.crear_invitacion(uuid, text, text, integer)
  to authenticated;

comment on function public.crear_invitacion(uuid, text, text, integer)
  is 'Crea una invitación hasheando el código con bcrypt (extensions.crypt). '
     'Devuelve el código en texto plano solo en este momento. '
     'Solo gerentes y admins de plataforma.';


-- ===========================================================================
-- 6. FUNCIÓN: canjear_invitacion
--    Verifica: hash bcrypt, caducidad, canjeada=false y que el email de la
--    invitación coincida con auth.users.email del llamador.
--    Si todo es correcto: crea la membresía y marca la invitación como canjeada,
--    todo en una sola transacción atómica.
--    Anon no puede llamarla (REVOKE execute).
-- ===========================================================================

create or replace function public.canjear_invitacion(p_codigo text)
returns text    -- nombre de la organización a la que se unió el usuario
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv        record;
  v_user_email text;
  v_org_nombre text;
begin
  -- Email real del usuario autenticado (no el que envíe la app)
  select email into v_user_email
  from auth.users
  where id = auth.uid();

  if v_user_email is null then
    raise exception 'No se pudo verificar el email del usuario autenticado.';
  end if;

  -- Buscar candidatas por email + activas, luego comparar hash.
  -- bcrypt es lento a propósito; filtrar por email primero limita el trabajo.
  select inv.* into v_inv
  from public.invitaciones inv
  where lower(inv.email) = lower(v_user_email)
    and inv.canjeada      = false
    and inv.expires_at    > now()
    and extensions.crypt(p_codigo, inv.codigo_hash) = inv.codigo_hash
  limit 1;

  if v_inv is null then
    -- Mensaje genérico intencionalmente: no revela si el email existe
    raise exception 'Código de invitación inválido, caducado o ya canjeado.';
  end if;

  if public.es_miembro_org(v_inv.organizacion_id) then
    raise exception 'Ya eres miembro activo de esta organización.';
  end if;

  -- Crear membresía (o reactivar si existía inactiva)
  insert into public.organizacion_miembros
    (organizacion_id, user_id, rol, activo, invited_at, joined_at)
  values (
    v_inv.organizacion_id,
    auth.uid(),
    v_inv.rol,
    true,
    v_inv.created_at,
    now()
  )
  on conflict (organizacion_id, user_id) do update set
    rol       = excluded.rol,
    activo    = true,
    joined_at = now();

  -- Marcar invitación como canjeada (SECURITY DEFINER bypasea RLS)
  update public.invitaciones
    set canjeada = true
    where id = v_inv.id;

  select nombre into v_org_nombre
  from public.organizaciones
  where id = v_inv.organizacion_id;

  return v_org_nombre;
end;
$$;

revoke execute on function public.canjear_invitacion(text) from public, anon;
grant  execute on function public.canjear_invitacion(text) to authenticated;

comment on function public.canjear_invitacion(text)
  is 'Canjea una invitación: verifica hash bcrypt, caducidad, canjeada=false y '
     'que email de la invitación = email del llamador en auth.users. '
     'Crea la membresía y marca canjeada en una sola transacción.';


-- ===========================================================================
-- AUDITORÍA POST-PASO A
-- ===========================================================================

-- Verificar que el backfill cubrió todo (inventario DEBE quedar en 0 de Samirarte)
select
  'recetas'   as tabla,
  count(*) filter (where organizacion_id is null)                         as sin_org,
  count(*) filter (where organizacion_id =
    (select id from public.organizaciones where slug = 'samirarte'))      as samirarte
from public.recetas
union all
select 'menus',
  count(*) filter (where organizacion_id is null),
  count(*) filter (where organizacion_id =
    (select id from public.organizaciones where slug = 'samirarte'))
from public.menus
union all
select 'clientes',
  count(*) filter (where organizacion_id is null),
  count(*) filter (where organizacion_id =
    (select id from public.organizaciones where slug = 'samirarte'))
from public.clientes
union all
select 'facturas',
  count(*) filter (where organizacion_id is null),
  count(*) filter (where organizacion_id =
    (select id from public.organizaciones where slug = 'samirarte'))
from public.facturas
union all
select 'inventario (global=NULL esperado)',
  count(*) filter (where organizacion_id is null),
  count(*) filter (where organizacion_id =
    (select id from public.organizaciones where slug = 'samirarte'))
from public.inventario;

-- Resultado esperado:
--   recetas, menus, clientes, facturas → sin_org = 0, samirarte > 0
--   inventario → sin_org = total filas, samirarte = 0


-- ===========================================================================
-- ROLLBACK (si hay que deshacer solo este paso)
-- ===========================================================================
/*
rollback;  -- si se ejecuta dentro de la misma sesión antes de commit

-- O de forma destructiva:
drop function  if exists public.canjear_invitacion(text);
drop function  if exists public.crear_invitacion(uuid, text, text, integer);
drop table     if exists public.invitaciones;
drop index     if exists public.idx_inventario_catalogo_global;
drop index     if exists public.idx_inventario_organizacion_id;
drop index     if exists public.idx_facturas_organizacion_id;
drop index     if exists public.idx_clientes_organizacion_id;
drop index     if exists public.idx_menus_organizacion_id;
drop index     if exists public.idx_recetas_org_activa;
drop index     if exists public.idx_recetas_organizacion_id;
alter table public.facturas   drop column if exists organizacion_id;
alter table public.clientes   drop column if exists organizacion_id;
alter table public.menus      drop column if exists organizacion_id;
alter table public.recetas    drop column if exists organizacion_id;
alter table public.inventario drop column if exists organizacion_id;
*/

commit;
