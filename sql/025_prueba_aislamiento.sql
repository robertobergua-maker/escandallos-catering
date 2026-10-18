-- =============================================================================
-- 025_prueba_aislamiento.sql
-- Prueba de aislamiento de la Fase 4 (compartir recetas).
--
-- INSTRUCCIONES:
--   1. Sustituir los placeholders <uid_...> por los UUID reales de los usuarios:
--        <uid_gerente_samirarte>   gerente de org Samirarte
--        <uid_chef_samirarte>      chef   de org Samirarte
--        <uid_gerente_pruebas>     gerente de org Pruebas
--        <uid_chef_pruebas>        chef   de org Pruebas
--   2. Ejecutar en el SQL Editor de Supabase como postgres (superusuario).
--   3. El script termina con ROLLBACK: no deja rastro en la BD.
--   4. Revisar la tabla r al final: todas las filas deben tener ok = true.
--
-- UUIDs de organizaciones (valores reales, NO sustituir):
--   Samirarte : 4bdf1328-958e-4b0b-97de-38ba157a5e2e
--   Pruebas   : 367d4642-16bc-4817-9565-a6b914d96aa9
--
-- Requisitos: sql/025_fase4_compartir_recetas.sql ya aplicado.
-- =============================================================================

begin;

-- ── Tabla de resultados ───────────────────────────────────────────────────────
create temp table r (
  prueba             text    not null,
  resultado_esperado text    not null,
  obtenido           text,
  ok                 boolean
) on commit drop;

-- ── Constantes ────────────────────────────────────────────────────────────────
\set org_samirarte '4bdf1328-958e-4b0b-97de-38ba157a5e2e'
\set org_pruebas   '367d4642-16bc-4817-9565-a6b914d96aa9'


-- =============================================================================
-- PREPARACIÓN: crear datos de prueba propios
-- Creamos dentro de esta transacción todo lo necesario para no depender de
-- datos existentes.  El ROLLBACK final borra todo.
-- =============================================================================

-- ── Ingrediente global de prueba (organizacion_id NULL) ───────────────────────
insert into public.inventario (
  codigo, familia, descripcion, unidad_medida,
  precio_unidad, organizacion_id, alergenos_revisados
) values (
  'TEST-GLOBAL-001', 'Lácteos', 'Leche entera TEST', 'L',
  1.50,   -- precio catálogo global
  null,   -- global
  true
) on conflict (codigo) do nothing;

-- Precio propio de Pruebas para ese global (2.00 €/L)
insert into public.inventario_org (
  organizacion_id, codigo_ingrediente, precio_unidad
) values (
  '367d4642-16bc-4817-9565-a6b914d96aa9',
  'TEST-GLOBAL-001',
  2.00
) on conflict (organizacion_id, codigo_ingrediente) do nothing;

-- ── Ingrediente privado de Samirarte con 1 alérgeno ──────────────────────────
insert into public.inventario (
  codigo, familia, descripcion, unidad_medida,
  precio_unidad, organizacion_id, alergenos_revisados
) values (
  'P-samirarte-TEST1', 'Especias', 'Mezcla especial TEST (privado Samirarte)', 'kg',
  5.00,
  '4bdf1328-958e-4b0b-97de-38ba157a5e2e',
  true
) on conflict (codigo) do nothing;

-- Alérgeno: gluten (id puede variar; buscamos por nombre)
insert into public.ingrediente_alergenos (codigo_ingrediente, alergeno_id)
select 'P-samirarte-TEST1', id
from public.alergenos
where lower(nombre) like '%gluten%'
  and activo = true
limit 1
on conflict (codigo_ingrediente, alergeno_id) do nothing;

-- ── Receta de Samirarte con 1 ingrediente global + 1 privado ─────────────────
insert into public.recetas (
  id, organizacion_id, user_id,
  codigo_receta, nombre, categoria, tipo_plato,
  raciones_base, unidad_servicio,
  costes_indirectos_pct, margen_beneficio_pct, iva_pct,
  coste_total, precio_venta_sin_iva, precio_venta_con_iva, activa
) values (
  'aaaaaaaa-0000-0000-0000-000000000025',
  '4bdf1328-958e-4b0b-97de-38ba157a5e2e',
  (select id from auth.users where email like '%samira%' limit 1),
  'TEST-REC-025', 'Receta TEST Fase4', 'Postres', 'postre',
  4, 'ración',
  10, 30, 10,
  99, 99, 99, true   -- valores de origen (NUNCA deben copiarse)
) on conflict (id) do nothing;

