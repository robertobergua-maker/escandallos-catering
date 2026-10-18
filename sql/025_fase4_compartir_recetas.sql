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
    check (
      destino_organizacion_id is null
      or destino_organizacion_id <> origen_organizacion_id
    ),
  -- Unicidad: una receta solo se puede compartir una vez con el mismo destino.
  -- NULLS NOT DISTINCT: destino_organizacion_id NULL ('todas') también es único.
  constraint comparticiones_unique
    unique nulls not distinct (tipo, objeto_id, destino, destino_organizacion_id)
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
-- El creador debe ser el propio usuario autenticado.
drop policy if exists comparticiones_insert on public.comparticiones;
create policy comparticiones_insert
  on public.comparticiones for insert to authenticated
  with check (
    public.es_gerente_org(origen_organizacion_id)
    -- El campo created_by debe ser el propio usuario (no se puede suplantar)
    and created_by = auth.uid()
    -- La receta debe pertenecer a la org origen
    and exists (
      select 1 from public.recetas r
      where r.id            = comparticiones.objeto_id
        and r.organizacion_id = comparticiones.origen_organizacion_id
    )
  );

-- Solo gerentes de la org origen pueden modificar comparticiones.
-- WITH CHECK garantiza que objeto_id siga siendo una receta de la org origen
-- (impide mover la compartición a apuntar a una receta ajena).
drop policy if exists comparticiones_update on public.comparticiones;
create policy comparticiones_update
  on public.comparticiones for update to authenticated
  using (public.es_gerente_org(origen_organizacion_id))
  with check (
    public.es_gerente_org(origen_organizacion_id)
    and exists (
      select 1 from public.recetas r
      where r.id            = comparticiones.objeto_id
        and r.organizacion_id = comparticiones.origen_organizacion_id
    )
  );

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
--    FÓRMULA DE PRECIOS (idéntica a calcular_datos_ingrediente_receta en la app):
--      precio_unidad_linea  = inventario_org(destino) → inventario global → 0 (privado)
--      coste_total_linea    = cantidad_bruta * precio_unidad_linea
--      coste_total_receta   = sum(coste_total_linea)  [calculado vía UPDATE final]
--      precio_venta_*       = 0  (márgenes no se copian del origen)
--
--    NUNCA se leen precios de la org origen. Solo se consulta:
--      · inventario_org WHERE organizacion_id = p_org_destino
--      · inventario    WHERE organizacion_id IS NULL  (catálogo global)
--    Los ingredientes privados copiados tienen precio 0 en destino.
--
--    Flujo:
--    1. Verificar: gerente de p_org_destino + compartición activa.
--    2. Insertar cabecera de receta con coste_total = 0.
--    3. Por cada ingrediente del bucle:
--       · Resolver codigo_destino y precio_unidad.
--       · INSERT directo en receta_ingredientes (sin tabla temporal
--         para que la función sea segura de llamar N veces en la misma
--         transacción sin "already exists").
--    4. UPDATE recetas SET coste_total = sum(receta_ingredientes.coste_total)
--       WHERE id = v_nueva_receta_id.
--    5. Devolver { nueva_receta_id, privados_pendientes }.
-- ===========================================================================

create or replace function public.copiar_receta_a_org(
  p_receta_id   uuid,
  p_org_destino uuid
)
returns jsonb    -- { nueva_receta_id, privados_pendientes: [{codigo, descripcion, codigo_origen}] }
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nueva_receta_id     uuid;
  v_privados_pendientes jsonb   := '[]'::jsonb;
  v_ri                  record;
  v_slug_destino        text;
  v_codigo_destino      text;
  v_nuevo_codigo        text;
  v_nombre_receta       text;
  v_prefix_dest         text;
  v_seq                 integer;
  v_precio_unidad       numeric;
  v_coste_linea         numeric;
