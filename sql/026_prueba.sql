-- =============================================================================
-- 026_prueba.sql
-- Prueba de aislamiento de la Fase 5 (facturación por organización).
--
-- CÓMO EJECUTAR:
--   Pegar TODO el script en el SQL Editor de Supabase y ejecutarlo de una vez.
--   Ejecutar como postgres (superusuario). No hay nada que sustituir.
--   El script termina con ROLLBACK: no deja rastro en la BD.
--   Revisar la tabla r al final: todas las filas deben tener ok = true.
--
-- Requisito: sql/026_facturacion_por_org.sql ya aplicado.
--
-- UUIDs de organizaciones (hardcoded):
--   Samirarte : 4bdf1328-958e-4b0b-97de-38ba157a5e2e
--   Pruebas   : 367d4642-16bc-4817-9565-a6b914d96aa9
-- =============================================================================

begin;

-- ── Tablas de trabajo ────────────────────────────────────────────────────────

create temp table r (
  prueba             text    not null,
  resultado_esperado text    not null,
  obtenido           text,
  ok                 boolean
) on commit drop;

-- u: 4 primeros usuarios de auth.users → gerente/chef de cada org
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
    end as clave, id
  from auth.users
  order by created_at
  limit 4
) sub where clave is not null;

grant all on r, u to authenticated, anon;

-- ── Preparar membresías ───────────────────────────────────────────────────────

insert into public.organizacion_miembros (organizacion_id, user_id, rol, activo)
values ('4bdf1328-958e-4b0b-97de-38ba157a5e2e', (select id from u where clave='gerente_samirarte'), 'gerente', true)
on conflict (organizacion_id, user_id) do update set rol='gerente', activo=true;

insert into public.organizacion_miembros (organizacion_id, user_id, rol, activo)
values ('4bdf1328-958e-4b0b-97de-38ba157a5e2e', (select id from u where clave='chef_samirarte'), 'chef', true)
on conflict (organizacion_id, user_id) do update set rol='chef', activo=true;

insert into public.organizacion_miembros (organizacion_id, user_id, rol, activo)
values ('367d4642-16bc-4817-9565-a6b914d96aa9', (select id from u where clave='gerente_pruebas'), 'gerente', true)
on conflict (organizacion_id, user_id) do update set rol='gerente', activo=true;

insert into public.organizacion_miembros (organizacion_id, user_id, rol, activo)
values ('367d4642-16bc-4817-9565-a6b914d96aa9', (select id from u where clave='chef_pruebas'), 'chef', true)
on conflict (organizacion_id, user_id) do update set rol='chef', activo=true;

-- ── Config fiscal de Samirarte (sin logo de momento) ────────────────────────
insert into public.organizacion_config (organizacion_id, razon_social, nif_cif, direccion_fiscal, tipo_iva_defecto)
values ('4bdf1328-958e-4b0b-97de-38ba157a5e2e', 'Samirarte TEST', 'B12345678', 'Calle de la Prueba 1, Madrid', 10)
on conflict (organizacion_id) do update
  set razon_social='Samirarte TEST', nif_cif='B12345678', direccion_fiscal='Calle de la Prueba 1, Madrid';

-- Config de Pruebas SIN datos fiscales completos (para probar bloqueo de emisión)
insert into public.organizacion_config (organizacion_id, razon_social, nif_cif, direccion_fiscal, tipo_iva_defecto)
values ('367d4642-16bc-4817-9565-a6b914d96aa9', '', '', '', 21)
on conflict (organizacion_id) do update set razon_social='', nif_cif='', direccion_fiscal='';

-- ── Borrar contadores del año en curso para empezar limpio ───────────────────
delete from public.organizacion_contadores
where organizacion_id in (
  '4bdf1328-958e-4b0b-97de-38ba157a5e2e',
  '367d4642-16bc-4817-9565-a6b914d96aa9'
);

-- ── Cliente de prueba ────────────────────────────────────────────────────────
insert into public.clientes (id, organizacion_id, user_id, nombre, nif_cif)
values (
  'cccccccc-0026-0026-0026-000000000001',
  '4bdf1328-958e-4b0b-97de-38ba157a5e2e',
  (select id from u where clave='gerente_samirarte'),
  'Cliente TEST 026', 'X9999999X'
) on conflict (id) do nothing;

-- ── Borrador de factura de Samirarte (sin número) ────────────────────────────
insert into public.facturas (id, organizacion_id, user_id, cliente_id, tipo_documento, estado,
  base_imponible, iva_pct, iva_importe, retencion_pct, retencion_importe, total)
values (
  'ffffffff-0026-0026-0026-000000000001',
  '4bdf1328-958e-4b0b-97de-38ba157a5e2e',
  (select id from u where clave='gerente_samirarte'),
  'cccccccc-0026-0026-0026-000000000001',
  'factura', 'borrador',
  1000, 10, 100, 0, 0, 1100
) on conflict (id) do nothing;