-- Línea 1: global (1 L de leche)
insert into public.receta_ingredientes (
  receta_id, codigo_ingrediente, descripcion_ingrediente,
  cantidad_bruta, unidad_medida, merma, cantidad_neta,
  precio_unidad, coste_total, orden, es_temporal
) values (
  'aaaaaaaa-0000-0000-0000-000000000025',
  'TEST-GLOBAL-001', 'Leche entera TEST',
  1.0, 'L', 0, 1.0,
  1.50, 1.50, 1, false   -- precio de origen (NUNCA debe copiarse)
) on conflict do nothing;

-- Línea 2: privado (0.1 kg de mezcla especial)
insert into public.receta_ingredientes (
  receta_id, codigo_ingrediente, descripcion_ingrediente,
  cantidad_bruta, unidad_medida, merma, cantidad_neta,
  precio_unidad, coste_total, orden, es_temporal
) values (
  'aaaaaaaa-0000-0000-0000-000000000025',
  'P-samirarte-TEST1', 'Mezcla especial TEST',
  0.1, 'kg', 10, 0.09,
  5.00, 0.50, 2, false   -- precio de origen (NUNCA debe copiarse)
) on conflict do nothing;

-- ── Compartición activa: Samirarte → Pruebas (específica) ─────────────────────
-- La insertamos como postgres (superusuario) para no depender de la sesión JWT.
insert into public.comparticiones (
  origen_organizacion_id, tipo, objeto_id,
  destino, destino_organizacion_id,
  activa, created_by
) values (
  '4bdf1328-958e-4b0b-97de-38ba157a5e2e',
  'receta',
  'aaaaaaaa-0000-0000-0000-000000000025',
  'especifica',
  '367d4642-16bc-4817-9565-a6b914d96aa9',
  true,
  (select id from auth.users where email like '%samira%' limit 1)
) on conflict do nothing;


-- =============================================================================
-- PRUEBA 1: gerente Samirarte ve su compartición en comparticiones_select
-- =============================================================================
do $$
declare v_count integer;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"<uid_gerente_samirarte>","role":"authenticated"}', true);

  select count(*) into v_count
  from public.comparticiones
  where objeto_id = 'aaaaaaaa-0000-0000-0000-000000000025';

  insert into r values (
    'P1 gerente_samirarte ve su compartición',
    '1',
    v_count::text,
    v_count >= 1
  );
end $$;

-- =============================================================================
-- PRUEBA 2: chef Samirarte NO ve comparticiones de Samirarte (no es gerente)
-- =============================================================================
do $$
declare v_count integer;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"<uid_chef_samirarte>","role":"authenticated"}', true);

  select count(*) into v_count
  from public.comparticiones
  where objeto_id = 'aaaaaaaa-0000-0000-0000-000000000025';

  insert into r values (
    'P2 chef_samirarte NO ve comparticiones (no gerente)',
    '0',
    v_count::text,
    v_count = 0
  );
end $$;

-- =============================================================================
-- PRUEBA 3: gerente Pruebas lista recetas compartidas con su org (≥ 1)
-- =============================================================================
do $$
declare v_count integer;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"<uid_gerente_pruebas>","role":"authenticated"}', true);

  select count(*) into v_count
  from public.listar_recetas_compartidas_conmigo(
    '367d4642-16bc-4817-9565-a6b914d96aa9'
  );

  insert into r values (
    'P3 gerente_pruebas lista recetas compartidas con Pruebas',
    '>=1',
    v_count::text,
    v_count >= 1
  );
end $$;

-- =============================================================================
-- PRUEBA 4: chef Pruebas NO puede copiar (solo gerentes)
-- =============================================================================
do $$
declare v_err text := 'no lanzó excepción';
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"<uid_chef_pruebas>","role":"authenticated"}', true);

  begin
    perform public.copiar_receta_a_org(
      'aaaaaaaa-0000-0000-0000-000000000025',
      '367d4642-16bc-4817-9565-a6b914d96aa9'
    );
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values (
    'P4 chef_pruebas NO puede copiar',
    'excepción Solo el gerente',
    v_err,
    v_err ilike '%Solo el gerente%'
  );
end $$;