begin
  -- 1a. Verificar que el llamador es gerente de la org destino
  if not public.es_gerente_org(p_org_destino) then
    raise exception 'Solo el gerente de la organización destino puede copiar recetas.';
  end if;

  -- 1b. Verificar compartición activa
  if not public._comparticion_activa_para_org(p_receta_id, p_org_destino) then
    raise exception 'La receta no está compartida con tu organización o la compartición no está activa.';
  end if;

  -- Slug de la org destino (para generar códigos P-<slug>-NNNN)
  select slug into v_slug_destino
  from public.organizaciones where id = p_org_destino;

  -- Resolver nombre (evitar colisión)
  select nombre into v_nombre_receta
  from public.recetas where id = p_receta_id;

  if exists (
    select 1 from public.recetas
    where organizacion_id = p_org_destino and nombre = v_nombre_receta
  ) then
    v_nombre_receta := v_nombre_receta || ' (copia)';
  end if;
  if exists (
    select 1 from public.recetas
    where organizacion_id = p_org_destino and nombre = v_nombre_receta
  ) then
    v_nombre_receta := v_nombre_receta || ' ' || to_char(now(), 'YYYYMMDD-HH24MI');
  end if;

  -- 2. Insertar cabecera con coste_total = 0 (se recalcula en el paso 4)
  insert into public.recetas (
    organizacion_id, user_id,
    codigo_receta, nombre, categoria, tipo_plato,
    raciones_base, unidad_servicio, descripcion, elaboracion, observaciones,
    -- Márgenes a cero: no se heredan del origen
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
    0, 0, 0,   -- costes_indirectos_pct, margen_beneficio_pct, iva_pct
    0,         -- coste_total provisional; se actualiza en paso 4
    0, 0,      -- precio_venta_sin_iva, precio_venta_con_iva
    true,
    r.id       -- copiada_de: trazabilidad
  from public.recetas r
  where r.id = p_receta_id
  returning id into v_nueva_receta_id;

  -- 3. Procesar cada ingrediente e insertar directamente en receta_ingredientes
  --    (sin tabla temporal: seguro si la función se llama varias veces en la
  --    misma transacción, ya que no persiste objetos de sesión entre llamadas)
  for v_ri in
    select ri.*
    from public.receta_ingredientes ri
    where ri.receta_id = p_receta_id
    order by ri.orden
  loop
    v_codigo_destino := v_ri.codigo_ingrediente;
    v_precio_unidad  := 0;

    if v_ri.codigo_ingrediente is not null then

      -- ── Privado (organizacion_id IS NOT NULL en inventario) ──────────────
      if exists (
        select 1 from public.inventario
        where codigo          = v_ri.codigo_ingrediente
          and organizacion_id is not null
      ) then
        -- Buscar copia previa en destino (reutilizar si ya existe)
        select codigo into v_codigo_destino
        from public.inventario
        where organizacion_id   = p_org_destino
          and copiado_de_codigo = v_ri.codigo_ingrediente
        limit 1;

        if v_codigo_destino is null then
          -- No existe: crear el privado en la org destino
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

          -- Insertar privado en destino (SECURITY DEFINER: trigger
          -- _trg_inventario_protect_revisado solo actúa para role
          -- 'anon'/'authenticated'; aquí somos el propietario de la función)
          insert into public.inventario (
            codigo, familia, descripcion, unidad_medida,
            merma, organizacion_id, alergenos_revisados, copiado_de_codigo
            -- precio_unidad omitido: queda NULL (precio 0 en destino)
          )
          select
            v_nuevo_codigo,
            i_orig.familia,
            i_orig.descripcion,
            i_orig.unidad_medida,
            i_orig.merma,
            p_org_destino,
            false,                      -- pendiente revisión gerente destino
            v_ri.codigo_ingrediente     -- trazabilidad
          from public.inventario i_orig
          where i_orig.codigo = v_ri.codigo_ingrediente;

          -- ⚠️ SEGURIDAD ALIMENTARIA: copiar alérgenos del privado origen
          insert into public.ingrediente_alergenos (codigo_ingrediente, alergeno_id)
          select v_nuevo_codigo, ia.alergeno_id
          from public.ingrediente_alergenos ia
          where ia.codigo_ingrediente = v_ri.codigo_ingrediente
          on conflict (codigo_ingrediente, alergeno_id) do nothing;

          v_codigo_destino := v_nuevo_codigo;

          v_privados_pendientes := v_privados_pendientes || jsonb_build_object(
            'codigo',        v_nuevo_codigo,
            'descripcion',   (select descripcion from public.inventario
                              where codigo = v_ri.codigo_ingrediente),
            'codigo_origen', v_ri.codigo_ingrediente
          );
        end if;

        -- Precio del privado en destino = 0 (sin precio hasta que el gerente lo configure)
        v_precio_unidad := 0;

      else
        -- ── Global (organizacion_id IS NULL) ─────────────────────────────
        -- Precio: inventario_org destino → catálogo global → 0
        -- NUNCA se lee el precio de la org origen
        select coalesce(io.precio_unidad, i.precio_unidad, 0)
        into v_precio_unidad
        from public.inventario i
        left join public.inventario_org io
          on  io.codigo_ingrediente = i.codigo
          and io.organizacion_id    = p_org_destino
        where i.codigo          = v_ri.codigo_ingrediente
          and i.organizacion_id is null
        limit 1;

        v_precio_unidad := coalesce(v_precio_unidad, 0);
      end if;
    end if;

    -- Fórmula coste (idéntica a calcular_datos_ingrediente_receta en la app):
    --   coste_total_linea = cantidad_bruta * precio_unidad
    v_coste_linea := v_ri.cantidad_bruta * v_precio_unidad;

    -- INSERT directo (sin tabla temporal)
    insert into public.receta_ingredientes (
      receta_id, codigo_ingrediente, descripcion_ingrediente,
      cantidad_bruta, unidad_medida, merma, cantidad_neta,
      precio_unidad, coste_total,
      orden, es_temporal
    ) values (
      v_nueva_receta_id,
      v_codigo_destino,
      v_ri.descripcion_ingrediente,
      v_ri.cantidad_bruta,
      v_ri.unidad_medida,
      v_ri.merma,
      v_ri.cantidad_neta,
      v_precio_unidad,
      v_coste_linea,
      v_ri.orden,
      (v_codigo_destino is null)
    );
  end loop;

  -- 4. Recalcular coste_total de la receta sumando las líneas ya insertadas
  update public.recetas
     set coste_total = (
       select coalesce(sum(coste_total), 0)
       from public.receta_ingredientes
       where receta_id = v_nueva_receta_id
     )
   where id = v_nueva_receta_id;

  return jsonb_build_object(
    'nueva_receta_id',     v_nueva_receta_id,
    'privados_pendientes', v_privados_pendientes
  );
end;
$$;

revoke execute on function public.copiar_receta_a_org(uuid, uuid) from public, anon;
grant  execute on function public.copiar_receta_a_org(uuid, uuid) to authenticated;

comment on function public.copiar_receta_a_org(uuid, uuid)
  is '⚠️  Copia una receta compartida a la org destino. '
     'Precios: inventario_org destino → catálogo global → 0 (privados copiados). '
     'Fórmula: precio_unidad_linea * cantidad_bruta = coste_linea; '
     'coste_total_receta = sum(coste_linea). '
     'NUNCA lee precios de la org origen. '
     'Privados copiados con alergenos_revisados=false (seguridad alimentaria). '
     'Solo gerentes de la org destino. '
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
-- I. PRUEBA DE AISLAMIENTO
-- Ver: sql/025_prueba_aislamiento.sql
-- ===========================================================================

commit;
