-- =============================================================================
-- 025_prueba_aislamiento.sql
-- Prueba de aislamiento de la Fase 4 (compartir recetas entre organizaciones).
--
-- CÓMO EJECUTAR:
--   Pegar TODO el script en el SQL Editor de Supabase y ejecutarlo de una vez.
--   Ejecutar como postgres (superusuario). No hay nada que sustituir.
--   El script termina con ROLLBACK: no deja rastro en la BD.
--   Revisar la última tabla: todas las filas deben tener ok = true.
--
-- Requisito: sql/025_fase4_compartir_recetas.sql ya aplicado.
--
-- UUIDs de organizaciones (hardcoded):
--   Samirarte : 4bdf1328-958e-4b0b-97de-38ba157a5e2e
--   Pruebas   : 367d4642-16bc-4817-9565-a6b914d96aa9
-- =============================================================================

begin;

-- =============================================================================
-- TABLAS DE TRABAJO (on commit drop → desaparecen con el rollback final)
-- =============================================================================

-- r: tabla de resultados de pruebas
create temp table r (
  prueba             text    not null,
  resultado_esperado text    not null,
  obtenido           text,
  ok                 boolean
) on commit drop;

-- u: usuarios de prueba tomados de auth.users
-- Usamos los 4 primeros usuarios existentes para no depender de emails concretos.
create temp table u (
  clave text primary key,
  id    uuid not null
) on commit drop;

insert into u (clave, id)
select clave, id from (
  select
    case row_number() over (order by created_at)
      when 1 then 'gerente_samirarte'
      when 2 then 'chef_samirarte'
      when 3 then 'gerente_pruebas'
      when 4 then 'chef_pruebas'
    end                              as clave,
    id
  from auth.users
  order by created_at
  limit 4
) sub
where clave is not null;

-- Grant para que los bloques DO puedan leer/escribir aunque cambien de rol
grant all on r, u to authenticated, anon;

-- =============================================================================
-- PREPARAR MEMBRESÍAS DE PRUEBA
-- Insertamos (o actualizamos) en organizacion_miembros los 4 roles necesarios.
-- El ROLLBACK final lo deshace todo.
-- =============================================================================

-- gerente_samirarte → gerente de Samirarte
insert into public.organizacion_miembros (organizacion_id, user_id, rol, activo)
values (
  '4bdf1328-958e-4b0b-97de-38ba157a5e2e',
  (select id from u where clave = 'gerente_samirarte'),
  'gerente', true
)
on conflict (organizacion_id, user_id)
  do update set rol = 'gerente', activo = true;

-- chef_samirarte → chef de Samirarte
insert into public.organizacion_miembros (organizacion_id, user_id, rol, activo)
values (
  '4bdf1328-958e-4b0b-97de-38ba157a5e2e',
  (select id from u where clave = 'chef_samirarte'),
  'chef', true
)
on conflict (organizacion_id, user_id)
  do update set rol = 'chef', activo = true;

-- gerente_pruebas → gerente de Pruebas
insert into public.organizacion_miembros (organizacion_id, user_id, rol, activo)
values (
  '367d4642-16bc-4817-9565-a6b914d96aa9',
  (select id from u where clave = 'gerente_pruebas'),
  'gerente', true
)
on conflict (organizacion_id, user_id)
  do update set rol = 'gerente', activo = true;

-- chef_pruebas → chef de Pruebas
insert into public.organizacion_miembros (organizacion_id, user_id, rol, activo)
values (
  '367d4642-16bc-4817-9565-a6b914d96aa9',
  (select id from u where clave = 'chef_pruebas'),
  'chef', true
)
on conflict (organizacion_id, user_id)
  do update set rol = 'chef', activo = true;

-- =============================================================================
-- PREPARAR DATOS DE RECETA (todo dentro de la transacción)
-- =============================================================================

-- Ingrediente global de prueba (organizacion_id NULL)
insert into public.inventario (
  codigo, familia, descripcion, unidad_medida,
  precio_unidad, organizacion_id, alergenos_revisados
) values (
  'TEST025-GLOBAL-001', 'Lácteos', 'Leche entera TEST025', 'L',
  1.50,   -- precio catálogo global (no debe copiarse a la receta destino)
  null,
  true
) on conflict (codigo) do nothing;