-- Segunda factura borrador (para la prueba de segunda emisión → 0002)
insert into public.facturas (id, organizacion_id, user_id, cliente_id, tipo_documento, estado,
  base_imponible, iva_pct, iva_importe, retencion_pct, retencion_importe, total)
values (
  'ffffffff-0026-0026-0026-000000000002',
  '4bdf1328-958e-4b0b-97de-38ba157a5e2e',
  (select id from u where clave='gerente_samirarte'),
  'cccccccc-0026-0026-0026-000000000001',
  'factura', 'borrador',
  500, 10, 50, 0, 0, 550
) on conflict (id) do nothing;

-- Borrador de presupuesto de Samirarte
insert into public.facturas (id, organizacion_id, user_id, cliente_id, tipo_documento, estado,
  base_imponible, iva_pct, iva_importe, retencion_pct, retencion_importe, total)
values (
  'ffffffff-0026-0026-0026-000000000003',
  '4bdf1328-958e-4b0b-97de-38ba157a5e2e',
  (select id from u where clave='gerente_samirarte'),
  'cccccccc-0026-0026-0026-000000000001',
  'presupuesto', 'borrador',
  800, 10, 80, 0, 0, 880
) on conflict (id) do nothing;

-- Borrador de factura de Pruebas (para probar contadores independientes)
insert into public.clientes (id, organizacion_id, user_id, nombre, nif_cif)
values (
  'cccccccc-0026-0026-0026-000000000002',
  '367d4642-16bc-4817-9565-a6b914d96aa9',
  (select id from u where clave='gerente_pruebas'),
  'Cliente Pruebas 026', 'Y9999999Y'
) on conflict (id) do nothing;

-- Config fiscal completa para Pruebas (necesaria para emitir en prueba P11)
insert into public.organizacion_config (organizacion_id, razon_social, nif_cif, direccion_fiscal, tipo_iva_defecto)
values ('367d4642-16bc-4817-9565-a6b914d96aa9', 'Org Pruebas TEST', 'B99999999', 'Av. Pruebas 999, Barcelona', 21)
on conflict (organizacion_id) do update
  set razon_social='Org Pruebas TEST', nif_cif='B99999999', direccion_fiscal='Av. Pruebas 999, Barcelona';

insert into public.facturas (id, organizacion_id, user_id, cliente_id, tipo_documento, estado,
  base_imponible, iva_pct, iva_importe, retencion_pct, retencion_importe, total)
values (
  'ffffffff-0026-0026-0026-000000000004',
  '367d4642-16bc-4817-9565-a6b914d96aa9',
  (select id from u where clave='gerente_pruebas'),
  'cccccccc-0026-0026-0026-000000000002',
  'factura', 'borrador',
  200, 21, 42, 0, 0, 242
) on conflict (id) do nothing;

-- ── Líneas de ejemplo (necesarias: emitir_documento exige >=1 línea y que los
--    totales de cabecera cuadren con la suma de líneas, tolerancia 0,01 €) ──
insert into public.factura_lineas (factura_id, descripcion, cantidad, precio_unitario, base_linea, iva_pct, iva_linea, total_linea, orden)
values
  ('ffffffff-0026-0026-0026-000000000001', 'Servicio TEST', 1, 1000, 1000, 10, 100, 1100, 1),
  ('ffffffff-0026-0026-0026-000000000002', 'Servicio TEST 2', 1,  500,  500, 10,  50,  550, 1),
  ('ffffffff-0026-0026-0026-000000000003', 'Servicio TEST 3', 1,  800,  800, 10,  80,  880, 1),
  ('ffffffff-0026-0026-0026-000000000004', 'Servicio TEST 4', 1,  200,  200, 21,  42,  242, 1)
on conflict do nothing;


-- =============================================================================
-- P01: chef Samirarte NO puede emitir (no es gerente)
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
begin
  select id into v_uid from u where clave = 'chef_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    perform public.emitir_documento('ffffffff-0026-0026-0026-000000000001');
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values ('P01 chef NO puede emitir', 'exc: Solo el gerente', v_err, v_err ilike '%Solo el gerente%');
end $$;
reset role;

-- =============================================================================
-- P02: gerente Samirarte SÍ puede emitir; obtiene FAC-AAAA-0001
-- =============================================================================
do $$
declare
  v_uid    uuid;
  v_numero text;
  v_anio   text := extract(year from (current_timestamp at time zone 'Europe/Madrid')::date)::text;
  v_ok     boolean;
begin
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  v_numero := public.emitir_documento('ffffffff-0026-0026-0026-000000000001');
  v_ok := (v_numero = 'FAC-' || v_anio || '-0001');

  perform set_config('test.numero_1', v_numero, true);

  insert into r values (
    'P02 gerente emite → FAC-' || v_anio || '-0001',
    'FAC-' || v_anio || '-0001', v_numero, v_ok
  );
end $$;
reset role;

