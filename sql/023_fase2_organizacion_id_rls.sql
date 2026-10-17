-- =============================================================================
-- 023_fase2_organizacion_id_rls.sql
-- Fase 2 — organizacion_id en tablas operativas, RLS por organización,
--           tabla de invitaciones con canje seguro.
-- =============================================================================
-- Principio rector: ninguna seguridad depende de que la app filtre.
-- La base de datos bloquea en RLS todo lo que no debe verse o modificarse,
-- independientemente de qué envíe la app.
--
-- Estrategia de migración sin corte de servicio (ejecutar en orden):
--   PASO A — organizacion_id NULLABLE en tablas operativas.
--   PASO B — Backfill: asignar todos los datos actuales a Samirarte.
--   PASO C — NOT NULL (después de desplegar la nueva versión de la app).
--   PASO D — Tabla invitaciones + función canjear_invitacion.
--   PASO E — Reemplazar políticas RLS (user_id → es_miembro_org).
--   PASO F — Índices por organizacion_id.
--
-- Requisitos previos: migraciones 013-021 y 022 (Fase 1).
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

-- ===========================================================================
-- PASO A — organizacion_id NULLABLE
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

-- NOTA: public.presupuestos, public.presupuesto_menus y public.factura_menus
-- son creadas por la migración 019, que no está aplicada en producción.
-- Esas tablas y sus políticas RLS se añadirán en un script complementario
-- cuando la 019 se ejecute. No se tocan aquí.

-- inventario: NULL = catálogo global (solo admin escribe).
-- NOT NULL = ingrediente privado de esa organización.
alter table public.inventario
  add column if not exists organizacion_id uuid
    references public.organizaciones(id) on delete restrict;

comment on column public.inventario.organizacion_id
  is 'NULL = catálogo global (lectura libre, escritura solo admin). '
     'NOT NULL = ingrediente privado visible solo para esa organización.';


-- ===========================================================================
-- PASO B — Backfill: asignar los datos actuales a Samirarte
-- ===========================================================================

do $$
declare
  v_org_id uuid;
begin
  select id into v_org_id from public.organizaciones where slug = 'samirarte';
  if v_org_id is null then
    raise exception 'Organización "samirarte" no encontrada. Ejecutar primero 022.';
  end if;

  update public.recetas      set organizacion_id = v_org_id where organizacion_id is null;
  update public.menus        set organizacion_id = v_org_id where organizacion_id is null;
  update public.clientes     set organizacion_id = v_org_id where organizacion_id is null;
  update public.facturas     set organizacion_id = v_org_id where organizacion_id is null;
  -- presupuestos: tabla de la migración 019, no aplicada → no se toca aquí.
  -- inventario: catálogo global → se deja NULL intencionadamente.

  raise notice 'Backfill completado. Org Samirarte id = %', v_org_id;
  raise notice '  recetas:   %', (select count(*) from public.recetas  where organizacion_id = v_org_id);
  raise notice '  menus:     %', (select count(*) from public.menus    where organizacion_id = v_org_id);
  raise notice '  clientes:  %', (select count(*) from public.clientes where organizacion_id = v_org_id);
  raise notice '  facturas:  %', (select count(*) from public.facturas where organizacion_id = v_org_id);
end;
$$;


-- ===========================================================================
-- PASO C — NOT NULL (ejecutar DESPUÉS de desplegar la nueva versión de la app)
-- ===========================================================================
-- Verificar antes:
--   SELECT COUNT(*) FROM recetas     WHERE organizacion_id IS NULL;  -- 0
--   SELECT COUNT(*) FROM menus       WHERE organizacion_id IS NULL;
--   SELECT COUNT(*) FROM clientes    WHERE organizacion_id IS NULL;
--   SELECT COUNT(*) FROM facturas    WHERE organizacion_id IS NULL;
--   SELECT COUNT(*) FROM presupuestos WHERE organizacion_id IS NULL;
-- ===========================================================================

alter table public.recetas      alter column organizacion_id set not null;
alter table public.menus        alter column organizacion_id set not null;
alter table public.clientes     alter column organizacion_id set not null;
alter table public.facturas     alter column organizacion_id set not null;

