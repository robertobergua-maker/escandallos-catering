-- Normalizacion segura de cantidad_formato_compra y unidad_formato_compra.
--
-- Recomendacion antes de ejecutar:
-- create table if not exists public.inventario_backup_antes_normalizar_formato_20260614 as
-- select * from public.inventario;
--
-- Reglas:
-- - No modifica precio_unidad.
-- - No modifica precio_formato_compra.
-- - No borra datos.
-- - Evita inferir cantidad en textos con "pieza aprox".
-- - Limpia unidad_formato_compra cuando contiene textos antiguos como "500 g" o "70 cl".

-- ============================================================================
-- 1. Patrones compuestos que deben ejecutarse antes de unidades simples
-- ============================================================================

-- 35 botellas x 33 cl = 11,55 L.
update public.inventario
set cantidad_formato_compra = 11.55,
    unidad_formato_compra = 'l',
    unidad_medida = 'l'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '%35%botellas%x%33%cl%'
    or unidad_formato_compra ilike '%35%botellas%x%33%cl%'
  )
  and coalesce(formato_compra, '') not ilike '%pieza aprox%'
  and coalesce(unidad_formato_compra, '') not ilike '%pieza aprox%';

-- 20 botellas x 50 cl = 10 L.
update public.inventario
set cantidad_formato_compra = 10,
    unidad_formato_compra = 'l',
    unidad_medida = 'l'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '%20%botellas%x%50%cl%'
    or unidad_formato_compra ilike '%20%botellas%x%50%cl%'
  )
  and coalesce(formato_compra, '') not ilike '%pieza aprox%'
  and coalesce(unidad_formato_compra, '') not ilike '%pieza aprox%';

-- 144 monodosis x 10 ml = 1,44 L.
update public.inventario
set cantidad_formato_compra = 1.44,
    unidad_formato_compra = 'l',
    unidad_medida = 'l'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '%144%monodosis%x%10%ml%'
    or unidad_formato_compra ilike '%144%monodosis%x%10%ml%'
  )
  and coalesce(formato_compra, '') not ilike '%pieza aprox%'
  and coalesce(unidad_formato_compra, '') not ilike '%pieza aprox%';

-- 3 x 50 g = 0,15 kg.
update public.inventario
set cantidad_formato_compra = 0.15,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '%3%x%50%g%'
    or unidad_formato_compra ilike '%3%x%50%g%'
  )
  and coalesce(formato_compra, '') not ilike '%pieza aprox%'
  and coalesce(unidad_formato_compra, '') not ilike '%pieza aprox%';

-- ============================================================================
-- 2. Litros y centilitros
-- ============================================================================

-- 33 cl = 0,33 L.
update public.inventario
set cantidad_formato_compra = 0.33,
    unidad_formato_compra = 'l',
    unidad_medida = 'l'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '%33 cl%'
    or unidad_formato_compra ilike '%33 cl%'
  )
  and coalesce(formato_compra, '') not ilike '%pieza aprox%'
  and coalesce(unidad_formato_compra, '') not ilike '%pieza aprox%';

-- 50 cl = 0,50 L.
update public.inventario
set cantidad_formato_compra = 0.50,
    unidad_formato_compra = 'l',
    unidad_medida = 'l'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '%50 cl%'
    or unidad_formato_compra ilike '%50 cl%'
  )
  and coalesce(formato_compra, '') not ilike '%pieza aprox%'
  and coalesce(unidad_formato_compra, '') not ilike '%pieza aprox%';

-- 70 cl = 0,70 L.
update public.inventario
set cantidad_formato_compra = 0.70,
    unidad_formato_compra = 'l',
    unidad_medida = 'l'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '%70 cl%'
    or unidad_formato_compra ilike '%70 cl%'
  )
  and coalesce(formato_compra, '') not ilike '%pieza aprox%'
  and coalesce(unidad_formato_compra, '') not ilike '%pieza aprox%';

-- ============================================================================
-- 3. Gramos convertidos a kilos
-- ============================================================================

-- 20 g = 0,02 kg.
update public.inventario
set cantidad_formato_compra = 0.02,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '%20 g%'
    or unidad_formato_compra ilike '%20 g%'
  )
  and coalesce(formato_compra, '') not ilike '%pieza aprox%'
  and coalesce(unidad_formato_compra, '') not ilike '%pieza aprox%';

-- 125 g = 0,125 kg.
update public.inventario
set cantidad_formato_compra = 0.125,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '%125 g%'
    or unidad_formato_compra ilike '%125 g%'
  )
  and coalesce(formato_compra, '') not ilike '%pieza aprox%'
  and coalesce(unidad_formato_compra, '') not ilike '%pieza aprox%';

-- 150 g = 0,15 kg.
update public.inventario
set cantidad_formato_compra = 0.15,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '%150 g%'
    or unidad_formato_compra ilike '%150 g%'
  )
  and coalesce(formato_compra, '') not ilike '%pieza aprox%'
  and coalesce(unidad_formato_compra, '') not ilike '%pieza aprox%';

