-- =============================================================================
-- 025_fase4_compartir_recetas.sql
-- Fase 4 — Compartir recetas entre organizaciones mediante copia independiente.
-- =============================================================================
-- ⚠️  SEGURIDAD ALIMENTARIA: los ingredientes privados de la org origen se
--    copian a la org destino CON sus alérgenos. La copia queda con
--    alergenos_revisados = false; el gerente destino debe revisarlos antes
--    de usar la receta en producción. Ver sección E y función copiar_receta_a_org.
--
-- PRINCIPIO RECTOR: los precios y costes de la org origen NUNCA son accesibles
--   por la org destino. Ninguna función de esta fase devuelve precio_unidad,
--   coste_total, precio_venta_*, costes_indirectos_pct, margen_beneficio_pct
--   ni iva_pct de la receta origen. Las políticas RLS de recetas y
--   receta_ingredientes (por es_miembro_org) siguen intactas.
--
-- DECISIONES DE SAMIRA (definitivas para esta fase):
--   1. Destino: una organización concreta o todas.
--   2. Ingredientes privados origen: se crean en destino con nuevo código
--      P-<slug destino>-NNNN, misma descripción/familia/unidad/merma,
--      mismos alérgenos, alergenos_revisados=false (pendiente revisión destino).
--      Si ya existe una copia previa del mismo privado en destino (trazabilidad
--      por inventario.copiado_de_codigo), se reutiliza.
--   3. Solo recetas en esta fase; menus quedan para la siguiente.
--   4. La copia es independiente del original: pertenece a la org destino.
--
-- SUBRECETAS: no existe soporte de subrecetas en el esquema actual
--   (receta_ingredientes.codigo_ingrediente no referencia recetas). No se
--   requiere ningún bloqueo adicional.
--
-- ESTADO DEL ADMIN (post-023d): NO existe ninguna política *_admin_all
--   en las tablas operativas (recetas, receta_ingredientes). Las funciones
--   de esta fase NO incluyen bypass de admin: solo gerentes de la org
--   origen/destino pueden compartir y copiar.
--
-- Requisitos previos: 022, 023a, 023c, 023d, 024, 024b (todas aplicadas).
-- Reversible: ejecutar 025_rollback.sql.
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

-- ===========================================================================
-- A. COLUMNAS DE TRAZABILIDAD
-- ===========================================================================

-- recetas.copiada_de: UUID de la receta original (NULL si es original)
alter table public.recetas
  add column if not exists copiada_de uuid
    references public.recetas(id) on delete set null;

comment on column public.recetas.copiada_de
  is 'ID de la receta original de la que se hizo esta copia. '
     'NULL si es original. La copia es independiente y no se sincroniza.';

create index if not exists idx_recetas_copiada_de
  on public.recetas (copiada_de)
  where copiada_de is not null;

-- inventario.copiado_de_codigo: código del ingrediente privado origen
-- que sirvió de base para crear este ingrediente privado en la org destino.
-- Permite reutilizar la copia si ya existe en lugar de duplicar.
alter table public.inventario
  add column if not exists copiado_de_codigo text;

comment on column public.inventario.copiado_de_codigo
  is 'Código del ingrediente privado origen (de otra org) del que se copió este. '
     'NULL si es original. Solo aplica a ingredientes privados copiados mediante '
     'copiar_receta_a_org.';

create index if not exists idx_inventario_copiado_de_codigo
  on public.inventario (organizacion_id, copiado_de_codigo)
  where copiado_de_codigo is not null;


-- ===========================================================================
-- B. TABLA: comparticiones
-- ===========================================================================