-- receta_ingredientes, menu_recetas y factura_lineas NO necesitan organizacion_id
-- propio: heredan el de su tabla padre y sus políticas RLS lo comprueban vía EXISTS.
-- presupuesto_menus y factura_menus pertenecen a la migración 019 (no aplicada).


-- ===========================================================================
-- PASO D — Tabla invitaciones + función de canje
-- ===========================================================================
-- Diseño de seguridad:
--   • El código se guarda como hash bcrypt (pgcrypto crypt) → si la tabla
--     se filtra, los códigos en texto plano no se exponen.
--   • La tabla invitaciones NO tiene política de SELECT para anon ni
--     para authenticated genérico: solo gerentes/admins leen filas.
--   • El canje se realiza ÚNICAMENTE a través de la función
--     canjear_invitacion(p_codigo text), que es SECURITY DEFINER y verifica:
--       1. El código (comparando el hash).
--       2. Que no esté canjeada.
--       3. Que no haya caducado.
--       4. Que el email de la invitación coincida con el email del usuario
--          autenticado (auth.users.email).
--   • Anon no puede llamar a la función (REVOKE execute).
-- ===========================================================================

-- pgcrypto está en el esquema extensions de Supabase; no se crea aquí.
-- Las funciones se cualifican con extensions.crypt / extensions.gen_salt /
-- extensions.gen_random_bytes para que funcionen con search_path = public.

create table if not exists public.invitaciones (
  id               uuid        primary key default gen_random_uuid(),
  organizacion_id  uuid        not null references public.organizaciones(id) on delete cascade,
  email            text        not null,
  rol              text        not null default 'chef',
  -- El código en texto plano NUNCA se guarda; solo el hash bcrypt.
  codigo_hash      text        not null,
  creado_por       uuid        references auth.users(id) on delete set null,
  canjeada         boolean     not null default false,
  expires_at       timestamptz not null default (now() + interval '7 days'),
  created_at       timestamptz not null default now(),

  constraint invitaciones_rol_check check (rol in ('gerente', 'chef')),
  constraint invitaciones_email_formato
    check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
  -- No UNIQUE sobre codigo_hash: bcrypt genera distinto hash para el mismo
  -- texto; la unicidad se garantiza en la lógica de generación del código.
);

comment on table  public.invitaciones
  is 'Invitaciones para unirse a una organización. El código se almacena hasheado con bcrypt.';
comment on column public.invitaciones.codigo_hash
  is 'Hash bcrypt del código de invitación. El código en texto plano se envía al invitado y nunca se persiste.';

create index if not exists idx_invitaciones_organizacion_id
  on public.invitaciones (organizacion_id);
create index if not exists idx_invitaciones_email
  on public.invitaciones (lower(email));
-- No se indexa codigo_hash (bcrypt no es apto para búsqueda por índice B-tree);
-- la búsqueda usa email para limitar el conjunto antes de comparar el hash.


-- RLS: invitaciones
-- La tabla está completamente bloqueada para lectura directa salvo gerentes/admins.
-- El canje va por la función, no por SELECT + UPDATE.

alter table public.invitaciones enable row level security;

-- Gerentes ven las invitaciones de su organización; admins ven todo.
drop policy if exists invitaciones_select on public.invitaciones;
create policy invitaciones_select
  on public.invitaciones
  for select to authenticated
  using (
    public.es_gerente_org(organizacion_id)
    or public.es_admin_app(auth.uid())
  );

-- Solo gerentes y admins pueden crear invitaciones.
drop policy if exists invitaciones_insert on public.invitaciones;
create policy invitaciones_insert
  on public.invitaciones
  for insert to authenticated
  with check (
    public.es_gerente_org(organizacion_id)
    or public.es_admin_app(auth.uid())
  );

-- Solo gerentes y admins pueden modificar o revocar invitaciones.
-- El canje (canjeada=true) se hace SOLO a través de la función canjear_invitacion;
-- la tabla en sí no tiene política de UPDATE para usuarios normales.
drop policy if exists invitaciones_update on public.invitaciones;
create policy invitaciones_update
  on public.invitaciones
  for update to authenticated
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
  on public.invitaciones
  for delete to authenticated
  using (
    public.es_gerente_org(organizacion_id)
    or public.es_admin_app(auth.uid())
  );

