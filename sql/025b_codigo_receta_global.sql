-- =============================================================================
-- 025b_codigo_receta_global.sql
-- Arregla el bug de colisión en recetas.codigo_receta al compartir entre orgs.
--
-- PROBLEMA:
--   recetas.codigo_receta tiene un UNIQUE global en Supabase
--   (constraint recetas_codigo_receta_key). copiar_receta_a_org copiaba el
--   codigo_receta del origen tal cual, fallando siempre con:
--     "duplicate key value violates unique constraint recetas_codigo_receta_key"
--   También: generar_codigo_receta() en la app lee recetas con RLS → solo ve
--   las de su org → asigna REC-0001 aunque ya exista en otra org.
--
-- SOLUCIÓN:
--   A. Función public.siguiente_codigo_receta(): SECURITY DEFINER, ve TODAS las
--      recetas sin RLS, usa pg_advisory_xact_lock para evitar race conditions,
--      devuelve el siguiente REC-NNNN disponible global. Solo devuelve el
--      código (text): ningún otro dato de recetas es accesible.
--   B. copiar_receta_a_org (create or replace): usa siguiente_codigo_receta()
--      en lugar de copiar el código del origen.
--
-- Requisito previo: 025_fase4_compartir_recetas.sql ya aplicado.
-- Reversible: 025b_rollback.sql.
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

-- ===========================================================================
-- A. FUNCIÓN: siguiente_codigo_receta
--    Calcula el siguiente REC-NNNN disponible globalmente (sin RLS).
--    SECURITY DEFINER: ve todas las filas de recetas independientemente del
--    rol del llamador. Solo devuelve el código generado (text), nunca datos
--    de otras recetas.
--    pg_advisory_xact_lock: evita que dos sesiones concurrentes obtengan el
--    mismo número (el lock se libera al final de la transacción del llamador).
-- ===========================================================================

create or replace function public.siguiente_codigo_receta()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max     integer;
  v_codigo  text;
begin
  -- Solo usuarios autenticados pueden obtener códigos
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión para obtener un código de receta.';
  end if;

  -- Lock exclusivo de transacción para evitar race conditions entre sesiones.
  -- hashtext('recetas_codigo_receta') produce un entero estable y único para
  -- este recurso. El lock se libera al hacer commit/rollback en el llamador.
  perform pg_advisory_xact_lock(hashtext('recetas_codigo_receta'));

  -- Calcular el máximo numérico de todos los códigos REC-NNNN existentes,
  -- sin filtro de organización ni de usuario (SECURITY DEFINER, sin RLS).
  select coalesce(
    max(
      nullif(substring(codigo_receta from '^REC-(\d+)$'), '')::integer
    ),
    0
  )
  into v_max
  from public.recetas
  where codigo_receta ~ '^REC-\d+$';

  -- Siguiente número, mínimo 4 dígitos
  v_codigo := 'REC-' || lpad((v_max + 1)::text, 4, '0');

  return v_codigo;
end;
$$;

revoke execute on function public.siguiente_codigo_receta() from public, anon;
grant  execute on function public.siguiente_codigo_receta() to authenticated;

comment on function public.siguiente_codigo_receta()
  is 'Devuelve el siguiente código REC-NNNN disponible globalmente. '
     'SECURITY DEFINER: ve todas las recetas sin RLS para garantizar unicidad '
     'entre organizaciones. Usa pg_advisory_xact_lock para evitar colisiones. '
     'Solo devuelve el código (text), nunca datos de otras recetas.';


-- ===========================================================================
-- B. copiar_receta_a_org: create or replace usando siguiente_codigo_receta()
--    Solo cambia la línea de codigo_receta en el INSERT de la cabecera.
--    El resto de la función es idéntico al 025.
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

  -- Slug de la org destino (para generar códigos P-<slug>-NNNN de privados)
  select slug into v_slug_destino
  from public.organizaciones where id = p_org_destino;

  -- Resolver nombre (evitar colisión en la org destino)
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

  -- 2. Insertar cabecera con codigo_receta global único y coste_total = 0
  insert into public.recetas (
    organizacion_id, user_id,
    codigo_receta,                  -- ← siguiente código global, nunca el del origen
    nombre, categoria, tipo_plato,
    raciones_base, unidad_servicio, descripcion, elaboracion, observaciones,
    costes_indirectos_pct, margen_beneficio_pct, iva_pct,
    coste_total, precio_venta_sin_iva, precio_venta_con_iva,
    activa, copiada_de
  )
  select
    p_org_destino,
    auth.uid(),
    public.siguiente_codigo_receta(),   -- código global único, sin RLS
    v_nombre_receta,
    r.categoria,
    r.tipo_plato,
    r.raciones_base,
    r.unidad_servicio,
    r.descripcion,
    r.elaboracion,
    r.observaciones,
    0, 0, 0,   -- costes_indirectos_pct, margen_beneficio_pct, iva_pct
    0,         -- coste_total provisional; se actualiza tras insertar líneas
    0, 0,      -- precio_venta_sin_iva, precio_venta_con_iva
    true,
    r.id       -- copiada_de: trazabilidad
  from public.recetas r
  where r.id = p_receta_id
  returning id into v_nueva_receta_id;

  -- 3. Procesar cada ingrediente e insertar directamente en receta_ingredientes
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
          -- Crear el privado en la org destino
          v_prefix_dest := 'P-' || v_slug_destino || '-';

          perform pg_advisory_xact_lock(hashtext(p_org_destino::text));

          select coalesce(
            max(nullif(substring(codigo from '-(\d+)$'), '')::integer), 0
          ) + 1
          into v_seq
          from public.inventario
          where organizacion_id = p_org_destino
            and codigo like (v_prefix_dest || '%');

          v_nuevo_codigo := v_prefix_dest || lpad(v_seq::text, 4, '0');

          -- Insertar privado en destino (SECURITY DEFINER)
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

        v_precio_unidad := 0;  -- privado: sin precio en destino todavía

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

  -- 4. Recalcular coste_total sumando las líneas ya insertadas
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
     'codigo_receta: usa siguiente_codigo_receta() (SECURITY DEFINER, global). '
     'Precios: inventario_org destino → catálogo global → 0 (privados). '
     'NUNCA lee precios ni codigo_receta de la org origen. '
     'Solo gerentes de la org destino.';


-- ===========================================================================
-- AUDITORÍA POST-MIGRACIÓN
-- ===========================================================================

-- Función creada:
select proname, prosecdef
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname = 'siguiente_codigo_receta';
-- Debe devolver 1 fila con prosecdef = true.

-- copiar_receta_a_org actualizada:
select proname, prosecdef
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname = 'copiar_receta_a_org';
-- Debe devolver 1 fila con prosecdef = true.

commit;