-- =============================================================================
-- PRUEBA 5: gerente Pruebas SÍ puede copiar; obtiene nueva_receta_id
-- =============================================================================
do $$
declare
  v_res         jsonb;
  v_nueva_id    text;
  v_ok          boolean;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"<uid_gerente_pruebas>","role":"authenticated"}', true);

  v_res := public.copiar_receta_a_org(
    'aaaaaaaa-0000-0000-0000-000000000025',
    '367d4642-16bc-4817-9565-a6b914d96aa9'
  );
  v_nueva_id := v_res->>'nueva_receta_id';

  -- Verificar que la receta copiada existe en Pruebas y tiene copiada_de correcto
  select (
    exists (
      select 1 from public.recetas
      where id               = v_nueva_id::uuid
        and organizacion_id  = '367d4642-16bc-4817-9565-a6b914d96aa9'
        and copiada_de       = 'aaaaaaaa-0000-0000-0000-000000000025'
    )
  ) into v_ok;

  -- Guardar id para pruebas posteriores
  perform set_config('app.nueva_receta_id', v_nueva_id, true);

  insert into r values (
    'P5 gerente_pruebas copia receta; receta existe en Pruebas',
    'true',
    v_ok::text,
    v_ok
  );
end $$;

-- =============================================================================
-- PRUEBA 6: la copia tiene precios del DESTINO (no los del origen)
--   · Ingrediente global TEST-GLOBAL-001:
--       Pruebas tiene precio propio 2.00 → debe usarse ese (no 1.50 del origen)
--       coste_linea = 1.0 * 2.00 = 2.00
--   · Ingrediente privado copiado: precio 0 (no tiene precio en destino todavía)
--       coste_linea = 0.1 * 0 = 0.00
--   · coste_total_receta = 2.00 + 0.00 = 2.00
--   (si Pruebas no tuviese precio propio del global → usaría cat. global 1.50)
-- =============================================================================
do $$
declare
  v_nueva_id   text;
  v_coste_rec  numeric;
  v_precio_lin numeric;
  v_ok         boolean;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"<uid_gerente_pruebas>","role":"authenticated"}', true);

  v_nueva_id := current_setting('app.nueva_receta_id', true);

  -- Precio de la línea global en la receta copiada (debe ser 2.00, no 1.50)
  select precio_unidad into v_precio_lin
  from public.receta_ingredientes
  where receta_id          = v_nueva_id::uuid
    and codigo_ingrediente = 'TEST-GLOBAL-001';

  -- coste_total de la receta copiada (debe ser 2.00)
  select coste_total into v_coste_rec
  from public.recetas
  where id = v_nueva_id::uuid;

  v_ok := (v_precio_lin = 2.00) and (v_coste_rec = 2.00);

  insert into r values (
    'P6 copia usa precio_destino (2.00); coste_total=2.00; nunca precio_origen (1.50)',
    'precio_linea=2.00 coste_total=2.00',
    'precio_linea=' || coalesce(v_precio_lin::text,'null')
      || ' coste_total=' || coalesce(v_coste_rec::text,'null'),
    v_ok
  );
end $$;

-- =============================================================================
-- PRUEBA 7: privado copiado tiene alergenos_revisados = false
--           y los mismos alérgenos que el privado origen
-- =============================================================================
do $$
declare
  v_nueva_id      text;
  v_codigo_priv   text;
  v_revisado      boolean;
  v_alergenos_ok  boolean;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"<uid_gerente_pruebas>","role":"authenticated"}', true);

  v_nueva_id := current_setting('app.nueva_receta_id', true);

  -- Obtener el código del privado copiado en la receta nueva
  select ri.codigo_ingrediente into v_codigo_priv
  from public.receta_ingredientes ri
  join public.inventario i on i.codigo = ri.codigo_ingrediente
  where ri.receta_id      = v_nueva_id::uuid
    and i.organizacion_id = '367d4642-16bc-4817-9565-a6b914d96aa9';

  -- alergenos_revisados = false
  select alergenos_revisados into v_revisado
  from public.inventario
  where codigo = v_codigo_priv;

  -- Los alérgenos del privado copiado coinciden con los del origen
  select (
    not exists (
      -- alérgenos en origen que NO están en copia
      select alergeno_id from public.ingrediente_alergenos
      where codigo_ingrediente = 'P-samirarte-TEST1'
      except
      select alergeno_id from public.ingrediente_alergenos
      where codigo_ingrediente = v_codigo_priv
    )
  ) into v_alergenos_ok;

  insert into r values (
    'P7 privado copiado: alergenos_revisados=false y alérgenos copiados',
    'revisado=false alérgenos_ok=true',
    'revisado=' || coalesce(v_revisado::text,'null')
      || ' alergenos_ok=' || coalesce(v_alergenos_ok::text,'null'),
    (v_revisado = false) and v_alergenos_ok
  );