-- No existe ninguna política para anon. La tabla no es accesible sin sesión.


-- ---------------------------------------------------------------------------
-- FUNCIÓN: crear_invitacion
-- Recibe el código en texto plano, lo hashea y guarda solo el hash.
-- Devuelve el código en texto plano (solo en este momento; no se vuelve a leer).
-- Solo gerentes y admins pueden crearla; la función comprueba el rol.
-- ---------------------------------------------------------------------------

create or replace function public.crear_invitacion(
  p_organizacion_id uuid,
  p_email           text,
  p_rol             text    default 'chef',
  p_dias_validez    integer default 7
)
returns text        -- devuelve el código en texto plano para enviar al invitado
language plpgsql
security definer
set search_path = public
as $$
declare
  v_codigo      text;
  v_codigo_hash text;
begin
  -- Solo gerentes y admins pueden invitar
  if not (public.es_gerente_org(p_organizacion_id) or public.es_admin_app(auth.uid())) then
    raise exception 'Sin permiso para crear invitaciones en esta organización.';
  end if;

  if p_rol not in ('gerente', 'chef') then
    raise exception 'Rol inválido: %. Solo se permite gerente o chef.', p_rol;
  end if;

  if p_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Formato de email inválido.';
  end if;

  -- Generar código aleatorio de 32 bytes → 64 hex chars
  -- gen_random_bytes está en el esquema extensions de Supabase
  v_codigo := encode(extensions.gen_random_bytes(32), 'hex');

  -- Hashear con bcrypt. crypt y gen_salt están en extensions.
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

  -- Devolver el código en texto plano para que el gerente lo envíe al invitado.
  -- Este es el ÚNICO momento en que el código está disponible en texto plano.
  return v_codigo;
end;
$$;

revoke execute on function public.crear_invitacion(uuid, text, text, integer) from public, anon;
grant  execute on function public.crear_invitacion(uuid, text, text, integer) to authenticated;

comment on function public.crear_invitacion(uuid, text, text, integer)
  is 'Crea una invitación hasheando el código con bcrypt. '
     'Devuelve el código en texto plano (solo en este momento) para enviarlo al invitado. '
     'Solo gerentes y admins.';


-- ---------------------------------------------------------------------------
-- FUNCIÓN: canjear_invitacion
-- El usuario autenticado presenta el código en texto plano.
-- La función verifica: hash, caducidad, no canjeada y que el email de la
-- invitación coincida con el email del usuario en auth.users.
-- Si todo es correcto: crea la membresía y marca la invitación como canjeada.
-- Todo ocurre en una sola transacción atómica.
-- ---------------------------------------------------------------------------

create or replace function public.canjear_invitacion(p_codigo text)
returns text        -- devuelve el nombre de la organización a la que se unió
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv         record;
  v_user_email  text;
  v_org_nombre  text;
begin
  -- Obtener el email del usuario autenticado desde auth.users
  select email into v_user_email
  from auth.users
  where id = auth.uid();

  if v_user_email is null then
    raise exception 'No se pudo verificar el email del usuario autenticado.';
  end if;

  -- Buscar invitaciones para ese email que no estén caducadas ni canjeadas.
  -- Se itera sobre las candidatas comparando el hash (bcrypt es lento a propósito;
  -- limitar a las del email reduce el coste a O(invitaciones_de_ese_email)).
  select inv.* into v_inv
  from public.invitaciones inv
  where lower(inv.email) = lower(v_user_email)
    and inv.canjeada = false
    and inv.expires_at > now()
    and extensions.crypt(p_codigo, inv.codigo_hash) = inv.codigo_hash
  limit 1;

  if v_inv is null then
    -- Mensaje intencionalmente genérico para no revelar si el email existe
    raise exception 'Código de invitación inválido, caducado o ya canjeado.';
  end if;

  -- Verificar que el usuario no es ya miembro activo de esa organización
  if public.es_miembro_org(v_inv.organizacion_id) then
    raise exception 'Ya eres miembro de esta organización.';
  end if;

  -- Crear la membresía con el rol de la invitación
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
  on conflict (organizacion_id, user_id)
  do update set
    rol      = excluded.rol,
    activo   = true,
    joined_at = now();

  -- Marcar la invitación como canjeada
  -- (UPDATE directo: la función es SECURITY DEFINER, bypasea RLS)
  update public.invitaciones
  set canjeada = true
  where id = v_inv.id;

  -- Devolver nombre de la organización para confirmación en la UI
  select nombre into v_org_nombre
  from public.organizaciones
  where id = v_inv.organizacion_id;

  return v_org_nombre;