-- =============================================================================
-- P03: segunda emisión → FAC-AAAA-0002
-- =============================================================================
do $$
declare
  v_uid    uuid;
  v_numero text;
  v_anio   text := extract(year from (current_timestamp at time zone 'Europe/Madrid')::date)::text;
begin
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  v_numero := public.emitir_documento('ffffffff-0026-0026-0026-000000000002');

  insert into r values (
    'P03 segunda emisión → FAC-' || v_anio || '-0002',
    'FAC-' || v_anio || '-0002', v_numero,
    v_numero = 'FAC-' || v_anio || '-0002'
  );
end $$;
reset role;

-- =============================================================================
-- P04: presupuesto → PRE-AAAA-0001 (contador independiente de FAC)
-- =============================================================================
do $$
declare
  v_uid    uuid;
  v_numero text;
  v_anio   text := extract(year from (current_timestamp at time zone 'Europe/Madrid')::date)::text;
begin
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  v_numero := public.emitir_documento('ffffffff-0026-0026-0026-000000000003');

  insert into r values (
    'P04 presupuesto → PRE-' || v_anio || '-0001 (contador independiente de FAC)',
    'PRE-' || v_anio || '-0001', v_numero,
    v_numero = 'PRE-' || v_anio || '-0001'
  );
end $$;
reset role;

-- =============================================================================
-- P05: contadores independientes entre orgs — Pruebas también emite FAC-AAAA-0001
-- =============================================================================
do $$
declare
  v_uid    uuid;
  v_numero text;
  v_anio   text := extract(year from (current_timestamp at time zone 'Europe/Madrid')::date)::text;
begin
  select id into v_uid from u where clave = 'gerente_pruebas';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  v_numero := public.emitir_documento('ffffffff-0026-0026-0026-000000000004');

  insert into r values (
    'P05 Pruebas emite independiente → FAC-' || v_anio || '-0001',
    'FAC-' || v_anio || '-0001', v_numero,
    v_numero = 'FAC-' || v_anio || '-0001'
  );
end $$;
reset role;

-- =============================================================================
-- P06: NO se puede emitir sin config fiscal completa
-- Creamos un borrador de org sin config y lo intentamos emitir
-- =============================================================================
do $$
declare
  v_uid    uuid;
  v_err    text := 'no lanzó excepción';
  v_fid    uuid := 'ffffffff-0026-0026-0026-000000000009';
begin
  -- Config de Samirarte incompleta temporalmente
  update public.organizacion_config
  set nif_cif = '', razon_social = '', direccion_fiscal = ''
  where organizacion_id = '4bdf1328-958e-4b0b-97de-38ba157a5e2e';

  -- Crear borrador sin número, con línea que cuadra (para llegar al check de config)
  insert into public.facturas (id, organizacion_id, user_id, cliente_id, tipo_documento, estado,
    base_imponible, iva_pct, iva_importe, retencion_pct, retencion_importe, total)
  values (v_fid, '4bdf1328-958e-4b0b-97de-38ba157a5e2e',
    (select id from u where clave='gerente_samirarte'),
    'cccccccc-0026-0026-0026-000000000001',
    'factura', 'borrador', 100, 10, 10, 0, 0, 110)
  on conflict (id) do nothing;
  insert into public.factura_lineas (factura_id, descripcion, cantidad, precio_unitario, base_linea, iva_pct, iva_linea, total_linea, orden)
  values (v_fid, 'Servicio TEST 9', 1, 100, 100, 10, 10, 110, 1)
  on conflict do nothing;

  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    perform public.emitir_documento(v_fid);
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values (
    'P06 emitir sin config fiscal → excepción',
    'exc: Faltan datos fiscales',
    v_err,
    v_err ilike '%Faltan datos fiscales%' or v_err ilike '%datos del emisor%'
  );
end $$;
reset role;
-- Restaurar config de Samirarte
update public.organizacion_config
set razon_social='Samirarte TEST', nif_cif='B12345678', direccion_fiscal='Calle de la Prueba 1, Madrid'
where organizacion_id = '4bdf1328-958e-4b0b-97de-38ba157a5e2e';

-- =============================================================================
-- P07: documento emitido → update de importe falla
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
begin
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    update public.facturas
    set base_imponible = 9999
    where id = 'ffffffff-0026-0026-0026-000000000001';
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values (
    'P07 emitida → update importe falla',
    'exc: No se pueden modificar',
    v_err,
    v_err ilike '%No se pueden modificar%' or v_err ilike '%modificar los importes%'
  );
end $$;
reset role;

-- =============================================================================
-- P08: documento emitido → update de cliente falla
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
begin
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    update public.facturas
    set cliente_id = gen_random_uuid()
    where id = 'ffffffff-0026-0026-0026-000000000001';
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values (
    'P08 emitida → update cliente falla',
    'exc: No se puede cambiar el cliente',
    v_err,
    v_err ilike '%No se puede cambiar el cliente%'
  );
end $$;
reset role;

