-- Normalizacion extra de formatos pendientes desde unidad_formato_compra/formato_compra.
--
-- Copia de seguridad recomendada antes de ejecutar:
-- create table if not exists public.inventario_backup_antes_normalizar_extra_20260614 as
-- select * from public.inventario;
--
-- Reglas:
-- - No modifica precio_unidad.
-- - No modifica precio_formato_compra.
-- - Solo actua si cantidad_formato_compra esta vacia.
-- - No toca filas con unidad_formato_compra ya normalizada.

-- ============================================================================
-- 1. Limpieza de textos no cuantificables
-- ============================================================================

update public.inventario
set unidad_formato_compra = null
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (
    unidad_formato_compra ilike '%€/kg%'
    or unidad_formato_compra ilike '%pieza precio aprox%'
    or unidad_formato_compra ilike '%pieza aprox%'
  );

-- ============================================================================
-- 2. Liquidos
-- ============================================================================

-- 24 botellas x 25 cl = 6 l.
update public.inventario
set cantidad_formato_compra = 6,
    unidad_formato_compra = 'l',
    unidad_medida = 'l'
where cantidad_formato_compra is null
  and (
    unidad_formato_compra is null
    or lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  )
  and (
    unidad_formato_compra ilike '24 botellas x 25 cl%'
    or unidad_formato_compra ilike '% 24 botellas x 25 cl%'
    or formato_compra ilike '24 botellas x 25 cl%'
    or formato_compra ilike '% 24 botellas x 25 cl%'
  );

update public.inventario
set cantidad_formato_compra = 0.20,
    unidad_formato_compra = 'l',
    unidad_medida = 'l'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '20 cl%' or unidad_formato_compra ilike '% 20 cl%');

update public.inventario
set cantidad_formato_compra = 0.25,
    unidad_formato_compra = 'l',
    unidad_medida = 'l'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '25 cl%' or unidad_formato_compra ilike '% 25 cl%');

update public.inventario
set cantidad_formato_compra = 0.33,
    unidad_formato_compra = 'l',
    unidad_medida = 'l'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '33 cl%' or unidad_formato_compra ilike '% 33 cl%');

update public.inventario
set cantidad_formato_compra = 0.50,
    unidad_formato_compra = 'l',
    unidad_medida = 'l'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '50 cl%' or unidad_formato_compra ilike '% 50 cl%');

update public.inventario
set cantidad_formato_compra = 0.70,
    unidad_formato_compra = 'l',
    unidad_medida = 'l'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '70 cl%' or unidad_formato_compra ilike '% 70 cl%');

-- ============================================================================
-- 3. Pesos
-- ============================================================================

update public.inventario
set cantidad_formato_compra = 0.038,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '38 g%' or unidad_formato_compra ilike '% 38 g%');

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
set cantidad_formato_compra = 0.100,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '100 g%' or unidad_formato_compra ilike '% 100 g%');

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
set cantidad_formato_compra = 0.330,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (
    unidad_formato_compra ilike '330 g%'
    or unidad_formato_compra ilike '% 330 g%'
    or unidad_formato_compra ilike 'aprox. 330 g%'
    or unidad_formato_compra ilike '% aprox. 330 g%'
  );

update public.inventario
set cantidad_formato_compra = 0.750,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '750 g%' or unidad_formato_compra ilike '% 750 g%');

update public.inventario
set cantidad_formato_compra = 0.800,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '800 g%' or unidad_formato_compra ilike '% 800 g%');

update public.inventario
set cantidad_formato_compra = 0.850,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '850 g%' or unidad_formato_compra ilike '% 850 g%');

update public.inventario
set cantidad_formato_compra = 2.5,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '2,5 kg%' or unidad_formato_compra ilike '% 2,5 kg%');

update public.inventario
set cantidad_formato_compra = 1.6,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '1,6 kg%' or unidad_formato_compra ilike '% 1,6 kg%');

update public.inventario
set cantidad_formato_compra = 1.8,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '1,8 kg%' or unidad_formato_compra ilike '% 1,8 kg%');

update public.inventario
set cantidad_formato_compra = 2,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '2 kg%' or unidad_formato_compra ilike '% 2 kg%');

-- ============================================================================
-- 4. Sobres y unidades
-- ============================================================================

update public.inventario
set cantidad_formato_compra = 150,
    unidad_formato_compra = 'sobre',
    unidad_medida = 'sobre'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '150 sobres%' or unidad_formato_compra ilike '% 150 sobres%');

update public.inventario
set cantidad_formato_compra = 100,
    unidad_formato_compra = 'sobre',
    unidad_medida = 'sobre'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '100 sobres%' or unidad_formato_compra ilike '% 100 sobres%');

update public.inventario
set cantidad_formato_compra = 600,
    unidad_formato_compra = 'ud',
    unidad_medida = 'ud'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '600 uds%' or unidad_formato_compra ilike '% 600 uds%');

update public.inventario
set cantidad_formato_compra = 1000,
    unidad_formato_compra = 'ud',
    unidad_medida = 'ud'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '1000 uds%' or unidad_formato_compra ilike '% 1000 uds%');

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