end;
$$;

revoke execute on function public.canjear_invitacion(text) from public, anon;
grant  execute on function public.canjear_invitacion(text) to authenticated;

comment on function public.canjear_invitacion(text)
  is 'Canjea una invitación verificando hash bcrypt, caducidad, estado canjeada y '
     'que el email de la invitación coincida con auth.users.email del llamador. '
     'Crea la membresía y marca la invitación como canjeada en una sola transacción.';


-- ===========================================================================
-- PASO E — Reemplazar políticas RLS en tablas operativas
-- Principio: la base de datos filtra por organizacion_id; la app no puede
-- acceder a datos de otra organización aunque envíe el id incorrecto.
-- ===========================================================================

-- ---- recetas ---------------------------------------------------------------

drop policy if exists recetas_select_propias on public.recetas;
drop policy if exists recetas_insert_propias on public.recetas;
drop policy if exists recetas_update_propias on public.recetas;
drop policy if exists recetas_delete_propias on public.recetas;

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

-- ---- receta_ingredientes ---------------------------------------------------
-- La condición de acceso se evalúa sobre la receta padre; es imposible leer
-- ingredientes de una receta a la que no se tiene acceso.

drop policy if exists receta_ingredientes_select_por_receta_propia on public.receta_ingredientes;
drop policy if exists receta_ingredientes_insert_por_receta_propia on public.receta_ingredientes;
drop policy if exists receta_ingredientes_update_por_receta_propia on public.receta_ingredientes;
drop policy if exists receta_ingredientes_delete_por_receta_propia on public.receta_ingredientes;

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

-- ---- menus -----------------------------------------------------------------

drop policy if exists menus_select_propios on public.menus;
drop policy if exists menus_insert_propios on public.menus;
drop policy if exists menus_update_propios on public.menus;
drop policy if exists menus_delete_propios on public.menus;

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

-- ---- menu_recetas ----------------------------------------------------------

drop policy if exists menu_recetas_select_por_menu_propio on public.menu_recetas;
drop policy if exists menu_recetas_insert_por_menu_propio on public.menu_recetas;
drop policy if exists menu_recetas_update_por_menu_propio on public.menu_recetas;
drop policy if exists menu_recetas_delete_por_menu_propio on public.menu_recetas;

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

-- ---- clientes --------------------------------------------------------------

drop policy if exists clientes_select_own on public.clientes;
drop policy if exists clientes_insert_own on public.clientes;
drop policy if exists clientes_update_own on public.clientes;
drop policy if exists clientes_delete_own on public.clientes;

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

-- ---- facturas --------------------------------------------------------------

drop policy if exists facturas_select_own on public.facturas;
drop policy if exists facturas_insert_own on public.facturas;
drop policy if exists facturas_update_own on public.facturas;
drop policy if exists facturas_delete_own on public.facturas;

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

-- ---- factura_lineas --------------------------------------------------------

drop policy if exists factura_lineas_select_own on public.factura_lineas;
drop policy if exists factura_lineas_insert_own on public.factura_lineas;
drop policy if exists factura_lineas_update_own on public.factura_lineas;
drop policy if exists factura_lineas_delete_own on public.factura_lineas;

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

-- ---- presupuestos, presupuesto_menus, factura_menus -----------------------
-- Estas tablas pertenecen a la migración 019, que no está aplicada en
-- producción. Sus políticas RLS se añadirán en un script complementario
-- que se ejecutará cuando la 019 se aplique. No se tocan aquí.