create table if not exists public.comparticiones (
  id                      uuid        primary key default gen_random_uuid(),
  -- La org que comparte. NOT NULL: en esta fase solo gerentes de la org comparten.
  origen_organizacion_id  uuid        not null
                            references public.organizaciones(id) on delete cascade,
  -- Tipo ampliable en futuras fases; hoy solo 'receta'.
  tipo                    text        not null,
  objeto_id               uuid        not null,
  destino                 text        not null default 'todas',
  destino_organizacion_id uuid        references public.organizaciones(id) on delete cascade,
  activa                  boolean     not null default true,
  created_by              uuid        references auth.users(id) on delete set null,
  created_at              timestamptz not null default now(),

  constraint comparticiones_tipo_check
    check (tipo in ('receta')),       -- ampliable: añadir 'menu', 'menu_completo', etc.
  constraint comparticiones_destino_check
    check (destino in ('todas', 'especifica')),
  constraint comparticiones_destino_org_check
    check (
      (destino = 'todas'      and destino_organizacion_id is null)
      or (destino = 'especifica' and destino_organizacion_id is not null)
    ),
  constraint comparticiones_no_autocomparticion
    check (origen_organizacion_id <> coalesce(destino_organizacion_id, gen_random_uuid())),
  -- Unicidad: una receta solo se puede compartir una vez con el mismo destino
  constraint comparticiones_unique
    unique (tipo, objeto_id, destino, destino_organizacion_id)
);

comment on table public.comparticiones
  is 'Registro de recetas compartidas entre organizaciones. '
     'Solo gerentes de la org origen crean/desactivan comparticiones.';
comment on column public.comparticiones.origen_organizacion_id
  is 'Organización que comparte. NOT NULL: los gerentes de la org son los responsables.';
comment on column public.comparticiones.destino
  is '"todas" = visible para todas las orgs activas. '
     '"especifica" = solo para destino_organizacion_id.';

create index if not exists idx_comparticiones_objeto
  on public.comparticiones (tipo, objeto_id);
create index if not exists idx_comparticiones_destino_org
  on public.comparticiones (destino_organizacion_id)
  where destino_organizacion_id is not null;
create index if not exists idx_comparticiones_origen
  on public.comparticiones (origen_organizacion_id);
create index if not exists idx_comparticiones_activa
  on public.comparticiones (activa)
  where activa = true;


-- ===========================================================================
-- C. RLS: comparticiones
--    Sin bypass de admin (respeta 023d).
--    Solo el gerente de la org origen gestiona sus comparticiones.
--    Los miembros de la org destino solo pueden leer metadatos de lo
--    compartido con ellos (a través de listar_recetas_compartidas_conmigo).
--    No existe política SELECT directa en esta tabla para miembros normales:
--    el acceso va siempre por función SECURITY DEFINER.
-- ===========================================================================

alter table public.comparticiones enable row level security;

-- Solo gerentes de la org origen pueden leer sus comparticiones.
drop policy if exists comparticiones_select on public.comparticiones;
create policy comparticiones_select
  on public.comparticiones for select to authenticated
  using (public.es_gerente_org(origen_organizacion_id));

-- Solo gerentes de la org origen pueden crear comparticiones.
drop policy if exists comparticiones_insert on public.comparticiones;
create policy comparticiones_insert
  on public.comparticiones for insert to authenticated
  with check (
    public.es_gerente_org(origen_organizacion_id)
    -- La receta debe pertenecer a la org origen
    and exists (
      select 1 from public.recetas r
      where r.id          = comparticiones.objeto_id
        and r.organizacion_id = comparticiones.origen_organizacion_id
    )
  );

-- Solo gerentes de la org origen pueden desactivar o borrar.
drop policy if exists comparticiones_update on public.comparticiones;
create policy comparticiones_update
  on public.comparticiones for update to authenticated
  using    (public.es_gerente_org(origen_organizacion_id))
  with check (public.es_gerente_org(origen_organizacion_id));

drop policy if exists comparticiones_delete on public.comparticiones;
create policy comparticiones_delete
  on public.comparticiones for delete to authenticated
  using (public.es_gerente_org(origen_organizacion_id));


-- ===========================================================================
-- D. FUNCIÓN INTERNA: _comparticion_activa_para_org
--    True si existe una compartición activa que permita a p_org_destino
--    ver la receta p_receta_id. SECURITY DEFINER; REVOKE a todos los roles
--    externos (solo la llaman otras funciones SECURITY DEFINER de este script).
-- ===========================================================================

create or replace function public._comparticion_activa_para_org(
  p_receta_id   uuid,
  p_org_destino uuid
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
    where c.tipo      = 'receta'
      and c.objeto_id = p_receta_id
      and c.activa    = true
      and (
        c.destino = 'todas'
        or (c.destino = 'especifica' and c.destino_organizacion_id = p_org_destino)
      )
      and c.origen_organizacion_id <> p_org_destino
  );
$$;

