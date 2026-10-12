-- =============================================================================
-- 025_fase4_comparticiones_copia.sql
-- Fase 4 — Compartir recetas y menús entre organizaciones, y copiarlos.
-- =============================================================================
-- Principio rector: los precios de origen NUNCA son legibles por la
-- organización destino, ni a través de RLS directa ni de ninguna función.
--
--   • No existe ninguna política SELECT que dé acceso directo a recetas,
--     receta_ingredientes, menus o menu_recetas de otra organización.
--   • La vista previa de un objeto compartido se obtiene ÚNICAMENTE a través
--     de las funciones ver_receta_compartida / ver_menu_compartido, que son
--     SECURITY DEFINER y proyectan EXCLUSIVAMENTE las columnas permitidas
--     (sin precio_unidad, coste_total, precio_venta_*, costes_indirectos_pct,
--     margen_beneficio_pct ni iva_pct).
--   • La copia se realiza a través de copiar_receta_a_org / copiar_menu_a_org,
--     que recalculan los precios con los datos de la organización destino.
--   • REVOKE execute a anon/public en todas las funciones.
--
-- ⚠️  ALÉRGENOS: los alérgenos NO se copian como filas.
--    La copia usa los ingredientes del catálogo global; sus alérgenos se
--    leen dinámicamente desde ingrediente_alergenos (catálogo global).
--    Si un ingrediente privado de la org origen no existe en la org destino,
--    se inserta en receta_ingredientes como es_temporal=true sin alérgenos
--    hasta que la org destino lo complete en su catálogo privado.
--
-- Requisitos previos: 022, 023, 024 (Fases 1-3).
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Columnas de trazabilidad en recetas y menus
-- ---------------------------------------------------------------------------

alter table public.recetas
  add column if not exists copiada_de uuid
    references public.recetas(id) on delete set null;

comment on column public.recetas.copiada_de
  is 'ID de la receta original de la que se hizo esta copia. NULL si es original.';

alter table public.menus
  add column if not exists copiado_de uuid
    references public.menus(id) on delete set null;

comment on column public.menus.copiado_de
  is 'ID del menú original del que se hizo esta copia. NULL si es original.';

create index if not exists idx_recetas_copiada_de
  on public.recetas (copiada_de) where copiada_de is not null;

create index if not exists idx_menus_copiado_de
  on public.menus (copiado_de) where copiado_de is not null;


-- ---------------------------------------------------------------------------
-- 2. TABLA: comparticiones
-- ---------------------------------------------------------------------------

create table if not exists public.comparticiones (
  id                       uuid        primary key default gen_random_uuid(),
  -- NULL = compartida por el admin de plataforma (sin org de origen)
  origen_organizacion_id   uuid        references public.organizaciones(id) on delete cascade,
  tipo                     text        not null,
  objeto_id                uuid        not null,
  destino                  text        not null default 'todas',
  destino_organizacion_id  uuid        references public.organizaciones(id) on delete cascade,
  activa                   boolean     not null default true,
  created_by               uuid        references auth.users(id) on delete set null,
  created_at               timestamptz not null default now(),

  constraint comparticiones_tipo_check
    check (tipo in ('receta', 'menu')),
  constraint comparticiones_destino_check
    check (destino in ('todas', 'especifica')),
  constraint comparticiones_destino_org_check
    check (
      (destino = 'todas'     and destino_organizacion_id is null)
      or (destino = 'especifica' and destino_organizacion_id is not null)
    ),
  constraint comparticiones_no_autocomparticion
    check (
      origen_organizacion_id is null
      or origen_organizacion_id <> destino_organizacion_id
    ),
  constraint comparticiones_unique
    unique (tipo, objeto_id, destino, destino_organizacion_id)
);

comment on table  public.comparticiones
  is 'Registro de recetas y menús compartidos entre organizaciones.';
comment on column public.comparticiones.origen_organizacion_id
  is 'Organización que comparte. NULL = compartida por el admin de plataforma.';

create index if not exists idx_comparticiones_objeto
  on public.comparticiones (tipo, objeto_id);
