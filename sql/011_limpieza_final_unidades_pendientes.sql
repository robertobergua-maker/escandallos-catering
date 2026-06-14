-- Limpieza final de unidades y formatos pendientes.
--
-- Copia de seguridad recomendada antes de ejecutar:
-- create table if not exists public.inventario_backup_antes_limpieza_final_unidades_20260614 as
-- select * from public.inventario;
--
-- Reglas:
-- - No modifica precio_unidad.
-- - No modifica precio_formato_compra.
-- - No elimina datos.
-- - Los updates de cantidad solo actuan si cantidad_formato_compra esta vacia.

-- ============================================================================
-- 1. Limpiar textos no cuantificables
-- ============================================================================

update public.inventario
set unidad_formato_compra = null
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (
    unidad_formato_compra ilike '%€/kg%'
    or unidad_formato_compra ilike '%€ / kg%'
    or unidad_formato_compra ilike '%pieza aprox%'
    or unidad_formato_compra ilike '%pieza precio aprox%'
  );

-- ============================================================================
-- 2. Pesos exactos a kg
-- ============================================================================

update public.inventario
set cantidad_formato_compra = 0.010,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '10 g%' or unidad_formato_compra ilike '% 10 g%');

update public.inventario
set cantidad_formato_compra = 0.015,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '15 g%' or unidad_formato_compra ilike '% 15 g%');

update public.inventario
set cantidad_formato_compra = 0.023,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '23 g%' or unidad_formato_compra ilike '% 23 g%');

update public.inventario
set cantidad_formato_compra = 0.030,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '30 g%' or unidad_formato_compra ilike '% 30 g%');

update public.inventario
set cantidad_formato_compra = 0.035,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '35 g%' or unidad_formato_compra ilike '% 35 g%');

update public.inventario
set cantidad_formato_compra = 0.038,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '38 g%' or unidad_formato_compra ilike '% 38 g%');

update public.inventario
set cantidad_formato_compra = 0.040,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '40 g%' or unidad_formato_compra ilike '% 40 g%');

update public.inventario
set cantidad_formato_compra = 0.042,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '42 g%' or unidad_formato_compra ilike '% 42 g%');

update public.inventario
set cantidad_formato_compra = 0.045,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '45 g%' or unidad_formato_compra ilike '% 45 g%');

update public.inventario
set cantidad_formato_compra = 0.058,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '58 g%' or unidad_formato_compra ilike '% 58 g%');

update public.inventario
set cantidad_formato_compra = 0.060,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '60 g%' or unidad_formato_compra ilike '% 60 g%');

update public.inventario
set cantidad_formato_compra = 0.071,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '71 g%' or unidad_formato_compra ilike '% 71 g%');

update public.inventario
set cantidad_formato_compra = 0.085,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '85 g%' or unidad_formato_compra ilike '% 85 g%');

update public.inventario
set cantidad_formato_compra = 0.090,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '90 g%' or unidad_formato_compra ilike '% 90 g%');

update public.inventario
set cantidad_formato_compra = 0.140,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '140 g%' or unidad_formato_compra ilike '% 140 g%');

update public.inventario
set cantidad_formato_compra = 0.165,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '165 g%' or unidad_formato_compra ilike '% 165 g%');

update public.inventario
set cantidad_formato_compra = 0.180,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '180 g%' or unidad_formato_compra ilike '% 180 g%');

update public.inventario
set cantidad_formato_compra = 2.5,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '2,5 kg%' or unidad_formato_compra ilike '% 2,5 kg%');

-- ============================================================================
-- 3. Unidades y sobres
-- ============================================================================

update public.inventario
set cantidad_formato_compra = 18,
    unidad_formato_compra = 'ud',
    unidad_medida = 'ud'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '18 uds%' or unidad_formato_compra ilike '% 18 uds%');

update public.inventario
set cantidad_formato_compra = 30,
    unidad_formato_compra = 'ud',
    unidad_medida = 'ud'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '30 uds%' or unidad_formato_compra ilike '% 30 uds%');

update public.inventario
set cantidad_formato_compra = 100,
    unidad_formato_compra = 'sobre',
    unidad_medida = 'sobre'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '100 sobres%' or unidad_formato_compra ilike '% 100 sobres%');

update public.inventario
set cantidad_formato_compra = 150,
    unidad_formato_compra = 'sobre',
    unidad_medida = 'sobre'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '150 sobres%' or unidad_formato_compra ilike '% 150 sobres%');

-- ============================================================================
-- 4. Correcciones evidentes de unidad_medida
-- ============================================================================

-- Coberturas y chocolates no deben trabajar en litros aunque contengan "leche".
update public.inventario
set unidad_medida = 'kg'
where unidad_medida = 'l'
  and (
    descripcion ilike '%cobertura%'
    or descripcion ilike '%chocolate%'
    or descripcion ilike '%sicao%'
    or descripcion ilike '%barry%'
    or formato_compra ilike '%cobertura%'
    or formato_compra ilike '%chocolate%'
    or formato_compra ilike '%sicao%'
    or formato_compra ilike '%barry%'
  );

-- Conservas y pescados en aceite se controlan por peso.
update public.inventario
set unidad_medida = 'kg'
where unidad_medida = 'l'
  and (
    descripcion ilike '%atun%'
    or descripcion ilike '%atún%'
    or descripcion ilike '%anchoa%'
    or descripcion ilike '%anchoas%'
    or descripcion ilike '%ventresca%'
    or descripcion ilike '%bacalao%'
    or descripcion ilike '%berberecho%'
    or descripcion ilike '%calamar%'
    or formato_compra ilike '%atun%'
    or formato_compra ilike '%atún%'
    or formato_compra ilike '%anchoa%'
    or formato_compra ilike '%anchoas%'
    or formato_compra ilike '%ventresca%'
    or formato_compra ilike '%bacalao%'
    or formato_compra ilike '%berberecho%'
    or formato_compra ilike '%calamar%'
  );

-- Especias se controlan por kg.
update public.inventario
set unidad_medida = 'kg'
where unidad_medida is distinct from 'kg'
  and (
    descripcion ilike '%especias%'
    or descripcion ilike '%clavo%'
    or descripcion ilike '%comino%'
    or descripcion ilike '%curry%'
    or descripcion ilike '%oregano%'
    or descripcion ilike '%orégano%'
    or descripcion ilike '%pimienta%'
    or descripcion ilike '%canela%'
    or descripcion ilike '%nuez moscada%'
    or descripcion ilike '%pebrella%'
    or descripcion ilike '%laurel%'
  );

-- ============================================================================
-- 5. Comprobaciones posteriores
-- ============================================================================

select codigo, descripcion, formato_compra, unidad_medida, cantidad_formato_compra, unidad_formato_compra, precio_unidad, precio_formato_compra
from public.inventario
where unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
order by descripcion
limit 100;

select codigo, descripcion, formato_compra, unidad_medida, cantidad_formato_compra, unidad_formato_compra, precio_unidad, precio_formato_compra
from public.inventario
where nullif(trim(formato_compra), '') is not null
  and cantidad_formato_compra is null
order by descripcion
limit 100;

select codigo, descripcion, formato_compra, unidad_medida, cantidad_formato_compra, unidad_formato_compra, precio_unidad, precio_formato_compra
from public.inventario
where cantidad_formato_compra > 1
  and precio_formato_compra is not null
  and precio_unidad = precio_formato_compra
order by descripcion;