-- Precio propio de Pruebas para ese global (2.00 €/L)
-- La receta copiada debe usar 2.00, no 1.50
insert into public.inventario_org (
  organizacion_id, codigo_ingrediente, precio_unidad
) values (
  '367d4642-16bc-4817-9565-a6b914d96aa9',
  'TEST025-GLOBAL-001',
  2.00
) on conflict (organizacion_id, codigo_ingrediente)
  do update set precio_unidad = 2.00;

-- Ingrediente privado de Samirarte con 1 alérgeno
insert into public.inventario (
  codigo, familia, descripcion, unidad_medida,
  precio_unidad, organizacion_id, alergenos_revisados
) values (
  'P-samirarte-TEST025', 'Especias', 'Mezcla especial TEST025 (privado Samirarte)', 'kg',
  5.00,
  '4bdf1328-958e-4b0b-97de-38ba157a5e2e',
  true
) on conflict (codigo) do nothing;

-- Alérgeno gluten al privado de Samirarte
insert into public.ingrediente_alergenos (codigo_ingrediente, alergeno_id)
select 'P-samirarte-TEST025', id
from public.alergenos
where lower(nombre) like '%gluten%' and activo = true
limit 1
on conflict (codigo_ingrediente, alergeno_id) do nothing;

-- Receta de Samirarte: 1 ingrediente global + 1 privado
-- coste_total, precio_venta_* puestos a 99 para verificar que no se copian
insert into public.recetas (
  id, organizacion_id, user_id,
  codigo_receta, nombre, categoria, tipo_plato,
  raciones_base, unidad_servicio,
  costes_indirectos_pct, margen_beneficio_pct, iva_pct,
  coste_total, precio_venta_sin_iva, precio_venta_con_iva, activa
) values (
  'aaaaaaaa-0025-0025-0025-000000000025',
  '4bdf1328-958e-4b0b-97de-38ba157a5e2e',
  (select id from u where clave = 'gerente_samirarte'),
  'TEST-REC-025', 'Receta TEST Fase4', 'Postres', 'postre',
  4, 'ración',
  10, 30, 10,
  99, 99, 99, true
) on conflict (id) do nothing;

-- Línea 1: global (1 L, merma 0)  → coste destino = 1.0 * 2.00 = 2.00
insert into public.receta_ingredientes (
  receta_id, codigo_ingrediente, descripcion_ingrediente,
  cantidad_bruta, unidad_medida, merma, cantidad_neta,
  precio_unidad, coste_total, orden, es_temporal
) values (
  'aaaaaaaa-0025-0025-0025-000000000025',
  'TEST025-GLOBAL-001', 'Leche entera TEST025',
  1.0, 'L', 0, 1.0,
  1.50, 1.50,   -- precio origen: NUNCA debe copiarse
  1, false
) on conflict do nothing;

-- Línea 2: privado (0.1 kg, merma 10%)  → coste destino = 0.1 * 0 = 0.00
insert into public.receta_ingredientes (
  receta_id, codigo_ingrediente, descripcion_ingrediente,
  cantidad_bruta, unidad_medida, merma, cantidad_neta,
  precio_unidad, coste_total, orden, es_temporal
) values (
  'aaaaaaaa-0025-0025-0025-000000000025',
  'P-samirarte-TEST025', 'Mezcla especial TEST025',
  0.1, 'kg', 10, 0.09,
  5.00, 0.50,   -- precio origen: NUNCA debe copiarse
  2, false
) on conflict do nothing;

-- Compartición activa: Samirarte → Pruebas (específica)
insert into public.comparticiones (
  origen_organizacion_id, tipo, objeto_id,
  destino, destino_organizacion_id, activa, created_by
) values (
  '4bdf1328-958e-4b0b-97de-38ba157a5e2e',
  'receta',
  'aaaaaaaa-0025-0025-0025-000000000025',
  'especifica',
  '367d4642-16bc-4817-9565-a6b914d96aa9',
  true,
  (select id from u where clave = 'gerente_samirarte')
) on conflict do nothing;


-- =============================================================================
-- P1: gerente Samirarte ve su compartición (SELECT con RLS gerente)
-- =============================================================================
do $$
declare
  v_uid   uuid;
  v_count integer;
begin
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  select count(*) into v_count
  from public.comparticiones
  where objeto_id = 'aaaaaaaa-0025-0025-0025-000000000025';

  insert into r values (
    'P01 gerente_samirarte ve su compartición',
    '>=1', v_count::text, v_count >= 1
  );
end $$;

reset role;

-- =============================================================================
-- P2: chef Samirarte NO ve comparticiones de Samirarte (no es gerente)
-- =============================================================================
do $$
declare
  v_uid   uuid;
  v_count integer;