-- =============================================================================
-- P09: documento emitido → update de numero_factura falla
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
begin
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    update public.facturas
    set numero_factura = 'FAC-2099-9999'
    where id = 'ffffffff-0026-0026-0026-000000000001';
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values (
    'P09 emitida → update numero_factura falla',
    'exc: numero_factura solo puede asignarse',
    v_err,
    v_err ilike '%numero_factura%'
  );
end $$;
reset role;

-- =============================================================================
-- P10: documento emitido → DELETE falla
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
begin
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    delete from public.facturas where id = 'ffffffff-0026-0026-0026-000000000001';
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values (
    'P10 emitida → DELETE falla',
    'exc: No se puede borrar',
    v_err,
    v_err ilike '%No se puede borrar%'
  );
end $$;
reset role;

-- =============================================================================
-- P11: documento emitido → modificar líneas falla
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
begin
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    update public.factura_lineas
    set precio_unitario = 9999
    where factura_id = 'ffffffff-0026-0026-0026-000000000001';
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values (
    'P11 emitida → modificar líneas falla',
    'exc: No se pueden modificar las líneas',
    v_err,
    v_err ilike '%No se pueden modificar las líneas%' or v_err ilike '%líneas de un documento%'
  );
end $$;
reset role;

-- =============================================================================
-- P12: transición emitida → cobrada OK
-- =============================================================================
do $$
declare
  v_uid    uuid;
  v_estado text;
begin
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  update public.facturas set estado = 'cobrada'
  where id = 'ffffffff-0026-0026-0026-000000000001';

  select estado into v_estado from public.facturas
  where id = 'ffffffff-0026-0026-0026-000000000001';

  insert into r values (
    'P12 emitida → cobrada OK',
    'cobrada', v_estado, v_estado = 'cobrada'
  );
end $$;
reset role;

-- =============================================================================
-- P13: factura emitida → anulada FALLA (solo presupuestos pueden anularse)
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
begin
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  -- ffffffff-...0002 es una factura emitida (FAC-AAAA-0002 de P03)
  begin
    update public.facturas set estado = 'anulada'
    where id = 'ffffffff-0026-0026-0026-000000000002';
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values (
    'P13 factura emitida → anulada FALLA (no es presupuesto)',
    'exc: Transición no permitida',
    v_err,
    v_err ilike '%Transición no permitida%' or v_err ilike '%rectificativa%'
  );
end $$;
reset role;

-- =============================================================================
-- P14: presupuesto emitido → anulado OK
-- =============================================================================
do $$
declare
  v_uid    uuid;
  v_estado text;
begin
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  -- ffffffff-...0003 es el presupuesto emitido PRE-AAAA-0001 de P04
  update public.facturas set estado = 'anulada'
  where id = 'ffffffff-0026-0026-0026-000000000003';

  select estado into v_estado from public.facturas
  where id = 'ffffffff-0026-0026-0026-000000000003';

  insert into r values (
    'P14 presupuesto emitido → anulado OK',
    'anulada', v_estado, v_estado = 'anulada'
  );
end $$;
reset role;

-- =============================================================================
-- P15: snapshot del emisor no cambia al modificar la config después de emitir
-- =============================================================================
do $$
declare
  v_uid           uuid;
  v_emisor_antes  text;
  v_emisor_despues text;
begin
  -- Leer el snapshot guardado al emitir (P02)
  select emisor_razon_social into v_emisor_antes
  from public.facturas where id = 'ffffffff-0026-0026-0026-000000000001';

  -- Cambiar la config de la org como gerente
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  update public.organizacion_config
  set razon_social = 'NOMBRE CAMBIADO POST-EMISIÓN'
  where organizacion_id = '4bdf1328-958e-4b0b-97de-38ba157a5e2e';

  -- El snapshot en la factura ya emitida NO debe cambiar
  select emisor_razon_social into v_emisor_despues
  from public.facturas where id = 'ffffffff-0026-0026-0026-000000000001';

  insert into r values (
    'P15 snapshot emisor no cambia al modificar config post-emisión',
    v_emisor_antes,
    v_emisor_despues,
    v_emisor_antes = v_emisor_despues and v_emisor_antes = 'Samirarte TEST'
  );
end $$;
reset role;

-- =============================================================================
-- P16: otra org NO ve ni la config ni las facturas ajenas
-- =============================================================================
do $$
declare
  v_uid      uuid;
  v_n_config integer;
  v_n_fact   integer;
begin
  select id into v_uid from u where clave = 'gerente_pruebas';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  -- No debe ver la config de Samirarte
  select count(*) into v_n_config
  from public.organizacion_config
  where organizacion_id = '4bdf1328-958e-4b0b-97de-38ba157a5e2e';

  -- No debe ver las facturas de Samirarte
  select count(*) into v_n_fact
  from public.facturas
  where organizacion_id = '4bdf1328-958e-4b0b-97de-38ba157a5e2e';

  insert into r values (
    'P16 org Pruebas NO ve config ni facturas de Samirarte',
    'config=0 fact=0',
    'config=' || v_n_config || ' fact=' || v_n_fact,
    v_n_config = 0 and v_n_fact = 0
  );
