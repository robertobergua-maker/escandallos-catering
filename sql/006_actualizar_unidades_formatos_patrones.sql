-- Migracion de apoyo para completar unidades y cantidades de formato por patrones evidentes.
--
-- Recomendacion antes de ejecutar:
-- create table public.inventario_backup_antes_unidades as
-- select * from public.inventario;
--
-- Regla fundamental:
-- precio_unidad NO se modifica en este archivo. Es el precio operativo normalizado del escandallo.

-- ============================================================================
-- 1. Unidades base de trabajo
-- ============================================================================

-- Aceites: se trabajan por litro.
update public.inventario
set unidad_medida = 'l'
where unidad_medida is distinct from 'l'
  and (
    descripcion ilike '%aceite%'
    or formato_compra ilike '%aceite%'
  );

-- Liquidos y bebidas: se trabajan por litro.
update public.inventario
set unidad_medida = 'l'
where unidad_medida is distinct from 'l'
  and (
    descripcion ilike '%leche%'
    or descripcion ilike '%nata%'
    or descripcion ilike '%caldo%'
    or descripcion ilike 'agua %'
    or descripcion ilike '% agua %'
    or descripcion ilike '% agua'
    or descripcion ilike '%zumo%'
    or descripcion ilike '%vino%'
    or descripcion ilike '%cerveza%'
    or descripcion ilike '%licor%'
    or descripcion ilike '%bebida%'
    or descripcion ilike '%coca cola%'
    or formato_compra ilike '%leche%'
    or formato_compra ilike '%nata%'
    or formato_compra ilike '%caldo%'
    or formato_compra ilike 'agua %'
    or formato_compra ilike '% agua %'
    or formato_compra ilike '% agua'
    or formato_compra ilike '%zumo%'
    or formato_compra ilike '%vino%'
    or formato_compra ilike '%cerveza%'
    or formato_compra ilike '%licor%'
    or formato_compra ilike '%bebida%'
    or formato_compra ilike '%coca cola%'
  );

-- Huevos: se trabajan por unidad.
update public.inventario
set unidad_medida = 'ud'
where unidad_medida is distinct from 'ud'
  and (
    descripcion ilike '%huevo%'
    or descripcion ilike '%huevos%'
    or formato_compra ilike '%huevo%'
    or formato_compra ilike '%huevos%'
    or formato_compra ilike '%docena%'
  );

-- Monodosis: se trabajan por unidad salvo casos liquidos convertidos explicitamente mas abajo.
update public.inventario
set unidad_medida = 'ud'
where unidad_medida is distinct from 'ud'
  and (
    descripcion ilike '%monodosis%'
    or formato_compra ilike '%monodosis%'
  );

-- Sobres: se trabajan por sobre.
update public.inventario
set unidad_medida = 'sobre'
where unidad_medida is distinct from 'sobre'
  and (
    descripcion ilike '%sobre%'
    or formato_compra ilike '%sobre%'
  );

-- Botellas o latas individuales cuando el producto se controla por unidad.
update public.inventario
set unidad_medida = 'ud'
where unidad_medida is distinct from 'ud'
  and (
    descripcion ilike '%botella%'
    or descripcion ilike '%lata%'
  )
  and not (
    descripcion ilike '%aceite%'
    or descripcion ilike '%leche%'
    or descripcion ilike '%nata%'
    or descripcion ilike '%caldo%'
    or descripcion ilike 'agua %'
    or descripcion ilike '% agua %'
    or descripcion ilike '% agua'
    or descripcion ilike '%zumo%'
    or descripcion ilike '%vino%'
    or descripcion ilike '%cerveza%'
    or descripcion ilike '%licor%'
    or descripcion ilike '%bebida%'
    or descripcion ilike '%coca cola%'
  );

-- ============================================================================
-- 2. Cantidad y unidad del formato de compra por patrones evidentes
-- ============================================================================

-- Caso prioritario: 144 monodosis x 10 ml = 1,44 L.
update public.inventario
set cantidad_formato_compra = 1.44,
    unidad_formato_compra = 'l',
    unidad_medida = 'l'
where cantidad_formato_compra is null
  and formato_compra ilike '%144%monodosis%x%10%ml%';

-- Litros explicitos.
update public.inventario
set cantidad_formato_compra = 0.37,
    unidad_formato_compra = 'l'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '%0,37 l%'
    or formato_compra ilike '%0.37 l%'
  );

update public.inventario
set cantidad_formato_compra = 1,
    unidad_formato_compra = 'l'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '% 1 l%'
    or formato_compra ilike '% 1l%'
    or formato_compra ilike '%1 l %'
  );

update public.inventario
set cantidad_formato_compra = 5,
    unidad_formato_compra = 'l'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '% 5 l%'
    or formato_compra ilike '% 5l%'
    or formato_compra ilike '%5 l %'
  );

-- Mililitros y centilitros convertidos a litros.
update public.inventario
set cantidad_formato_compra = 0.15,
    unidad_formato_compra = 'l'
where cantidad_formato_compra is null
  and formato_compra ilike '%150 ml%';

update public.inventario
set cantidad_formato_compra = 0.20,
    unidad_formato_compra = 'l'
where cantidad_formato_compra is null
  and formato_compra ilike '%200 ml%';

update public.inventario
set cantidad_formato_compra = 0.25,
    unidad_formato_compra = 'l'
where cantidad_formato_compra is null
  and formato_compra ilike '%250 ml%';

-- Gramos convertidos a kilos.
update public.inventario
set cantidad_formato_compra = 0.15,
    unidad_formato_compra = 'kg'
where cantidad_formato_compra is null
  and formato_compra ilike '%150 g%';

update public.inventario
set cantidad_formato_compra = 0.30,
    unidad_formato_compra = 'kg'
where cantidad_formato_compra is null
  and formato_compra ilike '%300 g%';

update public.inventario
set cantidad_formato_compra = 0.40,
    unidad_formato_compra = 'kg'
where cantidad_formato_compra is null
  and formato_compra ilike '%400 g%';

update public.inventario
set cantidad_formato_compra = 0.45,
    unidad_formato_compra = 'kg'
where cantidad_formato_compra is null
  and formato_compra ilike '%450 g%';

update public.inventario
set cantidad_formato_compra = 0.60,
    unidad_formato_compra = 'kg'
where cantidad_formato_compra is null
  and formato_compra ilike '%600 g%';

-- Kilos explicitos.
update public.inventario
set cantidad_formato_compra = 1,
    unidad_formato_compra = 'kg'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '% 1 kg%'
    or formato_compra ilike '% 1kg%'
    or formato_compra ilike '%1 kg %'
  );

update public.inventario
set cantidad_formato_compra = 25,
    unidad_formato_compra = 'kg'
where cantidad_formato_compra is null
  and (
    formato_compra ilike '% 25 kg%'
    or formato_compra ilike '% 25kg%'
    or formato_compra ilike '%25 kg %'
  );

-- ============================================================================
-- 3. Comprobaciones posteriores
-- ============================================================================

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