begin
  select id into v_uid from u where clave = 'chef_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  select count(*) into v_count
  from public.comparticiones
  where objeto_id = 'aaaaaaaa-0025-0025-0025-000000000025';

  insert into r values (
    'P02 chef_samirarte NO ve comparticiones (no gerente)',
    '0', v_count::text, v_count = 0
  );
end $$;

reset role;

-- =============================================================================
-- P3: gerente Pruebas lista recetas compartidas con su org (>= 1 fila)
-- =============================================================================
do $$
declare
  v_uid   uuid;
  v_count integer;
begin
  select id into v_uid from u where clave = 'gerente_pruebas';
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  select count(*) into v_count
  from public.listar_recetas_compartidas_conmigo(
    '367d4642-16bc-4817-9565-a6b914d96aa9'
  );

  insert into r values (
    'P03 gerente_pruebas lista recetas compartidas con Pruebas',
    '>=1', v_count::text, v_count >= 1
  );
end $$;

reset role;

-- =============================================================================
-- P4: chef Pruebas NO puede copiar (solo gerentes)
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
begin
  select id into v_uid from u where clave = 'chef_pruebas';
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    perform public.copiar_receta_a_org(
      'aaaaaaaa-0025-0025-0025-000000000025',
      '367d4642-16bc-4817-9565-a6b914d96aa9'
    );
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values (
    'P04 chef_pruebas NO puede copiar',
    'exc: Solo el gerente',
    v_err,
    v_err ilike '%Solo el gerente%'
  );
end $$;

reset role;

-- =============================================================================
-- P5: gerente Pruebas SÍ puede copiar; receta copiada existe en Pruebas
-- =============================================================================
do $$
declare
  v_uid      uuid;
  v_res      jsonb;
  v_nueva_id text;
  v_ok       boolean;
begin
  select id into v_uid from u where clave = 'gerente_pruebas';
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  v_res := public.copiar_receta_a_org(
    'aaaaaaaa-0025-0025-0025-000000000025',
    '367d4642-16bc-4817-9565-a6b914d96aa9'
  );
  v_nueva_id := v_res->>'nueva_receta_id';

  select exists (
    select 1 from public.recetas
    where id              = v_nueva_id::uuid
      and organizacion_id = '367d4642-16bc-4817-9565-a6b914d96aa9'
      and copiada_de      = 'aaaaaaaa-0025-0025-0025-000000000025'
  ) into v_ok;

  -- Guardar para pruebas posteriores
  perform set_config('test.nueva_receta_id', v_nueva_id, true);

  insert into r values (
    'P05 gerente_pruebas copia; receta existe en Pruebas con copiada_de',
    'true', v_ok::text, v_ok
  );
end $$;

reset role;

-- =============================================================================
-- P6: la copia usa precios del DESTINO, no del origen
--   · Global TEST025-GLOBAL-001: Pruebas tiene precio propio 2.00
--     → precio_unidad en línea = 2.00 (no 1.50 del origen)
--   · Privado copiado: precio 0 (sin precio en destino todavía)
--   · coste_total receta = 1.0*2.00 + 0.1*0 = 2.00
-- =============================================================================
do $$
declare
  v_uid        uuid;
  v_nueva_id   text;
  v_precio_lin numeric;
  v_coste_rec  numeric;
  v_ok         boolean;
begin
  select id into v_uid from u where clave = 'gerente_pruebas';
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  v_nueva_id := current_setting('test.nueva_receta_id', true);

  select precio_unidad into v_precio_lin
  from public.receta_ingredientes
  where receta_id          = v_nueva_id::uuid
    and codigo_ingrediente = 'TEST025-GLOBAL-001';

  select coste_total into v_coste_rec
  from public.recetas
  where id = v_nueva_id::uuid;

  v_ok := (v_precio_lin = 2.00) and (v_coste_rec = 2.00);

  insert into r values (
    'P06 precios copia = destino (2.00); nunca origen (1.50); coste_total=2.00',
    'precio_lin=2.00 coste=2.00',
    'precio_lin=' || coalesce(v_precio_lin::text, 'null')
      || ' coste=' || coalesce(v_coste_rec::text, 'null'),
    v_ok
  );
end $$;

reset role;

-- =============================================================================
-- P7: privado copiado tiene alergenos_revisados=false y mismos alérgenos
-- =============================================================================
do $$
declare
  v_uid          uuid;
  v_nueva_id     text;
  v_codigo_priv  text;
  v_revisado     boolean;
  v_alergs_ok    boolean;