-- Función auxiliar interna: solo la llaman otras funciones de este script.
revoke execute on function public._comparticion_activa_para_org(uuid, uuid)
  from public, anon, authenticated;

comment on function public._comparticion_activa_para_org(uuid, uuid)
  is 'Función interna. Verifica si existe compartición activa de la receta '
     'para la org destino. No callable directamente.';


-- ===========================================================================
-- E. FUNCIÓN: listar_organizaciones_destino
--    Para el gerente: devuelve id + nombre de las demás orgs activas
--    (candidatas para compartir). Solo gerentes.
-- ===========================================================================

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
  -- Solo gerentes pueden listar destinos
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
    -- Excluir las propias orgs del gerente
    and o.id <> all(v_orgs_gerente)
  order by o.nombre;
end;
$$;

revoke execute on function public.listar_organizaciones_destino() from public, anon;
grant  execute on function public.listar_organizaciones_destino() to authenticated;

comment on function public.listar_organizaciones_destino()
  is 'Devuelve id + nombre de las orgs activas distintas a las del gerente. '
     'Solo para gerentes.';


-- ===========================================================================
-- F. FUNCIÓN: listar_recetas_compartidas_conmigo
--    Devuelve metadatos (SIN precios ni costes) de recetas compartidas
--    activas con la organización p_org. Solo miembros de p_org.
-- ===========================================================================