create index if not exists idx_comparticiones_destino_org
  on public.comparticiones (destino_organizacion_id)
  where destino_organizacion_id is not null;
create index if not exists idx_comparticiones_origen
  on public.comparticiones (origen_organizacion_id)
  where origen_organizacion_id is not null;


-- ---------------------------------------------------------------------------
-- 3. RLS: comparticiones
--    Solo gerentes/admins gestionan comparticiones.
--    Los miembros pueden ver los metadatos de lo compartido con su org
--    (necesitan saber qué tienen disponible), pero NUNCA acceden a los
--    datos de precio vía esta tabla.
-- ---------------------------------------------------------------------------

alter table public.comparticiones enable row level security;

-- Lectura de metadatos: gerentes de la org origen, miembros de la org destino
-- (para saber qué les han compartido) y admins.
drop policy if exists comparticiones_select on public.comparticiones;
create policy comparticiones_select
  on public.comparticiones for select to authenticated
  using (
    -- Gerente o miembro de la org origen
    (origen_organizacion_id is not null
     and public.es_miembro_org(origen_organizacion_id))
    -- Miembro de la org destino en compartición específica
    or (destino = 'especifica'
        and public.es_miembro_org(destino_organizacion_id))
    -- Compartición "para todas": cualquier miembro activo de cualquier org
    or (destino = 'todas'
        and exists (
          select 1 from public.organizacion_miembros
          where user_id = auth.uid() and activo = true
        ))
    or public.es_admin_app(auth.uid())
  );

-- Solo gerentes y admins crean comparticiones.
drop policy if exists comparticiones_insert on public.comparticiones;
create policy comparticiones_insert
  on public.comparticiones for insert to authenticated
  with check (
    (origen_organizacion_id is not null
     and public.es_gerente_org(origen_organizacion_id))
    or public.es_admin_app(auth.uid())
  );

-- Solo el gerente de la org origen (o admin) modifica/retira.
drop policy if exists comparticiones_update on public.comparticiones;
create policy comparticiones_update
  on public.comparticiones for update to authenticated
  using (
    (origen_organizacion_id is not null
     and public.es_gerente_org(origen_organizacion_id))
    or public.es_admin_app(auth.uid())
  )
  with check (
    (origen_organizacion_id is not null
     and public.es_gerente_org(origen_organizacion_id))
    or public.es_admin_app(auth.uid())
  );

drop policy if exists comparticiones_delete on public.comparticiones;
create policy comparticiones_delete
  on public.comparticiones for delete to authenticated
  using (
    (origen_organizacion_id is not null
     and public.es_gerente_org(origen_organizacion_id))
    or public.es_admin_app(auth.uid())
  );


-- ---------------------------------------------------------------------------
-- 4. FUNCIÓN AUXILIAR: org_puede_ver_objeto_compartido  (interna)
--    True si la organización tiene acceso a un objeto compartido.
--    Solo para uso interno (SECURITY DEFINER); REVOKE a todos los roles.
-- ---------------------------------------------------------------------------

create or replace function public.org_puede_ver_objeto_compartido(
  p_tipo      text,
  p_objeto_id uuid,
  p_org_id    uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.comparticiones c
    where c.tipo      = p_tipo
      and c.objeto_id = p_objeto_id
      and c.activa    = true
      and (
        c.destino = 'todas'
        or (c.destino = 'especifica' and c.destino_organizacion_id = p_org_id)
      )
      and (c.origen_organizacion_id is null or c.origen_organizacion_id <> p_org_id)
  );
$$;

-- Esta función es auxiliar interna; ningún rol externo la llama directamente.
revoke execute on function public.org_puede_ver_objeto_compartido(text, uuid, uuid)
  from public, anon, authenticated;

comment on function public.org_puede_ver_objeto_compartido(text, uuid, uuid)
  is 'Función auxiliar interna. Verifica si existe compartición activa. '
     'No callable desde fuera (REVOKE a todos los roles externos).';