end $$;
reset role;

-- =============================================================================
-- P17: anon NO puede ejecutar ninguna función de Fase 5
-- =============================================================================
do $$
declare
  v_err1 text := 'no lanzó excepción';
  v_err2 text := 'no lanzó excepción';
  v_err3 text := 'no lanzó excepción';
begin
  set local role anon;

  begin
    perform public.emitir_documento('ffffffff-0026-0026-0026-000000000002');
  exception when others then v_err1 := sqlerrm; end;

  begin
    perform public.crear_rectificativa('ffffffff-0026-0026-0026-000000000001');
  exception when others then v_err2 := sqlerrm; end;

  begin
    perform public.obtener_config_facturacion('4bdf1328-958e-4b0b-97de-38ba157a5e2e');
  exception when others then v_err3 := sqlerrm; end;

  insert into r values (
    'P17 anon NO puede ejecutar funciones Fase 5',
    'todas lanzan exc',
    'emitir=' || (v_err1 <> 'no lanzó excepción')::text
      || ' rectif=' || (v_err2 <> 'no lanzó excepción')::text
      || ' config=' || (v_err3 <> 'no lanzó excepción')::text,
    (v_err1 <> 'no lanzó excepción')
      and (v_err2 <> 'no lanzó excepción')
      and (v_err3 <> 'no lanzó excepción')
  );
end $$;
reset role;

-- =============================================================================
-- P18: crear_rectificativa de factura emitida → devuelve UUID de borrador
-- =============================================================================
do $$
declare
  v_uid     uuid;
  v_rect_id uuid;
  v_tipo    text;
  v_estado  text;
  v_ref     uuid;
begin
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  -- ffffffff-...0002 está emitida (FAC-AAAA-0002 de P03)
  v_rect_id := public.crear_rectificativa('ffffffff-0026-0026-0026-000000000002');

  select tipo_documento, estado, factura_rectificada_id
  into v_tipo, v_estado, v_ref
  from public.facturas where id = v_rect_id;

  insert into r values (
    'P18 crear_rectificativa → borrador rectificativo enlazado',
    'tipo=factura_rectificativa estado=borrador ref=0002',
    'tipo=' || coalesce(v_tipo,'null')
      || ' estado=' || coalesce(v_estado,'null')
      || ' ref_ok=' || (v_ref = 'ffffffff-0026-0026-0026-000000000002')::text,
    v_tipo = 'factura_rectificativa'
      and v_estado = 'borrador'
      and v_ref = 'ffffffff-0026-0026-0026-000000000002'
  );
end $$;
reset role;

-- =============================================================================
-- P19: chef NO puede cambiar el logo (INSERT/UPDATE en organizacion_config)
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
begin
  select id into v_uid from u where clave = 'chef_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    update public.organizacion_config
    set logo = '\x89504e47'::bytea  -- PNG magic bytes de prueba
    where organizacion_id = '4bdf1328-958e-4b0b-97de-38ba157a5e2e';
  exception when others then
    v_err := sqlerrm;
  end;

  -- Si no lanzó excepción (Postgres puede devolver 0 filas silenciosamente con RLS),
  -- comprobar que el logo sigue siendo null
  if v_err = 'no lanzó excepción' then
    if not exists (
      select 1 from public.organizacion_config
      where organizacion_id = '4bdf1328-958e-4b0b-97de-38ba157a5e2e'
        and logo is not null
    ) then
      v_err := 'afectó 0 filas (correcto: RLS bloqueó)';
    else
      v_err := 'ERROR: chef pudo cambiar el logo';
    end if;
  end if;

  insert into r values (
    'P19 chef NO puede cambiar el logo (RLS bloquea update)',
    'exc o 0 filas',
    v_err,
    v_err not ilike '%ERROR: chef pudo cambiar%'
  );
end $$;
reset role;

-- =============================================================================
-- P20: gerente SÍ puede subir logo; chef lo puede leer
-- =============================================================================
do $$
declare
  v_uid_g uuid;
  v_uid_c uuid;
  v_logo  bytea;
  v_ok    boolean;
begin
  -- Gerente sube logo (PNG magic bytes de prueba: 4 bytes)
  select id into v_uid_g from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid_g || '","role":"authenticated"}', true);

  update public.organizacion_config
  set logo = '\x89504e47'::bytea, logo_mime = 'image/png'
  where organizacion_id = '4bdf1328-958e-4b0b-97de-38ba157a5e2e';
end $$;
reset role;

do $$
declare
  v_uid_c uuid;
  v_logo  bytea;
begin
  -- Chef lee el logo de su org (SELECT permitido a miembros)
  select id into v_uid_c from u where clave = 'chef_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid_c || '","role":"authenticated"}', true);

  select logo into v_logo
  from public.organizacion_config
  where organizacion_id = '4bdf1328-958e-4b0b-97de-38ba157a5e2e';

  insert into r values (
    'P20 gerente sube logo; chef puede leerlo',
    'logo not null',
    case when v_logo is not null then 'logo present' else 'null' end,
    v_logo is not null
  );
