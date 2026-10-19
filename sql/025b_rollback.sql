-- =============================================================================
-- 025b_rollback.sql
-- Rollback de 025b_codigo_receta_global.sql.
--
-- Qué hace:
--   1. Elimina siguiente_codigo_receta().
--   2. Restaura copiar_receta_a_org a la versión de 025 (sin siguiente_codigo_receta).
--      La versión restaurada tendrá el bug original de código duplicado, pero
--      permite volver al estado anterior a 025b mientras se decide otra solución.
--
-- Qué NO hace:
--   · No modifica recetas ya copiadas con el nuevo código.
--   · No toca la constraint recetas_codigo_receta_key.
--
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

-- 1. Eliminar siguiente_codigo_receta
drop function if exists public.siguiente_codigo_receta();

-- 2. Restaurar copiar_receta_a_org a versión 025
--    (copia r.codigo_receta del origen; sufrirá colisión si hay UNIQUE global,
--    pero refleja el estado de 025 antes de 025b)
create or replace function public.copiar_receta_a_org(
  p_receta_id   uuid,
  p_org_destino uuid
)
returns jsonb
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
  if not public.es_gerente_org(p_org_destino) then
    raise exception 'Solo el gerente de la organización destino puede copiar recetas.';
  end if;

  if not public._comparticion_activa_para_org(p_receta_id, p_org_destino) then
    raise exception 'La receta no está compartida con tu organización o la compartición no está activa.';
  end if;

  select slug into v_slug_destino
  from public.organizaciones where id = p_org_destino;

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

  -- Versión 025: copia codigo_receta del origen (puede colisionar si UNIQUE global)
  insert into public.recetas (
    organizacion_id, user_id,
    codigo_receta, nombre, categoria, tipo_plato,
    raciones_base, unidad_servicio, descripcion, elaboracion, observaciones,
    costes_indirectos_pct, margen_beneficio_pct, iva_pct,
    coste_total, precio_venta_sin_iva, precio_venta_con_iva,
    activa, copiada_de
  )
  select
    p_org_destino, auth.uid(),
    r.codigo_receta,   -- ← bug: puede colisionar con UNIQUE global
    v_nombre_receta, r.categoria, r.tipo_plato,
    r.raciones_base, r.unidad_servicio, r.descripcion, r.elaboracion, r.observaciones,
    0, 0, 0, 0, 0, 0,
    true, r.id
  from public.recetas r
  where r.id = p_receta_id
  returning id into v_nueva_receta_id;

  for v_ri in
    select ri.* from public.receta_ingredientes ri
    where ri.receta_id = p_receta_id order by ri.orden
  loop
    v_codigo_destino := v_ri.codigo_ingrediente;
    v_precio_unidad  := 0;

    if v_ri.codigo_ingrediente is not null then
      if exists (select 1 from public.inventario
                 where codigo = v_ri.codigo_ingrediente and organizacion_id is not null)
      then
        select codigo into v_codigo_destino
        from public.inventario
        where organizacion_id = p_org_destino
          and copiado_de_codigo = v_ri.codigo_ingrediente
        limit 1;

        if v_codigo_destino is null then
          v_prefix_dest := 'P-' || v_slug_destino || '-';
          perform pg_advisory_xact_lock(hashtext(p_org_destino::text));
          select coalesce(max(nullif(substring(codigo from '-(\d+)$'),'')::integer),0)+1
          into v_seq
          from public.inventario
          where organizacion_id = p_org_destino and codigo like (v_prefix_dest||'%');
          v_nuevo_codigo := v_prefix_dest || lpad(v_seq::text,4,'0');
          insert into public.inventario(codigo,familia,descripcion,unidad_medida,
            merma,organizacion_id,alergenos_revisados,copiado_de_codigo)
          select v_nuevo_codigo,i_orig.familia,i_orig.descripcion,i_orig.unidad_medida,
            i_orig.merma,p_org_destino,false,v_ri.codigo_ingrediente
          from public.inventario i_orig where i_orig.codigo=v_ri.codigo_ingrediente;
          insert into public.ingrediente_alergenos(codigo_ingrediente,alergeno_id)
          select v_nuevo_codigo,ia.alergeno_id from public.ingrediente_alergenos ia
          where ia.codigo_ingrediente=v_ri.codigo_ingrediente
          on conflict(codigo_ingrediente,alergeno_id) do nothing;
          v_codigo_destino := v_nuevo_codigo;
          v_privados_pendientes := v_privados_pendientes || jsonb_build_object(
            'codigo',v_nuevo_codigo,
            'descripcion',(select descripcion from public.inventario where codigo=v_ri.codigo_ingrediente),
            'codigo_origen',v_ri.codigo_ingrediente);
        end if;
        v_precio_unidad := 0;
      else
        select coalesce(io.precio_unidad,i.precio_unidad,0)
        into v_precio_unidad
        from public.inventario i
        left join public.inventario_org io
          on io.codigo_ingrediente=i.codigo and io.organizacion_id=p_org_destino
        where i.codigo=v_ri.codigo_ingrediente and i.organizacion_id is null limit 1;
        v_precio_unidad := coalesce(v_precio_unidad,0);
      end if;
    end if;

    v_coste_linea := v_ri.cantidad_bruta * v_precio_unidad;
    insert into public.receta_ingredientes(
      receta_id,codigo_ingrediente,descripcion_ingrediente,
      cantidad_bruta,unidad_medida,merma,cantidad_neta,
      precio_unidad,coste_total,orden,es_temporal)
    values(v_nueva_receta_id,v_codigo_destino,v_ri.descripcion_ingrediente,
      v_ri.cantidad_bruta,v_ri.unidad_medida,v_ri.merma,v_ri.cantidad_neta,
      v_precio_unidad,v_coste_linea,v_ri.orden,(v_codigo_destino is null));
  end loop;

  update public.recetas
     set coste_total=(select coalesce(sum(coste_total),0)
                      from public.receta_ingredientes where receta_id=v_nueva_receta_id)
   where id=v_nueva_receta_id;

  return jsonb_build_object('nueva_receta_id',v_nueva_receta_id,
                            'privados_pendientes',v_privados_pendientes);
end;
$$;

revoke execute on function public.copiar_receta_a_org(uuid, uuid) from public, anon;
grant  execute on function public.copiar_receta_a_org(uuid, uuid) to authenticated;

-- Verificación: siguiente_codigo_receta eliminada (0 filas)
select proname from pg_proc
where pronamespace = 'public'::regnamespace
  and proname = 'siguiente_codigo_receta';

commit;