-- ---------------------------------------------------------------------------
-- 5. FUNCIÓN: ver_receta_compartida
--    Vista previa de una receta compartida SIN columnas de precio ni coste.
--    La función verifica que la receta esté compartida con alguna organización
--    del usuario llamador antes de devolver nada.
--    Las columnas omitidas son: precio_unidad, coste_total, precio_venta_sin_iva,
--    precio_venta_con_iva, costes_indirectos_pct, margen_beneficio_pct, iva_pct.
-- ---------------------------------------------------------------------------

create or replace function public.ver_receta_compartida(p_receta_id uuid)
returns table (
  id               uuid,
  nombre           text,
  categoria        text,
  tipo_plato       text,
  raciones_base    numeric,
  unidad_servicio  text,
  descripcion      text,
  elaboracion      text,
  observaciones    text,
  activa           boolean,
  -- Ingredientes: sin precio_unidad ni coste_total
  ingredientes     jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  -- Verificar que el llamador pertenece a alguna organización que tenga
  -- acceso a esta receta por compartición. Se itera sobre las orgs del usuario.
  select mo into v_org_id
  from public.mis_organizaciones() mo
  where public.org_puede_ver_objeto_compartido('receta', p_receta_id, mo)
  limit 1;

  -- También puede ser miembro de la org propietaria (lectura normal)
  if v_org_id is null then
    select organizacion_id into v_org_id
    from public.recetas
    where id = p_receta_id
      and public.es_miembro_org(organizacion_id);
  end if;

  if v_org_id is null then
    raise exception 'La receta no existe o no está compartida con tu organización.';
  end if;

  return query
  select
    r.id,
    r.nombre,
    r.categoria,
    r.tipo_plato,
    r.raciones_base,
    r.unidad_servicio,
    r.descripcion,
    r.elaboracion,
    r.observaciones,
    r.activa,
    -- Ingredientes sin precio ni coste
    (
      select jsonb_agg(
        jsonb_build_object(
          'id',                    ri.id,
          'codigo_ingrediente',    ri.codigo_ingrediente,
          'descripcion_ingrediente', ri.descripcion_ingrediente,
          'cantidad_bruta',        ri.cantidad_bruta,
          'unidad_medida',         ri.unidad_medida,
          'merma',                 ri.merma,
          'cantidad_neta',         ri.cantidad_neta,
          'orden',                 ri.orden
          -- precio_unidad y coste_total deliberadamente EXCLUIDOS
        )
        order by ri.orden
      )
      from public.receta_ingredientes ri
      where ri.receta_id = r.id
    ) as ingredientes
  from public.recetas r
  where r.id = p_receta_id;
end;
$$;

revoke execute on function public.ver_receta_compartida(uuid) from public, anon;
grant  execute on function public.ver_receta_compartida(uuid) to authenticated;

comment on function public.ver_receta_compartida(uuid)
  is 'Vista previa de una receta compartida. '
     'Excluye precio_unidad, coste_total, precio_venta_*, costes_indirectos_pct, '
     'margen_beneficio_pct e iva_pct. Verifica acceso por compartición internamente.';


-- ---------------------------------------------------------------------------
-- 6. FUNCIÓN: ver_menu_compartido
--    Vista previa de un menú compartido SIN columnas de precio ni coste.
-- ---------------------------------------------------------------------------

create or replace function public.ver_menu_compartido(p_menu_id uuid)
returns table (
  id                  uuid,
  nombre              text,
  tipo_menu           text,
  descripcion         text,
  numero_comensales   integer,
  pax_referencia_menu integer,
  -- Recetas del menú: sin precios
  recetas             jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  -- Verificar acceso por compartición o membresía en la org propietaria
  select mo into v_org_id
  from public.mis_organizaciones() mo
  where public.org_puede_ver_objeto_compartido('menu', p_menu_id, mo)
  limit 1;

  if v_org_id is null then
    select organizacion_id into v_org_id
    from public.menus
    where id = p_menu_id
      and public.es_miembro_org(organizacion_id);
  end if;

  if v_org_id is null then
    raise exception 'El menú no existe o no está compartido con tu organización.';
  end if;

  return query
  select
    m.id,
    m.nombre,
    m.tipo_menu,
    m.descripcion,
    m.numero_comensales,
    m.pax_referencia_menu,
    -- Recetas del menú sin precios ni costes
    (
      select jsonb_agg(
        jsonb_build_object(
          'receta_id',     mr.receta_id,
          'nombre',        r.nombre,
          'categoria',     r.categoria,
          'tipo_plato',    r.tipo_plato,
          'raciones',      mr.raciones_receta_en_menu,
          'seccion',       mr.seccion,
          'orden',         mr.orden
          -- coste_total, precio_venta_* deliberadamente EXCLUIDOS
        )
        order by mr.orden
      )
      from public.menu_recetas mr
      join public.recetas r on r.id = mr.receta_id
      where mr.menu_id = m.id
    ) as recetas
  from public.menus m
  where m.id = p_menu_id;
end;
$$;

revoke execute on function public.ver_menu_compartido(uuid) from public, anon;
grant  execute on function public.ver_menu_compartido(uuid) to authenticated;

comment on function public.ver_menu_compartido(uuid)
  is 'Vista previa de un menú compartido. '
     'Excluye coste_total, precio_total y todos los campos de precio de recetas. '
     'Verifica acceso por compartición internamente.';


-- ---------------------------------------------------------------------------
-- 7. FUNCIÓN: listar_compartidos_para_org
--    Devuelve los metadatos de recetas y menús compartidos con la organización
--    del usuario. Solo metadatos (nombre, tipo, org origen): sin precios.
--    La app usa estos datos para mostrar el catálogo compartido y ofrecer "Copiar".
-- ---------------------------------------------------------------------------

create or replace function public.listar_compartidos_para_org(
  p_organizacion_id uuid
)
returns table (
  tipo              text,
  objeto_id         uuid,
  nombre            text,
  categoria         text,     -- solo para recetas
  tipo_especifico   text,     -- tipo_plato o tipo_menu
  org_origen_nombre text,
  comparticion_id   uuid
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not (public.es_miembro_org(p_organizacion_id) or public.es_admin_app(auth.uid())) then
    raise exception 'Sin acceso a la organización indicada.';
  end if;

  return query
  -- Recetas compartidas
  select
    'receta'::text                          as tipo,
    c.objeto_id,
    r.nombre,
    r.categoria,
    r.tipo_plato                            as tipo_especifico,
    coalesce(o.nombre, 'Admin plataforma')  as org_origen_nombre,
    c.id                                    as comparticion_id
  from public.comparticiones c
  join public.recetas r on r.id = c.objeto_id
  left join public.organizaciones o on o.id = c.origen_organizacion_id
  where c.tipo   = 'receta'
    and c.activa = true
    and (
      c.destino = 'todas'
      or (c.destino = 'especifica' and c.destino_organizacion_id = p_organizacion_id)
    )
    and (c.origen_organizacion_id is null or c.origen_organizacion_id <> p_organizacion_id)
    -- Excluir lo que ya hemos copiado
    and not exists (
      select 1 from public.recetas rc
      where rc.copiada_de = c.objeto_id
        and rc.organizacion_id = p_organizacion_id
    )

  union all

  -- Menús compartidos
  select
    'menu'::text,
    c.objeto_id,
    m.nombre,
    null::text,
    m.tipo_menu,
    coalesce(o.nombre, 'Admin plataforma'),
    c.id
  from public.comparticiones c
  join public.menus m on m.id = c.objeto_id
  left join public.organizaciones o on o.id = c.origen_organizacion_id
  where c.tipo   = 'menu'
    and c.activa = true
    and (
      c.destino = 'todas'
      or (c.destino = 'especifica' and c.destino_organizacion_id = p_organizacion_id)
    )
    and (c.origen_organizacion_id is null or c.origen_organizacion_id <> p_organizacion_id)
    and not exists (
      select 1 from public.menus mc
      where mc.copiado_de = c.objeto_id
        and mc.organizacion_id = p_organizacion_id
    )

  order by tipo, nombre;
end;
$$;

revoke execute on function public.listar_compartidos_para_org(uuid) from public, anon;
grant  execute on function public.listar_compartidos_para_org(uuid) to authenticated;

comment on function public.listar_compartidos_para_org(uuid)
  is 'Metadatos de recetas y menús compartidos con la organización. '
     'Sin precios. Excluye objetos ya copiados.';


-- ---------------------------------------------------------------------------
-- 8. FUNCIÓN: copiar_receta_a_org
--    Duplica una receta compartida en la organización destino.
--    Los precios se resuelven con inventario_org de la org destino.
--    Nunca expone ni usa precios de la organización origen.
--    ⚠️  Alérgenos: se leen dinámicamente del catálogo global; no se copian filas.
-- ---------------------------------------------------------------------------

create or replace function public.copiar_receta_a_org(
  p_receta_id       uuid,
  p_org_destino     uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nueva_id uuid;
begin
  -- Verificar membresía en la org destino
  if not (public.es_miembro_org(p_org_destino) or public.es_admin_app(auth.uid())) then
    raise exception 'No eres miembro de la organización destino.';
  end if;

  -- Verificar que la receta está compartida con la org destino O es de la propia org
  if not (
    public.org_puede_ver_objeto_compartido('receta', p_receta_id, p_org_destino)
    or exists (
      select 1 from public.recetas
      where id = p_receta_id and public.es_miembro_org(organizacion_id)
    )
  ) then
    raise exception 'La receta no está compartida con tu organización.';
  end if;

  -- Crear copia de la receta.
  -- Los campos de precio y coste se inicializan a 0; la app los recalcula.
  insert into public.recetas (
    organizacion_id, user_id,
    codigo_receta, nombre, categoria, tipo_plato,
    raciones_base, unidad_servicio, descripcion, elaboracion, observaciones,
    costes_indirectos_pct, margen_beneficio_pct, iva_pct,
    coste_total, precio_venta_sin_iva, precio_venta_con_iva,
    activa, copiada_de
  )
  select
    p_org_destino,
    auth.uid(),
    r.codigo_receta,
    r.nombre,
    r.categoria,
    r.tipo_plato,
    r.raciones_base,
    r.unidad_servicio,
    r.descripcion,
    r.elaboracion,
    r.observaciones,
    r.costes_indirectos_pct,
    r.margen_beneficio_pct,
    r.iva_pct,
    0, 0, 0,    -- precios a cero: se recalculan en la app con los datos propios
    true,
    r.id
  from public.recetas r
  where r.id = p_receta_id
  returning id into v_nueva_id;

  -- Copiar ingredientes resolviendo precios con inventario_org de la org destino.
  -- Los precios de ORIGEN no se usan en ningún momento.
  insert into public.receta_ingredientes (
    receta_id, codigo_ingrediente, descripcion_ingrediente,
    cantidad_bruta, unidad_medida, merma, cantidad_neta,
    precio_unidad, coste_total, orden, es_temporal
  )
  select
    v_nueva_id,
    ri.codigo_ingrediente,
    ri.descripcion_ingrediente,
    ri.cantidad_bruta,
    ri.unidad_medida,
    -- Merma: de la org destino o del catálogo global; nunca de la org origen
    coalesce(
      public.resolver_merma_ingrediente(ri.codigo_ingrediente, p_org_destino),
      ri.merma    -- fallback: merma del catálogo global (no de la org origen)
    ),
    ri.cantidad_neta,
    -- Precio: de la org destino o del catálogo global; NUNCA de la org origen
    coalesce(
      public.resolver_precio_ingrediente(ri.codigo_ingrediente, p_org_destino),
      0
    ),
    0,      -- coste_total: la app recalcula
    ri.orden,
    -- Marcar temporal si el ingrediente no existe ni en catálogo global
    -- ni en inventario_org de la org destino
    not exists (
      select 1 from public.inventario i
      where i.codigo = ri.codigo_ingrediente
        and (i.organizacion_id is null or i.organizacion_id = p_org_destino)
    )
  from public.receta_ingredientes ri
  where ri.receta_id = p_receta_id;

  return v_nueva_id;
end;
$$;

revoke execute on function public.copiar_receta_a_org(uuid, uuid) from public, anon;
grant  execute on function public.copiar_receta_a_org(uuid, uuid) to authenticated;

comment on function public.copiar_receta_a_org(uuid, uuid)
  is 'Copia una receta compartida a la org destino. '
     'Precios resueltos con inventario_org de la org destino: los de origen nunca se usan. '
     'Alérgenos no se copian; se leen dinámicamente del catálogo global.';


-- ---------------------------------------------------------------------------
-- 9. FUNCIÓN: copiar_menu_a_org
--    Copia un menú compartido copiando también sus recetas si no existen ya.
-- ---------------------------------------------------------------------------

create or replace function public.copiar_menu_a_org(
  p_menu_id     uuid,
  p_org_destino uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nuevo_id        uuid;
  v_mr              record;
  v_receta_copia_id uuid;
begin
  if not (public.es_miembro_org(p_org_destino) or public.es_admin_app(auth.uid())) then
    raise exception 'No eres miembro de la organización destino.';
  end if;

  if not (
    public.org_puede_ver_objeto_compartido('menu', p_menu_id, p_org_destino)
    or exists (
      select 1 from public.menus
      where id = p_menu_id and public.es_miembro_org(organizacion_id)
    )
  ) then
    raise exception 'El menú no está compartido con tu organización.';
  end if;

  -- Crear copia del menú (costes a cero; la app recalcula)
  insert into public.menus (
    organizacion_id, user_id,
    nombre, tipo_menu, descripcion,
    numero_comensales, pax_referencia_menu,
    coste_total, precio_total, copiado_de
  )
  select
    p_org_destino, auth.uid(),
    m.nombre, m.tipo_menu, m.descripcion,
    m.numero_comensales, m.pax_referencia_menu,
    0, 0,
    m.id
  from public.menus m
  where m.id = p_menu_id
  returning id into v_nuevo_id;

  -- Copiar recetas del menú
  for v_mr in
    select mr.*
    from public.menu_recetas mr
    where mr.menu_id = p_menu_id
    order by mr.orden
  loop
    -- Reusar copia previa si ya existe en la org destino
    select id into v_receta_copia_id
    from public.recetas
    where copiada_de = v_mr.receta_id
      and organizacion_id = p_org_destino
    limit 1;

    if v_receta_copia_id is null then
      v_receta_copia_id := public.copiar_receta_a_org(v_mr.receta_id, p_org_destino);
    end if;

    insert into public.menu_recetas (
      menu_id, receta_id,
      raciones, raciones_receta_en_menu,
      orden, seccion, observaciones
    ) values (
      v_nuevo_id, v_receta_copia_id,
      v_mr.raciones, v_mr.raciones_receta_en_menu,
      v_mr.orden, v_mr.seccion, v_mr.observaciones
    );
  end loop;

  return v_nuevo_id;
end;
$$;

revoke execute on function public.copiar_menu_a_org(uuid, uuid) from public, anon;
grant  execute on function public.copiar_menu_a_org(uuid, uuid) to authenticated;

comment on function public.copiar_menu_a_org(uuid, uuid)
  is 'Copia un menú compartido y sus recetas a la org destino. '
     'Reutiliza copias de recetas ya existentes en la org destino.';


-- ---------------------------------------------------------------------------
-- AUDITORÍA
-- ---------------------------------------------------------------------------

select
  (select count(*) from public.comparticiones)                           as comparticiones,
  (select count(*) from public.recetas where copiada_de is not null)     as recetas_copiadas,
  (select count(*) from public.menus   where copiado_de  is not null)    as menus_copiados;


-- ---------------------------------------------------------------------------
-- ROLLBACK
-- ---------------------------------------------------------------------------
/*
rollback;

drop function if exists public.copiar_menu_a_org(uuid, uuid);
drop function if exists public.copiar_receta_a_org(uuid, uuid);
drop function if exists public.listar_compartidos_para_org(uuid);
drop function if exists public.ver_menu_compartido(uuid);
drop function if exists public.ver_receta_compartida(uuid);
drop function if exists public.org_puede_ver_objeto_compartido(text, uuid, uuid);
drop table  if exists public.comparticiones;
-- ALTER TABLE public.recetas DROP COLUMN IF EXISTS copiada_de;
-- ALTER TABLE public.menus   DROP COLUMN IF EXISTS copiado_de;
*/

commit;