end $$;
reset role;

-- =============================================================================
-- P21: otra org NO puede leer ni cambiar el logo ajeno
-- =============================================================================
do $$
declare
  v_uid    uuid;
  v_n_logo integer;
  v_err    text := 'no lanzó excepción';
begin
  select id into v_uid from u where clave = 'gerente_pruebas';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  -- No debe ver la config de Samirarte
  select count(*) into v_n_logo
  from public.organizacion_config
  where organizacion_id = '4bdf1328-958e-4b0b-97de-38ba157a5e2e';

  -- No debe poder actualizar el logo de Samirarte
  begin
    update public.organizacion_config
    set logo = '\x89504e47'::bytea
    where organizacion_id = '4bdf1328-958e-4b0b-97de-38ba157a5e2e';
  exception when others then
    v_err := sqlerrm;
  end;
  if v_err = 'no lanzó excepción' then
    v_err := 'afectó 0 filas (correcto: RLS)';
  end if;

  insert into r values (
    'P21 otra org NO lee ni cambia logo ajeno',
    'select=0 update=0filas',
    'select=' || v_n_logo || ' update=' || v_err,
    v_n_logo = 0 and v_err not ilike '%ERROR%'
  );
end $$;
reset role;

-- =============================================================================
-- P22: INSERT directo de una factura con estado 'emitida' FALLA (trigger INSERT)
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
begin
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    insert into public.facturas (organizacion_id, user_id, cliente_id, tipo_documento, estado,
      base_imponible, iva_pct, iva_importe, retencion_pct, retencion_importe, total)
    values ('4bdf1328-958e-4b0b-97de-38ba157a5e2e', v_uid,
      'cccccccc-0026-0026-0026-000000000001', 'factura', 'emitida',
      100, 10, 10, 0, 0, 110);
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values (
    'P22 INSERT estado emitida falla',
    'exc: solo borrador',
    v_err,
    v_err ilike '%borrador%'
  );
end $$;
reset role;

-- =============================================================================
-- P23: INSERT directo con numero_factura FALLA (trigger INSERT)
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
begin
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    insert into public.facturas (organizacion_id, user_id, cliente_id, tipo_documento, estado,
      numero_factura, base_imponible, iva_pct, iva_importe, retencion_pct, retencion_importe, total)
    values ('4bdf1328-958e-4b0b-97de-38ba157a5e2e', v_uid,
      'cccccccc-0026-0026-0026-000000000001', 'factura', 'borrador',
      'FAC-2099-0001', 100, 10, 10, 0, 0, 110);
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values (
    'P23 INSERT con numero_factura falla',
    'exc: un borrador no puede llevar número',
    v_err,
    v_err ilike '%número%' or v_err ilike '%numero%'
  );
end $$;
reset role;

-- =============================================================================
-- P24: UPDATE directo borrador→emitida FALLA (solo vía emitir_documento)
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
  v_fid uuid := 'ffffffff-0026-0026-0026-000000000024';
begin
  -- Crear un borrador como postgres
  insert into public.facturas (id, organizacion_id, user_id, cliente_id, tipo_documento, estado,
    base_imponible, iva_pct, iva_importe, retencion_pct, retencion_importe, total)
  values (v_fid, '4bdf1328-958e-4b0b-97de-38ba157a5e2e',
    (select id from u where clave='gerente_samirarte'),
    'cccccccc-0026-0026-0026-000000000001', 'factura', 'borrador',
    100, 10, 10, 0, 0, 110)
  on conflict (id) do nothing;

  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    update public.facturas set estado = 'emitida' where id = v_fid;
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values (
    'P24 UPDATE borrador→emitida directo falla',
    'exc: solo mediante emitir_documento',
    v_err,
    v_err ilike '%emitir_documento%'
  );
end $$;
reset role;

-- =============================================================================
-- P25: en emitida, cambiar tipo_documento FALLA (lista blanca)
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
begin
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  -- 0002 está emitida (FAC-AAAA-0002)
  begin
    update public.facturas set tipo_documento = 'presupuesto'
    where id = 'ffffffff-0026-0026-0026-000000000002';
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values (
    'P25 emitida: cambiar tipo_documento falla',
    'exc: inmutable',
    v_err,
    v_err ilike '%inmutable%'
  );
end $$;
reset role;

-- =============================================================================
-- P26: en emitida, cambiar iva_pct FALLA (lista blanca)
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
begin
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    update public.facturas set iva_pct = 4
    where id = 'ffffffff-0026-0026-0026-000000000002';
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values (
    'P26 emitida: cambiar iva_pct falla',
    'exc: inmutable',
    v_err,
    v_err ilike '%inmutable%'
  );
end $$;
reset role;