create or replace function public.listar_recetas_compartidas_conmigo(
  p_org uuid
)
returns table (
  comparticion_id         uuid,
  receta_id               uuid,
  nombre                  text,
  categoria               text,
  tipo_plato              text,
  raciones_base           numeric,
  activa_receta           boolean,
  org_origen_nombre       text,
  org_origen_slug         text,
  ya_copiada              boolean   -- true si ya existe una copia en p_org
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.es_miembro_org(p_org) then
    raise exception 'Sin acceso a la organización indicada.';
  end if;

  return query
  select
    c.id                                                          as comparticion_id,
    r.id                                                          as receta_id,
    r.nombre,
    r.categoria,
    r.tipo_plato,
    r.raciones_base,
    r.activa                                                      as activa_receta,
    o.nombre                                                      as org_origen_nombre,
    o.slug                                                        as org_origen_slug,
    exists (
      select 1 from public.recetas rc
      where rc.copiada_de     = r.id
        and rc.organizacion_id = p_org
    )                                                             as ya_copiada
    -- NOTA: precio_venta_*, coste_total, costes_indirectos_pct, margen_beneficio_pct,
    -- iva_pct deliberadamente EXCLUIDOS.
  from public.comparticiones c
  join public.recetas r       on r.id = c.objeto_id
  join public.organizaciones o on o.id = c.origen_organizacion_id
  where c.tipo   = 'receta'
    and c.activa = true
    and (
      c.destino = 'todas'
      or (c.destino = 'especifica' and c.destino_organizacion_id = p_org)
    )
    and c.origen_organizacion_id <> p_org
  order by o.nombre, r.nombre;
end;
$$;

revoke execute on function public.listar_recetas_compartidas_conmigo(uuid) from public, anon;
grant  execute on function public.listar_recetas_compartidas_conmigo(uuid) to authenticated;

comment on function public.listar_recetas_compartidas_conmigo(uuid)
  is 'Metadatos de recetas compartidas activas con la org. '
     'SIN precios ni costes. Solo miembros de la org.';


-- ===========================================================================
-- G. FUNCIÓN: ver_receta_compartida
--    Vista previa de una receta compartida: ingredientes (sin precios),
--    elaboración y alérgenos. No devuelve ningún campo económico de origen.
--    Accesible para miembros de cualquier org con compartición activa.
-- ===========================================================================

create or replace function public.ver_receta_compartida(
  p_receta_id uuid,
  p_org       uuid    -- organización del llamador (para validar acceso)
)
returns table (
  receta_id          uuid,
  nombre             text,
  categoria          text,
  tipo_plato         text,
  raciones_base      numeric,
  unidad_servicio    text,
  descripcion        text,
  elaboracion        text,
  observaciones      text,
  activa             boolean,
  org_origen_nombre  text,
  ingredientes       jsonb,   -- sin precio_unidad ni coste_total
  alergenos          jsonb    -- lista de alérgenos de la receta (de globales y privados)
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  -- Verificar membresía en la org del llamador
  if not public.es_miembro_org(p_org) then
    raise exception 'Sin acceso a la organización indicada.';
  end if;

  -- Verificar que existe compartición activa para esta org
  if not public._comparticion_activa_para_org(p_receta_id, p_org) then
    raise exception 'La receta no está compartida con tu organización o la compartición está desactivada.';
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
    o.nombre                                                        as org_origen_nombre,
    -- Ingredientes SIN precio_unidad ni coste_total ni costes_indirectos ni margen
    (
      select jsonb_agg(
        jsonb_build_object(
          'orden',                  ri.orden,
          'codigo_ingrediente',     ri.codigo_ingrediente,
          'descripcion_ingrediente', ri.descripcion_ingrediente,
          'cantidad_bruta',         ri.cantidad_bruta,
          'unidad_medida',          ri.unidad_medida,
          'merma',                  ri.merma,
          'cantidad_neta',          ri.cantidad_neta,
          'es_privado',             (i.organizacion_id is not null)
          -- precio_unidad, coste_total: EXCLUIDOS
        )
        order by ri.orden
      )
      from public.receta_ingredientes ri
      left join public.inventario i on i.codigo = ri.codigo_ingrediente
      where ri.receta_id = r.id
    )                                                               as ingredientes,
    -- Alérgenos: se calculan dinámicamente desde ingrediente_alergenos del catálogo
    -- global y de privados de la org origen visibles por membresía.
    (
      select jsonb_agg(distinct jsonb_build_object(
        'codigo',  al.codigo,
        'nombre',  al.nombre
      ) order by jsonb_build_object('codigo', al.codigo, 'nombre', al.nombre))
      from public.receta_ingredientes ri2
      join public.ingrediente_alergenos ia
        on ia.codigo_ingrediente = ri2.codigo_ingrediente
      join public.alergenos al
        on al.id = ia.alergeno_id
      where ri2.receta_id = r.id
        and al.activo = true
    )                                                               as alergenos
  from public.recetas r
  join public.organizaciones o on o.id = r.organizacion_id
  where r.id = p_receta_id;
end;
$$;

revoke execute on function public.ver_receta_compartida(uuid, uuid) from public, anon;
grant  execute on function public.ver_receta_compartida(uuid, uuid) to authenticated;

comment on function public.ver_receta_compartida(uuid, uuid)
  is 'Vista previa de una receta compartida con ingredientes (sin precios) y alérgenos. '
     'Verifica compartición activa internamente. '
     'NUNCA devuelve precio_unidad, coste_total, precio_venta_*, '
     'costes_indirectos_pct, margen_beneficio_pct ni iva_pct.';


-- ===========================================================================
-- H. FUNCIÓN: copiar_receta_a_org
--    ⚠️  SEGURIDAD ALIMENTARIA: copia ingredientes privados con sus alérgenos.
--
--    Flujo:
--    1. Verifica: llamador es gerente de p_org_destino.
--    2. Verifica: existe compartición activa para (receta, p_org_destino).
--    3. Por cada ingrediente de la receta:
--       a. Si es global (codigo_ingrediente en catálogo global): se usa el mismo código.
--       b. Si es privado (código empieza por 'P-'):
--          · Buscar si ya existe en p_org_destino con copiado_de_codigo = código origen.
--          · Si existe: reutilizarlo (mismo código destino).
--          · Si no: crear un nuevo privado en p_org_destino con el generador
--            crear_ingrediente_privado_interno (SECURITY DEFINER, misma lógica
--            que crear_ingrediente_privado pero sin exigir es_gerente_org al llamador
--            ya que la propia función copiar_receta_a_org ya lo verificó).
--            Copiar alérgenos del privado origen al nuevo privado destino.
--            alergenos_revisados = false (el gerente destino debe revisarlos).
--    4. Insertar la nueva receta en p_org_destino con:
--       · costes_indirectos_pct, margen_beneficio_pct, iva_pct = 0 (sin datos de origen)
--       · coste_total, precio_venta_sin_iva, precio_venta_con_iva = 0
--       · copiada_de = p_receta_id
--    5. Insertar receta_ingredientes con códigos resueltos y precio_unidad = 0.
--    6. Devolver: id de la nueva receta + lista de privados pendientes de revisión.
--
--    Si el nombre de la receta ya existe en p_org_destino: añade sufijo " (copia)".
--    Si aún así choca (hay CHECK UNIQUE en el nombre): añade timestamp.
-- ===========================================================================

create or replace function public.copiar_receta_a_org(
  p_receta_id   uuid,
  p_org_destino uuid
)
returns jsonb    -- { nueva_receta_id, privados_pendientes: [{codigo, descripcion}] }
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nueva_receta_id    uuid;
  v_privados_pendientes jsonb := '[]'::jsonb;
  v_ri                 record;
  v_slug_destino       text;
  v_codigo_destino     text;
  v_nuevo_codigo       text;
  v_nombre_receta      text;
  v_prefix_dest        text;
  v_seq                integer;
begin
  -- 1. Verificar que el llamador es gerente de la org destino
  if not public.es_gerente_org(p_org_destino) then
    raise exception 'Solo el gerente de la organización destino puede copiar recetas.';
  end if;

  -- 2. Verificar compartición activa
  if not public._comparticion_activa_para_org(p_receta_id, p_org_destino) then
    raise exception 'La receta no está compartida con tu organización o la compartición no está activa.';
  end if;

  -- Obtener slug de la org destino (necesario para generar códigos privados)
  select slug into v_slug_destino
  from public.organizaciones where id = p_org_destino;

  -- 3. Resolver nombre (evitar colisión)
  select nombre into v_nombre_receta
  from public.recetas where id = p_receta_id;

  if exists (
    select 1 from public.recetas
    where organizacion_id = p_org_destino and nombre = v_nombre_receta
  ) then
    v_nombre_receta := v_nombre_receta || ' (copia)';
  end if;
  -- Si aún choca, añadir timestamp de segundo
  if exists (
    select 1 from public.recetas
    where organizacion_id = p_org_destino and nombre = v_nombre_receta
  ) then
    v_nombre_receta := v_nombre_receta || ' ' || to_char(now(), 'YYYYMMDD-HH24MI');
  end if;

  -- 4. Insertar la nueva receta (sin datos económicos de origen)
  insert into public.recetas (
    organizacion_id, user_id,
    codigo_receta, nombre, categoria, tipo_plato,
    raciones_base, unidad_servicio, descripcion, elaboracion, observaciones,
    -- Campos económicos a cero: la org destino los calculará con sus propios precios
    costes_indirectos_pct, margen_beneficio_pct, iva_pct,
    coste_total, precio_venta_sin_iva, precio_venta_con_iva,
    activa, copiada_de
  )
  select
    p_org_destino,
    auth.uid(),
    r.codigo_receta,
    v_nombre_receta,
    r.categoria,
    r.tipo_plato,
    r.raciones_base,
    r.unidad_servicio,
    r.descripcion,
    r.elaboracion,
    r.observaciones,
    0,   -- costes_indirectos_pct
    0,   -- margen_beneficio_pct
    0,   -- iva_pct
    0,   -- coste_total
    0,   -- precio_venta_sin_iva
    0,   -- precio_venta_con_iva
    true,
    r.id -- copiada_de: trazabilidad
  from public.recetas r
  where r.id = p_receta_id
  returning id into v_nueva_receta_id;

  -- 5. Procesar cada ingrediente de la receta origen
  for v_ri in
    select ri.*
    from public.receta_ingredientes ri
    where ri.receta_id = p_receta_id
    order by ri.orden
  loop
    v_codigo_destino := v_ri.codigo_ingrediente;

    -- Comprobar si el ingrediente es privado (código comienza por 'P-' en minúsculas)
    if v_ri.codigo_ingrediente is not null
       and lower(v_ri.codigo_ingrediente) like 'p-%'
       and exists (
         select 1 from public.inventario i
         where i.codigo = v_ri.codigo_ingrediente
           and i.organizacion_id is not null
       )
    then
      -- Es un ingrediente privado de la org origen.
      -- Buscar si ya existe una copia en la org destino (reutilizar).
      select codigo into v_codigo_destino
      from public.inventario
      where organizacion_id    = p_org_destino
        and copiado_de_codigo  = v_ri.codigo_ingrediente
      limit 1;

      if v_codigo_destino is null then
        -- No existe copia previa: crear el ingrediente privado en la org destino.
        v_prefix_dest := 'P-' || v_slug_destino || '-';

        -- Lock anti-race para el secuencial de la org destino
        perform pg_advisory_xact_lock(hashtext(p_org_destino::text));

        select coalesce(
          max(nullif(substring(codigo from '-(\d+)$'), '')::integer), 0
        ) + 1
        into v_seq
        from public.inventario
        where organizacion_id = p_org_destino
          and codigo like (v_prefix_dest || '%');

        v_nuevo_codigo := v_prefix_dest || lpad(v_seq::text, 4, '0');

        -- Insertar el nuevo privado en la org destino
        -- (Usamos INSERT directo porque estamos en SECURITY DEFINER y ya verificamos
        --  el permiso del llamador arriba. El trigger _trg_inventario_protect_revisado
        --  forzará alergenos_revisados=false para current_user='postgres'? No:
        --  el trigger solo actúa si current_user IN ('anon','authenticated'). Aquí
        --  current_user = propietario de la función (postgres), así que el trigger
        --  no interviene — insertamos alergenos_revisados=false explícitamente.)
        insert into public.inventario (
          codigo, familia, descripcion, unidad_medida,
          merma,  -- copiamos la merma del origen como referencia
          organizacion_id, alergenos_revisados, copiado_de_codigo
        )
        select
          v_nuevo_codigo,
          i_orig.familia,
          i_orig.descripcion,
          i_orig.unidad_medida,
          i_orig.merma,    -- merma de referencia (sin precio)
          p_org_destino,
          false,           -- pendiente de revisión por el gerente destino
          v_ri.codigo_ingrediente  -- trazabilidad
        from public.inventario i_orig
        where i_orig.codigo = v_ri.codigo_ingrediente;

        -- Copiar alérgenos del privado origen al nuevo privado destino
        -- ⚠️  SEGURIDAD ALIMENTARIA: los alérgenos viajan con la copia.
        insert into public.ingrediente_alergenos (codigo_ingrediente, alergeno_id)
        select v_nuevo_codigo, ia.alergeno_id
        from public.ingrediente_alergenos ia
        where ia.codigo_ingrediente = v_ri.codigo_ingrediente
        on conflict (codigo_ingrediente, alergeno_id) do nothing;

        v_codigo_destino := v_nuevo_codigo;

        -- Añadir a la lista de privados pendientes de revisión
        v_privados_pendientes := v_privados_pendientes || jsonb_build_object(
          'codigo',      v_nuevo_codigo,
          'descripcion', (select descripcion from public.inventario where codigo = v_ri.codigo_ingrediente),
          'codigo_origen', v_ri.codigo_ingrediente
        );
      end if;
      -- Si ya existía copia previa (v_codigo_destino != null), la usamos sin tocar alérgenos
    end if;

    -- Insertar línea de ingrediente en la nueva receta (sin precio ni coste)
    insert into public.receta_ingredientes (
      receta_id, codigo_ingrediente, descripcion_ingrediente,
      cantidad_bruta, unidad_medida, merma, cantidad_neta,
      precio_unidad, coste_total,   -- a 0: la org destino los calculará
      orden, es_temporal
    ) values (
      v_nueva_receta_id,
      v_codigo_destino,
      v_ri.descripcion_ingrediente,
      v_ri.cantidad_bruta,
      v_ri.unidad_medida,
      v_ri.merma,
      v_ri.cantidad_neta,
      0,    -- precio_unidad
      0,    -- coste_total
      v_ri.orden,
      (v_codigo_destino is null)   -- es_temporal si no se pudo resolver
    );
  end loop;

  return jsonb_build_object(
    'nueva_receta_id',    v_nueva_receta_id,
    'privados_pendientes', v_privados_pendientes
  );
end;
$$;

revoke execute on function public.copiar_receta_a_org(uuid, uuid) from public, anon;
grant  execute on function public.copiar_receta_a_org(uuid, uuid) to authenticated;

comment on function public.copiar_receta_a_org(uuid, uuid)
  is '⚠️  Copia una receta compartida a la org destino. '
     'Los ingredientes privados origen se crean en destino con alergenos_revisados=false. '
     'NUNCA copia precios, costes ni márgenes. Solo gerentes de la org destino. '
     'Devuelve {nueva_receta_id, privados_pendientes: [{codigo, descripcion, codigo_origen}]}.';


-- ===========================================================================
-- AUDITORÍA POST-MIGRACIÓN
-- ===========================================================================

-- 1. Columna copiada_de añadida correctamente:
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name   = 'recetas'
  and column_name  = 'copiada_de';

-- 2. Columna copiado_de_codigo en inventario:
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name   = 'inventario'
  and column_name  = 'copiado_de_codigo';

-- 3. Tabla comparticiones creada con RLS activado:
select relname, relrowsecurity
from pg_class
where relnamespace = 'public'::regnamespace
  and relname = 'comparticiones';

-- 4. Funciones creadas:
select proname
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname in (
    '_comparticion_activa_para_org',
    'listar_organizaciones_destino',
    'listar_recetas_compartidas_conmigo',
    'ver_receta_compartida',
    'copiar_receta_a_org'
  )
order by proname;
-- Debe devolver 5 filas.


-- ===========================================================================
-- I. PRUEBA DE AISLAMIENTO (transacción con ROLLBACK — no deja rastro)
-- Ejecutar en Supabase SQL Editor. Sustituir los UUIDs reales.
-- Requisitos: org Samirarte (slug 'samirarte'), org Pruebas (slug 'pruebas'),
--   gerente Samirarte (uid_gerente_samirarte), chef Samirarte (uid_chef_samirarte),
--   gerente Pruebas (uid_gerente_pruebas), tercera org (slug 'tercera', si existe).
-- ===========================================================================
/*
begin;

-- ─── Preparación: crear compartición de prueba ───────────────────────────────
-- Simular como gerente de Samirarte
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"<uid_gerente_samirarte>","role":"authenticated"}';

-- Crear compartición específica con Pruebas
insert into public.comparticiones (origen_organizacion_id, tipo, objeto_id, destino, destino_organizacion_id, created_by)
values (
  (select id from public.organizaciones where slug='samirarte'),
  'receta',
  (select id from public.recetas where organizacion_id=(select id from public.organizaciones where slug='samirarte') limit 1),
  'especifica',
  (select id from public.organizaciones where slug='pruebas'),
  auth.uid()
);
-- Si falla: el gerente no es de Samirarte o no hay recetas en Samirarte.

-- ─── TEST 1: gerente origen puede listar sus comparticiones ──────────────────
select count(*) as comparticiones_gerente_samirarte
from public.comparticiones
where origen_organizacion_id = (select id from public.organizaciones where slug='samirarte');
-- Debe ser ≥ 1.

-- ─── TEST 2: chef (no gerente) de Samirarte NO puede copiar ──────────────────
set local "request.jwt.claims" to '{"sub":"<uid_chef_samirarte>","role":"authenticated"}';
select public.copiar_receta_a_org(
  (select id from public.recetas where organizacion_id=(select id from public.organizaciones where slug='samirarte') limit 1),
  (select id from public.organizaciones where slug='pruebas')
);
-- Debe lanzar excepción: "Solo el gerente de la organización destino puede copiar recetas."

-- ─── TEST 3: gerente Pruebas SÍ puede copiar ─────────────────────────────────
set local "request.jwt.claims" to '{"sub":"<uid_gerente_pruebas>","role":"authenticated"}';
select public.copiar_receta_a_org(
  (select id from public.recetas where organizacion_id=(select id from public.organizaciones where slug='samirarte') limit 1),
  (select id from public.organizaciones where slug='pruebas')
);
-- Debe devolver {nueva_receta_id: "...", privados_pendientes: [...]}.
-- nueva_receta_id debe apuntar a una receta de Pruebas.

-- ─── TEST 4: ver_receta_compartida NO devuelve precios ───────────────────────
set local "request.jwt.claims" to '{"sub":"<uid_gerente_pruebas>","role":"authenticated"}';
with vista as (
  select * from public.ver_receta_compartida(
    (select id from public.recetas where organizacion_id=(select id from public.organizaciones where slug='samirarte') limit 1),
    (select id from public.organizaciones where slug='pruebas')
  )
)
select
  -- Estas columnas NO deben existir en el resultado:
  (ingredientes::text) like '%precio_unidad%'    as contiene_precio_unidad,
  (ingredientes::text) like '%coste_total%'      as contiene_coste_total
from vista;
-- Ambas columnas deben ser FALSE.

-- ─── TEST 5: tercera org NO ve la compartición específica ────────────────────
-- Si existe un usuario de una tercera org:
-- set local "request.jwt.claims" to '{"sub":"<uid_tercera_org>","role":"authenticated"}';
-- select public.listar_recetas_compartidas_conmigo(
--   (select id from public.organizaciones where slug='tercera')
-- );
-- Debe devolver 0 filas (la compartición es 'especifica' para Pruebas, no para Tercera).

-- ─── TEST 6: privados copiados tienen alergenos_revisados = false ─────────────
set local "request.jwt.claims" to '{"sub":"<uid_gerente_pruebas>","role":"authenticated"}';
select codigo, alergenos_revisados, copiado_de_codigo
from public.inventario
where organizacion_id = (select id from public.organizaciones where slug='pruebas')
  and copiado_de_codigo is not null;
-- Todos deben tener alergenos_revisados = false.
-- Los alérgenos deben existir en ingrediente_alergenos para esos códigos.
select count(*) as alergenos_copiados
from public.ingrediente_alergenos ia
where ia.codigo_ingrediente in (
  select codigo from public.inventario
  where organizacion_id = (select id from public.organizaciones where slug='pruebas')
    and copiado_de_codigo is not null
);
-- Debe ser > 0 si los privados origen tenían alérgenos.

-- ─── TEST 7: privados copiados tienen MISMOS alérgenos que el original ────────
-- Verificar que cada alérgeno del origen existe en la copia:
select
  ia_orig.codigo_ingrediente as codigo_origen,
  al.nombre                  as alergeno,
  exists (
    select 1 from public.ingrediente_alergenos ia_dest
    join public.inventario i_dest on i_dest.codigo = ia_dest.codigo_ingrediente
    where i_dest.organizacion_id  = (select id from public.organizaciones where slug='pruebas')
      and i_dest.copiado_de_codigo = ia_orig.codigo_ingrediente
      and ia_dest.alergeno_id      = ia_orig.alergeno_id
  ) as alergenoExisteEnCopia
from public.ingrediente_alergenos ia_orig
join public.inventario i_orig on i_orig.codigo = ia_orig.codigo_ingrediente
join public.alergenos al on al.id = ia_orig.alergeno_id
where i_orig.organizacion_id = (select id from public.organizaciones where slug='samirarte')
  and i_orig.codigo like 'P-%';
-- alergenoExisteEnCopia debe ser TRUE en todas las filas.

-- ─── TEST 8: compartición desactivada → copiar falla ─────────────────────────
set local "request.jwt.claims" to '{"sub":"<uid_gerente_samirarte>","role":"authenticated"}';
update public.comparticiones set activa = false
where origen_organizacion_id = (select id from public.organizaciones where slug='samirarte')
  and tipo = 'receta';

set local "request.jwt.claims" to '{"sub":"<uid_gerente_pruebas>","role":"authenticated"}';
select public.copiar_receta_a_org(
  (select id from public.recetas where organizacion_id=(select id from public.organizaciones where slug='samirarte') limit 1),
  (select id from public.organizaciones where slug='pruebas')
);
-- Debe lanzar excepción: "La receta no está compartida..."

-- ─── TEST 9: anon no puede ejecutar ninguna función ──────────────────────────
set local role anon;
select public.listar_recetas_compartidas_conmigo(
  (select id from public.organizaciones where slug='pruebas')
);
-- Debe lanzar excepción o "permission denied".

select public.copiar_receta_a_org(
  (select id from public.recetas limit 1),
  (select id from public.organizaciones where slug='pruebas')
);
-- Debe lanzar excepción o "permission denied".

-- ─── TEST 10: ver_receta_compartida sin compartición → excepción ─────────────
set local "request.jwt.claims" to '{"sub":"<uid_gerente_pruebas>","role":"authenticated"}';
select * from public.ver_receta_compartida(
  gen_random_uuid(),   -- UUID inexistente
  (select id from public.organizaciones where slug='pruebas')
);
-- Debe lanzar excepción: "La receta no está compartida..."

rollback;   -- La prueba no deja rastro en la BD
*/

commit;