begin
  select id into v_uid from u where clave = 'gerente_pruebas';
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  v_nueva_id := current_setting('test.nueva_receta_id', true);

  -- Código del privado copiado en la receta nueva (el de la org Pruebas)
  select ri.codigo_ingrediente into v_codigo_priv
  from public.receta_ingredientes ri
  join public.inventario i on i.codigo = ri.codigo_ingrediente
  where ri.receta_id      = v_nueva_id::uuid
    and i.organizacion_id = '367d4642-16bc-4817-9565-a6b914d96aa9';

  select alergenos_revisados into v_revisado
  from public.inventario
  where codigo = v_codigo_priv;

  -- Todos los alérgenos del origen deben estar en la copia
  select not exists (
    select alergeno_id from public.ingrediente_alergenos
    where codigo_ingrediente = 'P-samirarte-TEST025'
    except
    select alergeno_id from public.ingrediente_alergenos
    where codigo_ingrediente = v_codigo_priv
  ) into v_alergs_ok;

  insert into r values (
    'P07 privado copiado: alergenos_revisados=false y alérgenos copiados',
    'revisado=false alergs=true',
    'revisado=' || coalesce(v_revisado::text, 'null')
      || ' alergs=' || coalesce(v_alergs_ok::text, 'null'),
    (v_revisado = false) and v_alergs_ok
  );
end $$;

reset role;

-- =============================================================================
-- P8: ver_receta_compartida NO devuelve precio_unidad ni coste_total
-- =============================================================================
do $$
declare
  v_uid        uuid;
  v_ings       jsonb;
  v_tiene_prec boolean;
  v_tiene_cost boolean;
begin
  select id into v_uid from u where clave = 'gerente_pruebas';
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  select ingredientes into v_ings
  from public.ver_receta_compartida(
    'aaaaaaaa-0025-0025-0025-000000000025',
    '367d4642-16bc-4817-9565-a6b914d96aa9'
  );

  v_tiene_prec := v_ings::text ilike '%precio_unidad%';
  v_tiene_cost := v_ings::text ilike '%coste_total%';

  insert into r values (
    'P08 ver_receta_compartida excluye precio_unidad y coste_total',
    'precio=false coste=false',
    'precio=' || v_tiene_prec::text || ' coste=' || v_tiene_cost::text,
    (not v_tiene_prec) and (not v_tiene_cost)
  );
end $$;

reset role;

-- =============================================================================
-- P9: llamar copiar_receta_a_org DOS VECES en la misma transacción
--     · Debe funcionar (sin error "already exists" de tabla temporal)
--     · El privado P-samirarte-TEST025 debe copiarse solo 1 vez en Pruebas
-- =============================================================================
do $$
declare
  v_uid        uuid;
  v_res2       jsonb;
  v_count_priv integer;
  v_ok         boolean;
begin
  select id into v_uid from u where clave = 'gerente_pruebas';
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  -- Segunda copia (la primera se hizo en P5; el nombre ya existe → añade sufijo)
  v_res2 := public.copiar_receta_a_org(
    'aaaaaaaa-0025-0025-0025-000000000025',
    '367d4642-16bc-4817-9565-a6b914d96aa9'
  );

  -- Solo 1 ingrediente privado copiado de P-samirarte-TEST025 en Pruebas
  select count(*) into v_count_priv
  from public.inventario
  where organizacion_id   = '367d4642-16bc-4817-9565-a6b914d96aa9'
    and copiado_de_codigo = 'P-samirarte-TEST025';

  v_ok := (v_res2->>'nueva_receta_id' is not null) and (v_count_priv = 1);

  insert into r values (
    'P09 doble copia OK; privado reutilizado (no duplicado)',
    'nueva_id ok; privados=1',
    'nueva_id=' || (v_res2->>'nueva_receta_id' is not null)::text
      || ' privados_en_destino=' || v_count_priv::text,
    v_ok
  );
end $$;

reset role;

-- =============================================================================
-- P10: compartición desactivada → copiar_receta_a_org lanza excepción
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
begin
  -- Desactivar como postgres
  update public.comparticiones
     set activa = false
   where objeto_id               = 'aaaaaaaa-0025-0025-0025-000000000025'
     and destino_organizacion_id = '367d4642-16bc-4817-9565-a6b914d96aa9';

  select id into v_uid from u where clave = 'gerente_pruebas';
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    perform public.copiar_receta_a_org(
      'aaaaaaaa-0025-0025-0025-000000000025',
      '367d4642-16bc-4817-9565-a6b914d96aa9'
    );
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values (
    'P10 compartición desactivada → copiar falla',
    'exc: no está activa',
    v_err,
    v_err ilike '%no está compartida%' or v_err ilike '%no está activa%'
  );