-- =============================================================================
-- P27: en emitida, cambiar concepto FALLA (lista blanca)
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
begin
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    update public.facturas set concepto = 'CAMBIO ILEGAL'
    where id = 'ffffffff-0026-0026-0026-000000000002';
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values (
    'P27 emitida: cambiar concepto falla',
    'exc: inmutable',
    v_err,
    v_err ilike '%inmutable%'
  );
end $$;
reset role;

-- =============================================================================
-- P28: en emitida, cambiar emisor_nif y cliente_snapshot_nombre FALLA
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err1 text := 'no lanzó excepción';
  v_err2 text := 'no lanzó excepción';
begin
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    update public.facturas set emisor_nif = 'X0000000X'
    where id = 'ffffffff-0026-0026-0026-000000000002';
  exception when others then v_err1 := sqlerrm; end;

  begin
    update public.facturas set cliente_snapshot_nombre = 'OTRO CLIENTE'
    where id = 'ffffffff-0026-0026-0026-000000000002';
  exception when others then v_err2 := sqlerrm; end;

  insert into r values (
    'P28 emitida: cambiar emisor_nif / cliente_snapshot_nombre falla',
    'ambos inmutables',
    'emisor=' || (v_err1 ilike '%inmutable%')::text || ' cliente=' || (v_err2 ilike '%inmutable%')::text,
    v_err1 ilike '%inmutable%' and v_err2 ilike '%inmutable%'
  );
end $$;
reset role;

-- =============================================================================
-- P29: chef NO puede pasar emitida→cobrada; gerente SÍ
-- =============================================================================
do $$
declare
  v_uid_c uuid;
  v_uid_g uuid;
  v_err   text := 'no lanzó excepción';
  v_estado text;
  v_fid   uuid := 'ffffffff-0026-0026-0026-000000000029';
  v_num   text;
begin
  -- Crear y emitir (como gerente) una factura para la prueba de transición
  insert into public.facturas (id, organizacion_id, user_id, cliente_id, tipo_documento, estado,
    base_imponible, iva_pct, iva_importe, retencion_pct, retencion_importe, total)
  values (v_fid, '4bdf1328-958e-4b0b-97de-38ba157a5e2e',
    (select id from u where clave='gerente_samirarte'),
    'cccccccc-0026-0026-0026-000000000001', 'factura', 'borrador',
    100, 10, 10, 0, 0, 110)
  on conflict (id) do nothing;
  insert into public.factura_lineas (factura_id, descripcion, cantidad, precio_unitario, base_linea, iva_pct, iva_linea, total_linea, orden)
  values (v_fid, 'Servicio 29', 1, 100, 100, 10, 10, 110, 1)
  on conflict do nothing;

  select id into v_uid_g from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid_g || '","role":"authenticated"}', true);
  v_num := public.emitir_documento(v_fid);

  -- Chef intenta marcar como cobrada → falla
  reset role;
  select id into v_uid_c from u where clave = 'chef_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid_c || '","role":"authenticated"}', true);
  begin
    update public.facturas set estado = 'cobrada' where id = v_fid;
  exception when others then v_err := sqlerrm; end;

  -- Gerente marca como cobrada → OK
  reset role;
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid_g || '","role":"authenticated"}', true);
  update public.facturas set estado = 'cobrada' where id = v_fid;
  select estado into v_estado from public.facturas where id = v_fid;

  insert into r values (
    'P29 chef NO pasa emitida→cobrada; gerente SÍ',
    'chef falla; gerente cobrada',
    'chef_err=' || (v_err ilike '%gerente%')::text || ' estado=' || v_estado,
    (v_err ilike '%gerente%') and v_estado = 'cobrada'
  );
end $$;
reset role;

-- =============================================================================
-- P30: emitir sin líneas FALLA; emitir con totales descuadrados FALLA
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err_sin   text := 'no lanzó excepción';
  v_err_desc  text := 'no lanzó excepción';
  v_fid_sin   uuid := 'ffffffff-0026-0026-0026-000000000030';
  v_fid_desc  uuid := 'ffffffff-0026-0026-0026-000000000031';