-- 200 g = 0,20 kg.
update public.inventario
set cantidad_formato_compra = 0.20,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '%200 g%'
    or unidad_formato_compra ilike '%200 g%'
  )
  and coalesce(formato_compra, '') not ilike '%pieza aprox%'
  and coalesce(unidad_formato_compra, '') not ilike '%pieza aprox%';

-- 250 g = 0,25 kg. Incluye "250 g aprox.".
update public.inventario
set cantidad_formato_compra = 0.25,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '%250 g%'
    or unidad_formato_compra ilike '%250 g%'
  )
  and coalesce(formato_compra, '') not ilike '%pieza aprox%'
  and coalesce(unidad_formato_compra, '') not ilike '%pieza aprox%';

-- 300 g = 0,30 kg.
update public.inventario
set cantidad_formato_compra = 0.30,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '%300 g%'
    or unidad_formato_compra ilike '%300 g%'
  )
  and coalesce(formato_compra, '') not ilike '%pieza aprox%'
  and coalesce(unidad_formato_compra, '') not ilike '%pieza aprox%';

-- 400 g = 0,40 kg.
update public.inventario
set cantidad_formato_compra = 0.40,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '%400 g%'
    or unidad_formato_compra ilike '%400 g%'
  )
  and coalesce(formato_compra, '') not ilike '%pieza aprox%'
  and coalesce(unidad_formato_compra, '') not ilike '%pieza aprox%';

-- 450 g = 0,45 kg.
update public.inventario
set cantidad_formato_compra = 0.45,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '%450 g%'
    or unidad_formato_compra ilike '%450 g%'
  )
  and coalesce(formato_compra, '') not ilike '%pieza aprox%'
  and coalesce(unidad_formato_compra, '') not ilike '%pieza aprox%';

-- 500 g = 0,50 kg.
update public.inventario
set cantidad_formato_compra = 0.50,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '%500 g%'
    or unidad_formato_compra ilike '%500 g%'
  )
  and coalesce(formato_compra, '') not ilike '%pieza aprox%'
  and coalesce(unidad_formato_compra, '') not ilike '%pieza aprox%';

-- 600 g = 0,60 kg.
update public.inventario
set cantidad_formato_compra = 0.60,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '%600 g%'
    or unidad_formato_compra ilike '%600 g%'
  )
  and coalesce(formato_compra, '') not ilike '%pieza aprox%'
  and coalesce(unidad_formato_compra, '') not ilike '%pieza aprox%';

-- ============================================================================
-- 4. Kilos explicitos
-- ============================================================================

-- 1 kg.
update public.inventario
set cantidad_formato_compra = 1,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '%1 kg%'
    or unidad_formato_compra ilike '%1 kg%'
  )
  and coalesce(formato_compra, '') not ilike '%pieza aprox%'
  and coalesce(unidad_formato_compra, '') not ilike '%pieza aprox%';

-- 25 kg.
update public.inventario
set cantidad_formato_compra = 25,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '%25 kg%'
    or unidad_formato_compra ilike '%25 kg%'
  )
  and coalesce(formato_compra, '') not ilike '%pieza aprox%'
  and coalesce(unidad_formato_compra, '') not ilike '%pieza aprox%';

-- ============================================================================
-- 5. Limpieza de unidad_formato_compra textual sin cantidad fiable
-- ============================================================================

-- Si contiene "pieza aprox", no se infiere cantidad. Se deja la unidad pendiente.
update public.inventario
set unidad_formato_compra = null
where (
    formato_compra ilike '%pieza aprox%'
    or unidad_formato_compra ilike '%pieza aprox%'
  )
  and lower(trim(coalesce(unidad_formato_compra, ''))) not in (
    'kg', 'l', 'ud', 'sobre', 'botella', 'lata',
    'paquete', 'caja', 'bandeja', 'hoja'
  );

-- ============================================================================
-- 6. Comprobaciones posteriores
-- ============================================================================

select codigo, descripcion, formato_compra, unidad_medida, cantidad_formato_compra, unidad_formato_compra, precio_unidad, precio_formato_compra
from public.inventario
where nullif(trim(formato_compra), '') is not null
  and cantidad_formato_compra is null
order by descripcion
limit 100;

select codigo, descripcion, formato_compra, unidad_medida, cantidad_formato_compra, unidad_formato_compra, precio_unidad, precio_formato_compra
from public.inventario
where unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
order by descripcion
limit 100;

select codigo, descripcion, formato_compra, unidad_medida, cantidad_formato_compra, unidad_formato_compra, precio_unidad, precio_formato_compra
from public.inventario
where cantidad_formato_compra > 1
  and precio_formato_compra is not null
  and precio_unidad = precio_formato_compra
order by descripcion;