end $$;

-- =============================================================================
-- PRUEBA 8: ver_receta_compartida NO devuelve precio_unidad ni coste_total
-- =============================================================================
do $$
declare
  v_ings        jsonb;
  v_tiene_prec  boolean;
  v_tiene_cost  boolean;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"<uid_gerente_pruebas>","role":"authenticated"}', true);

  select ingredientes into v_ings
  from public.ver_receta_compartida(
    'aaaaaaaa-0000-0000-0000-000000000025',
    '367d4642-16bc-4817-9565-a6b914d96aa9'
  );

  v_tiene_prec := v_ings::text ilike '%precio_unidad%';
  v_tiene_cost := v_ings::text ilike '%coste_total%';

  insert into r values (
    'P8 ver_receta_compartida NO incluye precio_unidad ni coste_total',
    'precio=false coste=false',
    'precio=' || v_tiene_prec::text || ' coste=' || v_tiene_cost::text,
    (not v_tiene_prec) and (not v_tiene_cost)
  );
end $$;

-- =============================================================================
-- PRUEBA 9: segundo intento de copiar la misma receta reutiliza el privado
--           (no crea un duplicado de P-samirarte-TEST1 en Pruebas)
-- =============================================================================
do $$
declare
  v_count_priv integer;
  v_res        jsonb;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"<uid_gerente_pruebas>","role":"authenticated"}', true);

  -- Copiar de nuevo (el nombre tendrá sufijo " (copia)" por colisión)
  v_res := public.copiar_receta_a_org(
    'aaaaaaaa-0000-0000-0000-000000000025',
    '367d4642-16bc-4817-9565-a6b914d96aa9'
  );

  -- Solo debe haber 1 ingrediente privado copiado de P-samirarte-TEST1 en Pruebas
  select count(*) into v_count_priv
  from public.inventario
  where organizacion_id   = '367d4642-16bc-4817-9565-a6b914d96aa9'
    and copiado_de_codigo = 'P-samirarte-TEST1';

  insert into r values (
    'P9 segundo copiar reutiliza privado (sin duplicar)',
    '1',
    v_count_priv::text,
    v_count_priv = 1
  );
end $$;

-- =============================================================================
-- PRUEBA 10: compartición desactivada → copiar_receta_a_org lanza excepción
-- =============================================================================
do $$
declare v_err text := 'no lanzó excepción';
begin
  -- Desactivar como postgres (superusuario, fuera de RLS)
  update public.comparticiones
  set activa = false
  where objeto_id              = 'aaaaaaaa-0000-0000-0000-000000000025'
    and destino_organizacion_id = '367d4642-16bc-4817-9565-a6b914d96aa9';

  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"<uid_gerente_pruebas>","role":"authenticated"}', true);

  begin
    perform public.copiar_receta_a_org(
      'aaaaaaaa-0000-0000-0000-000000000025',
      '367d4642-16bc-4817-9565-a6b914d96aa9'
    );
  exception when others then
    v_err := sqlerrm;
  end;

  -- Reactivar para pruebas posteriores
  reset role;
  update public.comparticiones
  set activa = true
  where objeto_id              = 'aaaaaaaa-0000-0000-0000-000000000025'
    and destino_organizacion_id = '367d4642-16bc-4817-9565-a6b914d96aa9';

  insert into r values (
    'P10 compartición desactivada → copiar falla',
    'excepción no está compartida',
    v_err,
    v_err ilike '%no está compartida%' or v_err ilike '%no está activa%'
  );
end $$;

-- =============================================================================
-- PRUEBA 11: anon NO puede ejecutar ninguna función pública de Fase 4
-- =============================================================================
do $$
declare
  v_err1 text := 'no lanzó excepción';
  v_err2 text := 'no lanzó excepción';
  v_err3 text := 'no lanzó excepción';
