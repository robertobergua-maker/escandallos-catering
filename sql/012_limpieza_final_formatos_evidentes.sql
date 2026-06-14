-- Limpieza prudente de formatos evidentes restantes.
--
-- Copia de seguridad recomendada antes de ejecutar:
-- create table if not exists public.inventario_backup_antes_limpieza_final_evidentes_20260614 as
-- select * from public.inventario;
--
-- Reglas:
-- - No modifica precio_unidad.
-- - No modifica precio_formato_compra.
-- - No elimina datos.
-- - Los updates de cantidad solo actuan si cantidad_formato_compra esta vacia.

-- ============================================================================
-- 1. Limpiar textos no cuantificables o rangos variables
-- ============================================================================

update public.inventario
set unidad_formato_compra = null
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (
    unidad_formato_compra ilike '%pieza aprox%'
    or unidad_formato_compra ilike '%pieza precio aprox%'
    or unidad_formato_compra ilike '%4-5 kg%'
    or unidad_formato_compra ilike '%5-6 kg%'
    or unidad_formato_compra ilike '%2-4 kg%'
    or unidad_formato_compra ilike '%al peso/barra%'
    or formato_compra ilike '%pieza aprox%'
    or formato_compra ilike '%pieza precio aprox%'
    or formato_compra ilike '%4-5 kg%'
    or formato_compra ilike '%5-6 kg%'
    or formato_compra ilike '%2-4 kg%'
    or formato_compra ilike '%al peso/barra%'
  );

-- ============================================================================
-- 2. Pesos evidentes a kg
-- ============================================================================

update public.inventario
set cantidad_formato_compra = 0.0275,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '27,5 g%' or unidad_formato_compra ilike '% 27,5 g%');

update public.inventario
set cantidad_formato_compra = 0.050,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '50 g%' or unidad_formato_compra ilike '% 50 g%');

update public.inventario
set cantidad_formato_compra = 0.170,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '170 g%' or unidad_formato_compra ilike '% 170 g%');

update public.inventario
set cantidad_formato_compra = 0.220,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '220 g%' or unidad_formato_compra ilike '% 220 g%');

-- Caso mixto 255 g / aprox. 12 uds: se usa peso, no unidades.
update public.inventario
set cantidad_formato_compra = 0.255,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (
    unidad_formato_compra ilike '255 g%'
    or unidad_formato_compra ilike '% 255 g%'
  );

update public.inventario
set cantidad_formato_compra = 0.265,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '265 g%' or unidad_formato_compra ilike '% 265 g%');

update public.inventario
set cantidad_formato_compra = 0.525,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '525 g%' or unidad_formato_compra ilike '% 525 g%');

-- Conservas en almibar con neto escurrido: se trabajan por kg.
update public.inventario
set cantidad_formato_compra = 1.5,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (
    unidad_formato_compra ilike '1500 g neto escurrido%'
    or unidad_formato_compra ilike '% 1500 g neto escurrido%'
  );

update public.inventario
set cantidad_formato_compra = 1.795,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (
    unidad_formato_compra ilike '1795 g neto escurrido%'
    or unidad_formato_compra ilike '% 1795 g neto escurrido%'
  );

-- ============================================================================
-- 3. Unidades evidentes
-- ============================================================================

update public.inventario
set cantidad_formato_compra = 1,
    unidad_formato_compra = 'ud',
    unidad_medida = 'ud'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '1 ud%' or unidad_formato_compra ilike '% 1 ud%');

update public.inventario
set cantidad_formato_compra = 12,
    unidad_formato_compra = 'ud',
    unidad_medida = 'ud'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '12 uds%' or unidad_formato_compra ilike '% 12 uds%');

-- ============================================================================
-- 4. Correcciones evidentes de unidad_medida a unidad
-- ============================================================================

update public.inventario
set unidad_medida = 'ud'
where unidad_medida = 'kg'
  and (
    unidad_formato_compra = 'ud'
    or formato_compra ilike '%1 ud%'
    or formato_compra ilike '%12 uds%'
    or formato_compra ilike '%unidad%'
  )
  and (
    descripcion ilike '%hamburguesa%'
    or descripcion ilike '%baguette%'
    or descripcion ilike '%chapata%'
    or formato_compra ilike '%hamburguesa%'
    or formato_compra ilike '%baguette%'
    or formato_compra ilike '%chapata%'
  );

-- Conservas en almibar con neto escurrido deben seguir en kg.
update public.inventario
set unidad_medida = 'kg'
where unidad_medida is distinct from 'kg'
  and (
    unidad_formato_compra = 'kg'
    or formato_compra ilike '%neto escurrido%'
    or unidad_formato_compra ilike '%neto escurrido%'
  )
  and (
    descripcion ilike '%almibar%'
    or descripcion ilike '%almíbar%'
    or formato_compra ilike '%almibar%'
    or formato_compra ilike '%almíbar%'
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