-- ---- inventario: catálogo global + ingredientes privados -------------------
-- Catálogo global (organizacion_id IS NULL): lectura para cualquier autenticado.
-- Ingredientes privados (NOT NULL): solo la organización propietaria.
-- Escritura en catálogo global: solo admin de plataforma.
-- La app no puede "ver" ingredientes privados de otra organización.

drop policy if exists inventario_select_authenticated on public.inventario;
drop policy if exists inventario_select_invitado      on public.inventario;
drop policy if exists inventario_insert_authenticated on public.inventario;
drop policy if exists inventario_update_org           on public.inventario;
drop policy if exists inventario_delete_org           on public.inventario;

create policy inventario_select_authenticated
  on public.inventario for select to authenticated
  using (
    organizacion_id is null                           -- catálogo global
    or public.es_miembro_org(organizacion_id)         -- ingrediente privado propio
  );

-- anon: solo catálogo global (modo invitado)
create policy inventario_select_invitado
  on public.inventario for select to anon
  using (organizacion_id is null);

create policy inventario_insert_authenticated
  on public.inventario for insert to authenticated
  with check (
    (organizacion_id is null     and public.es_admin_app(auth.uid()))
    or
    (organizacion_id is not null and public.es_miembro_org(organizacion_id))
  );

create policy inventario_update_org
  on public.inventario for update to authenticated
  using (
    (organizacion_id is null     and public.es_admin_app(auth.uid()))
    or
    (organizacion_id is not null and public.es_miembro_org(organizacion_id))
  )
  with check (
    (organizacion_id is null     and public.es_admin_app(auth.uid()))
    or
    (organizacion_id is not null and public.es_miembro_org(organizacion_id))
  );

create policy inventario_delete_org
  on public.inventario for delete to authenticated
  using (
    (organizacion_id is null     and public.es_admin_app(auth.uid()))
    or
    (organizacion_id is not null and public.es_miembro_org(organizacion_id))
  );


-- ===========================================================================
-- PASO F — Índices por organizacion_id
-- ===========================================================================

create index if not exists idx_recetas_organizacion_id
  on public.recetas (organizacion_id);
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

-- Índice parcial para el catálogo global (organizacion_id IS NULL es lo más consultado)
create index if not exists idx_inventario_catalogo_global
  on public.inventario (codigo)
  where organizacion_id is null;


-- ===========================================================================
-- AUDITORÍA POST-MIGRACIÓN
-- ===========================================================================

select 'recetas'   as tabla, count(*) as sin_org from public.recetas  where organizacion_id is null
union all
select 'menus',              count(*) from public.menus    where organizacion_id is null
union all
select 'clientes',           count(*) from public.clientes where organizacion_id is null
union all
select 'facturas',           count(*) from public.facturas where organizacion_id is null;
-- Todas deben devolver 0.
-- NOTA: presupuestos/presupuesto_menus/factura_menus (migración 019) no aparecen aquí.


-- ===========================================================================
-- TEST DE AISLAMIENTO RLS
-- ===========================================================================
/*
-- Org B: usuario que no pertenece a Samirarte no debe ver sus datos.
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"<uid_org_b>","role":"authenticated"}';
select count(*) from public.recetas;      -- 0
select count(*) from public.menus;        -- 0
select count(*) from public.clientes;     -- 0
select count(*) from public.facturas;     -- 0

-- Intento de insertar con organizacion_id de Samirarte → fallo de política:
insert into public.recetas(organizacion_id, nombre, raciones_base)
values ((select id from public.organizaciones where slug='samirarte'), 'X', 1);

-- Función canjear_invitacion: email no coincidente → excepción genérica.
-- Código inexistente → excepción genérica.
*/


-- ===========================================================================
-- ROLLBACK
-- ===========================================================================
/*
rollback;

-- O de forma destructiva:
drop function if exists public.canjear_invitacion(text);
drop function if exists public.crear_invitacion(uuid, text, text, integer);
drop table  if exists public.invitaciones;
-- Restaurar políticas antiguas copiando bloques de 014, 016, 018, 019.
-- ALTER TABLE ... ALTER COLUMN organizacion_id DROP NOT NULL; (si llegó al paso C)
*/

commit;