begin
  set local role anon;

  begin
    perform public.listar_organizaciones_destino();
  exception when others then v_err1 := sqlerrm; end;

  begin
    perform public.listar_recetas_compartidas_conmigo(
      '367d4642-16bc-4817-9565-a6b914d96aa9'
    );
  exception when others then v_err2 := sqlerrm; end;

  begin
    perform public.copiar_receta_a_org(
      'aaaaaaaa-0000-0000-0000-000000000025',
      '367d4642-16bc-4817-9565-a6b914d96aa9'
    );
  exception when others then v_err3 := sqlerrm; end;

  insert into r values (
    'P11 anon NO puede ejecutar funciones Fase 4',
    'todas lanzan excepción',
    'listar_destino=' || (v_err1 <> 'no lanzó excepción')::text
      || ' listar_conmigo=' || (v_err2 <> 'no lanzó excepción')::text
      || ' copiar=' || (v_err3 <> 'no lanzó excepción')::text,
    (v_err1 <> 'no lanzó excepción')
    and (v_err2 <> 'no lanzó excepción')
    and (v_err3 <> 'no lanzó excepción')
  );
end $$;

-- =============================================================================
-- PRUEBA 12: UPDATE que cambia objeto_id a una receta ajena falla (RLS WITH CHECK)
-- =============================================================================
do $$
declare v_err text := 'no lanzó excepción';
begin
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"<uid_gerente_samirarte>","role":"authenticated"}', true);

  begin
    update public.comparticiones
    set objeto_id = gen_random_uuid()   -- UUID inexistente → no es receta de Samirarte
    where objeto_id              = 'aaaaaaaa-0000-0000-0000-000000000025'
      and origen_organizacion_id = '4bdf1328-958e-4b0b-97de-38ba157a5e2e';
  exception when others then
    v_err := sqlerrm;
  end;

  -- Si no lanzó excepción, verificar que el update no afectó filas
  -- (new check no pasó → 0 filas afectadas es igualmente correcto en Postgres)
  if v_err = 'no lanzó excepción' then
    -- Comprobar que el objeto_id sigue siendo el original
    if exists (
      select 1 from public.comparticiones
      where objeto_id = 'aaaaaaaa-0000-0000-0000-000000000025'
    ) then
      v_err := 'update no afectó filas (correcto)';
    else
      v_err := 'update cambió objeto_id (ERROR: RLS falló)';
    end if;
  end if;

  insert into r values (
    'P12 UPDATE que cambia objeto_id a receta ajena falla o afecta 0 filas',
    'excepción o 0 filas',
    v_err,
    v_err not ilike '%update cambió objeto_id%'
  );
end $$;

-- =============================================================================
-- PRUEBA 13: segundo INSERT 'todas' de la misma receta falla (NULLS NOT DISTINCT)
-- =============================================================================
do $$
declare v_err text := 'no lanzó excepción';
begin
  -- Insertar primera compartición 'todas' como postgres
  reset role;
  insert into public.comparticiones (
    origen_organizacion_id, tipo, objeto_id,
    destino, destino_organizacion_id, activa, created_by
  ) values (
    '4bdf1328-958e-4b0b-97de-38ba157a5e2e',
    'receta',
    'aaaaaaaa-0000-0000-0000-000000000025',
    'todas', null, true,
    (select id from auth.users where email like '%samira%' limit 1)
  );

  -- Segundo INSERT idéntico debe fallar por UNIQUE NULLS NOT DISTINCT
  begin
    insert into public.comparticiones (
      origen_organizacion_id, tipo, objeto_id,
      destino, destino_organizacion_id, activa, created_by
    ) values (
      '4bdf1328-958e-4b0b-97de-38ba157a5e2e',
      'receta',
      'aaaaaaaa-0000-0000-0000-000000000025',
      'todas', null, true,
      (select id from auth.users where email like '%samira%' limit 1)
    );
  exception when unique_violation then
    v_err := 'unique_violation';
  end;

  insert into r values (
    'P13 segundo compartir todas de la misma receta falla (NULLS NOT DISTINCT)',
    'unique_violation',
    v_err,
    v_err = 'unique_violation'
  );
end $$;


-- =============================================================================
-- RESULTADO FINAL
-- =============================================================================

select
  prueba,
  resultado_esperado,
  obtenido,
  ok,
  case when ok then '✅' else '❌ FALLO' end as estado
from r
order by prueba;

-- La transacción se revierte: ningún dato de prueba queda en la BD.
rollback;