begin
  -- Borrador SIN líneas
  insert into public.facturas (id, organizacion_id, user_id, cliente_id, tipo_documento, estado,
    base_imponible, iva_pct, iva_importe, retencion_pct, retencion_importe, total)
  values (v_fid_sin, '4bdf1328-958e-4b0b-97de-38ba157a5e2e',
    (select id from u where clave='gerente_samirarte'),
    'cccccccc-0026-0026-0026-000000000001', 'factura', 'borrador',
    100, 10, 10, 0, 0, 110)
  on conflict (id) do nothing;

  -- Borrador con líneas que NO cuadran con la cabecera
  insert into public.facturas (id, organizacion_id, user_id, cliente_id, tipo_documento, estado,
    base_imponible, iva_pct, iva_importe, retencion_pct, retencion_importe, total)
  values (v_fid_desc, '4bdf1328-958e-4b0b-97de-38ba157a5e2e',
    (select id from u where clave='gerente_samirarte'),
    'cccccccc-0026-0026-0026-000000000001', 'factura', 'borrador',
    999, 10, 99, 0, 0, 1098)   -- cabecera dice 999 pero la línea será 100
  on conflict (id) do nothing;
  insert into public.factura_lineas (factura_id, descripcion, cantidad, precio_unitario, base_linea, iva_pct, iva_linea, total_linea, orden)
  values (v_fid_desc, 'Servicio descuadrado', 1, 100, 100, 10, 10, 110, 1)
  on conflict do nothing;

  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    perform public.emitir_documento(v_fid_sin);
  exception when others then v_err_sin := sqlerrm; end;

  begin
    perform public.emitir_documento(v_fid_desc);
  exception when others then v_err_desc := sqlerrm; end;

  insert into r values (
    'P30 emitir sin líneas / con totales descuadrados falla',
    'ambas fallan',
    'sin_lineas=' || (v_err_sin ilike '%líneas%' or v_err_sin ilike '%linea%')::text
      || ' descuadre=' || (v_err_desc ilike '%no cuadran%' or v_err_desc ilike '%totales%')::text,
    (v_err_sin ilike '%líneas%' or v_err_sin ilike '%linea%')
      and (v_err_desc ilike '%no cuadran%' or v_err_desc ilike '%totales%')
  );
end $$;
reset role;

-- =============================================================================
-- P31: snapshot del cliente NO cambia al editar la ficha del cliente
-- =============================================================================
do $$
declare
  v_uid           uuid;
  v_snap_antes    text;
  v_snap_despues  text;
begin
  -- Snapshot guardado al emitir 0002 (su cliente es cccccccc-...0001)
  select cliente_snapshot_nombre into v_snap_antes
  from public.facturas where id = 'ffffffff-0026-0026-0026-000000000002';

  -- Editar la ficha del cliente como gerente
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);
  update public.clientes set nombre = 'Cliente TEST 026 RENOMBRADO'
  where id = 'cccccccc-0026-0026-0026-000000000001';

  -- El snapshot de la factura emitida no debe cambiar
  select cliente_snapshot_nombre into v_snap_despues
  from public.facturas where id = 'ffffffff-0026-0026-0026-000000000002';

  insert into r values (
    'P31 snapshot cliente no cambia al editar la ficha del cliente',
    v_snap_antes,
    v_snap_despues,
    v_snap_antes = v_snap_despues and v_snap_antes = 'Cliente TEST 026'
  );
end $$;
reset role;

-- =============================================================================
-- P32: logo > 300 KB FALLA (constraint org_config_logo_tamano)
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
begin
  select id into v_uid from u where clave = 'gerente_samirarte';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    -- 300 KB + 1 byte de ceros → supera el límite 307200
    update public.organizacion_config
    set logo = decode(repeat('00', 307201), 'hex'), logo_mime = 'image/png'
    where organizacion_id = '4bdf1328-958e-4b0b-97de-38ba157a5e2e';
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values (
    'P32 logo > 300 KB falla (constraint)',
    'exc: check constraint',
    v_err,
    v_err <> 'no lanzó excepción'
  );
end $$;
reset role;

-- =============================================================================
-- P33: emitir factura de Pruebas con un cliente de Samirarte FALLA
-- =============================================================================
do $$
declare
  v_uid uuid;
  v_err text := 'no lanzó excepción';
  v_fid uuid := 'ffffffff-0026-0026-0026-000000000033';
begin
  -- Borrador en Pruebas pero apuntando al cliente de Samirarte (cccccccc-...0001).
  -- Se inserta como postgres (el trigger de usuario solo valida INSERT de borradores limpios).
  insert into public.facturas (id, organizacion_id, user_id, cliente_id, tipo_documento, estado,
    base_imponible, iva_pct, iva_importe, retencion_pct, retencion_importe, total)
  values (v_fid, '367d4642-16bc-4817-9565-a6b914d96aa9',
    (select id from u where clave='gerente_pruebas'),
    'cccccccc-0026-0026-0026-000000000001',   -- cliente de Samirarte
    'factura', 'borrador', 100, 21, 21, 0, 0, 121)
  on conflict (id) do nothing;
  insert into public.factura_lineas (factura_id, descripcion, cantidad, precio_unitario, base_linea, iva_pct, iva_linea, total_linea, orden)
  values (v_fid, 'Servicio 33', 1, 100, 100, 21, 21, 121, 1)
  on conflict do nothing;

  select id into v_uid from u where clave = 'gerente_pruebas';
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"' || v_uid || '","role":"authenticated"}', true);

  begin
    perform public.emitir_documento(v_fid);
  exception when others then
    v_err := sqlerrm;
  end;

  insert into r values (
    'P33 emitir factura de Pruebas con cliente de Samirarte falla',
    'exc: El cliente no pertenece a esta organización',
    v_err,
    v_err ilike '%no pertenece a esta organización%'
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