end $$;

-- Reactivar para pruebas posteriores (seguimos como postgres)
reset role;
update public.comparticiones
   set activa = true
 where objeto_id               = 'aaaaaaaa-0025-0025-0025-000000000025'
   and destino_organizacion_id = '367d4642-16bc-4817-9565-a6b914d96aa9';

-- =============================================================================
-- P11: anon NO puede ejecutar ninguna función pública de Fase 4
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
      'aaaaaaaa-0025-0025-0025-000000000025',
      '367d4642-16bc-4817-9565-a6b914d96aa9'
    );
  exception when others then v_err3 := sqlerrm; end;

  insert into r values (
    'P11 anon NO puede ejecutar funciones Fase 4',
    'todas lanzan exc',
    'listar_dest=' || (v_err1 <> 'no lanzó excepción')::text
      || ' listar_conmigo=' || (v_err2 <> 'no lanzó excepción')::text
      || ' copiar=' || (v_err3 <> 'no lanzó excepción')::text,
    (v_err1 <> 'no lanzó excepción')
      and (v_err2 <> 'no lanzó excepción')
      and (v_err3 <> 'no lanzó excepción')
  );
end $$;

reset role;

-- =============================================================================
-- P12: UPDATE que cambia objeto_id a receta inexistente falla (RLS WITH CHECK)
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
begin
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims',
    '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    update public.comparticiones
       set objeto_id = gen_random_uuid()   -- UUID ficticio → no es receta de Samirarte
     where objeto_id              = 'aaaaaaaa-0025-0025-0025-000000000025'
       and origen_organizacion_id = '4bdf1328-958e-4b0b-97de-38ba157a5e2e';
  exception when others then
    v_err := sqlerrm;
  end;

  -- Si Postgres no lanzó excepción (puede devolver 0 filas silenciosamente),
  -- verificar que el objeto_id sigue siendo el original
  if v_err = 'no lanzó excepción' then
    if exists (
      select 1 from public.comparticiones
      where objeto_id = 'aaaaaaaa-0025-0025-0025-000000000025'
    ) then
      v_err := 'update afectó 0 filas (correcto)';
    else
      v_err := 'ERROR: objeto_id fue cambiado por RLS fallido';
    end if;
  end if;

  insert into r values (
    'P12 UPDATE objeto_id a receta ajena falla o afecta 0 filas',
    'exc o 0 filas',
    v_err,
    v_err not ilike '%ERROR: objeto_id fue cambiado%'
  );
end $$;

reset role;

-- =============================================================================
-- P13: segundo INSERT 'todas' de la misma receta falla (NULLS NOT DISTINCT)
-- =============================================================================
do $$
declare
  v_err text := 'no lanzó excepción';
begin
  -- Primera compartición 'todas' (como postgres, sin restricciones RLS)
  insert into public.comparticiones (
    origen_organizacion_id, tipo, objeto_id,
    destino, destino_organizacion_id, activa, created_by
  ) values (
    '4bdf1328-958e-4b0b-97de-38ba157a5e2e',
    'receta',
    'aaaaaaaa-0025-0025-0025-000000000025',
    'todas', null, true,
    (select id from u where clave = 'gerente_samirarte')
  );

  -- Segundo INSERT idéntico debe fallar por UNIQUE NULLS NOT DISTINCT
  begin
    insert into public.comparticiones (
      origen_organizacion_id, tipo, objeto_id,
      destino, destino_organizacion_id, activa, created_by
    ) values (
      '4bdf1328-958e-4b0b-97de-38ba157a5e2e',
      'receta',
      'aaaaaaaa-0025-0025-0025-000000000025',
      'todas', null, true,
      (select id from u where clave = 'gerente_samirarte')
    );
  exception when unique_violation then
    v_err := 'unique_violation';
  end;

  insert into r values (
    'P13 segundo compartir todas misma receta falla (NULLS NOT DISTINCT)',
    'unique_violation',
    v_err,
    v_err = 'unique_violation'
  );
end $$;

reset role;

-- =============================================================================
-- RESULTADO
-- =============================================================================

select prueba, resultado_esperado, obtenido, ok
from r
order by prueba;

rollback;
