-- Normalizacion de formatos pendientes desde unidad_formato_compra heredada.
--
-- Copia de seguridad recomendada antes de ejecutar:
-- create table if not exists public.inventario_backup_antes_normalizar_pendientes_20260614 as
-- select * from public.inventario;
--
-- Reglas:
-- - No modifica precio_unidad.
-- - No modifica precio_formato_compra.
-- - Solo actua si cantidad_formato_compra esta vacia.
-- - Solo actua si unidad_formato_compra contiene texto no normalizado.

-- ============================================================================
-- 1. Patrones compuestos
-- ============================================================================

-- 35 botellas x 33 cl = 11,55 l.
update public.inventario
set cantidad_formato_compra = 11.55,
    unidad_formato_compra = 'l',
    unidad_medida = 'l'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (
    unidad_formato_compra ilike '35 botellas x 33 cl%'
    or unidad_formato_compra ilike '% 35 botellas x 33 cl%'
  );

-- 20 botellas x 50 cl = 10 l.
update public.inventario
set cantidad_formato_compra = 10,
    unidad_formato_compra = 'l',
    unidad_medida = 'l'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (
    unidad_formato_compra ilike '20 botellas x 50 cl%'
    or unidad_formato_compra ilike '% 20 botellas x 50 cl%'
  );

-- 144 monodosis x 10 ml = 1,44 l.
update public.inventario
set cantidad_formato_compra = 1.44,
    unidad_formato_compra = 'l',
    unidad_medida = 'l'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (
    unidad_formato_compra ilike '144 monodosis x 10 ml%'
    or unidad_formato_compra ilike '% 144 monodosis x 10 ml%'
  );

-- 3 x 50 g = 0,15 kg.
update public.inventario
set cantidad_formato_compra = 0.15,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (
    unidad_formato_compra ilike '3 x 50 g%'
    or unidad_formato_compra ilike '% 3 x 50 g%'
  );

-- 100 sobres x 2 g: se controla por sobre.
update public.inventario
set cantidad_formato_compra = 100,
    unidad_formato_compra = 'sobre',
    unidad_medida = 'sobre'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (
    unidad_formato_compra ilike '100 sobres x 2 g%'
    or unidad_formato_compra ilike '% 100 sobres x 2 g%'
  );

-- ============================================================================
-- 2. Pesos en gramos convertidos a kg
-- ============================================================================

update public.inventario
set cantidad_formato_compra = 0.00036,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '0,36 g%' or unidad_formato_compra ilike '% 0,36 g%');

update public.inventario
set cantidad_formato_compra = 0.045,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '45 g%' or unidad_formato_compra ilike '% 45 g%');

update public.inventario
set cantidad_formato_compra = 0.055,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '55 g%' or unidad_formato_compra ilike '% 55 g%');

update public.inventario
set cantidad_formato_compra = 0.063,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '63 g%' or unidad_formato_compra ilike '% 63 g%');

update public.inventario
set cantidad_formato_compra = 0.100,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '100 g%' or unidad_formato_compra ilike '% 100 g%');

update public.inventario
set cantidad_formato_compra = 0.125,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '125 g%' or unidad_formato_compra ilike '% 125 g%');

update public.inventario
set cantidad_formato_compra = 0.150,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '150 g%' or unidad_formato_compra ilike '% 150 g%');

update public.inventario
set cantidad_formato_compra = 0.160,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '160 g%' or unidad_formato_compra ilike '% 160 g%');

update public.inventario
set cantidad_formato_compra = 0.180,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '180 g%' or unidad_formato_compra ilike '% 180 g%');

update public.inventario
set cantidad_formato_compra = 0.200,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '200 g%' or unidad_formato_compra ilike '% 200 g%');

update public.inventario
set cantidad_formato_compra = 0.225,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '225 g%' or unidad_formato_compra ilike '% 225 g%');

update public.inventario
set cantidad_formato_compra = 0.250,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '250 g%' or unidad_formato_compra ilike '% 250 g%');

update public.inventario
set cantidad_formato_compra = 0.300,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '300 g%' or unidad_formato_compra ilike '% 300 g%');

update public.inventario
set cantidad_formato_compra = 0.350,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '350 g%' or unidad_formato_compra ilike '% 350 g%');

update public.inventario
set cantidad_formato_compra = 0.360,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (
    unidad_formato_compra ilike '360 g%'
    or unidad_formato_compra ilike '% 360 g%'
    or unidad_formato_compra ilike 'aprox. 360 g%'
    or unidad_formato_compra ilike '% aprox. 360 g%'
  );

update public.inventario
set cantidad_formato_compra = 0.400,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '400 g%' or unidad_formato_compra ilike '% 400 g%');

update public.inventario
set cantidad_formato_compra = 0.425,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '425 g%' or unidad_formato_compra ilike '% 425 g%');

update public.inventario
set cantidad_formato_compra = 0.450,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '450 g%' or unidad_formato_compra ilike '% 450 g%');

update public.inventario
set cantidad_formato_compra = 0.500,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '500 g%' or unidad_formato_compra ilike '% 500 g%');

update public.inventario
set cantidad_formato_compra = 0.600,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '600 g%' or unidad_formato_compra ilike '% 600 g%');

update public.inventario
set cantidad_formato_compra = 0.650,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '650 g%' or unidad_formato_compra ilike '% 650 g%');

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

-- ============================================================================
-- 3. Pesos en kilos
-- ============================================================================

update public.inventario
set cantidad_formato_compra = 0.42,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '0,42 kg%' or unidad_formato_compra ilike '% 0,42 kg%');

update public.inventario
set cantidad_formato_compra = 1,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '1 kg%' or unidad_formato_compra ilike '% 1 kg%');

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

update public.inventario
set cantidad_formato_compra = 4.4,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '4,4 kg%' or unidad_formato_compra ilike '% 4,4 kg%');

update public.inventario
set cantidad_formato_compra = 5,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '5 kg%' or unidad_formato_compra ilike '% 5 kg%');

update public.inventario
set cantidad_formato_compra = 25,
    unidad_formato_compra = 'kg',
    unidad_medida = 'kg'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '25 kg%' or unidad_formato_compra ilike '% 25 kg%');

-- ============================================================================
-- 4. Liquidos convertidos a litros
-- ============================================================================

update public.inventario
set cantidad_formato_compra = 0.20,
    unidad_formato_compra = 'l',
    unidad_medida = 'l'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '20 cl%' or unidad_formato_compra ilike '% 20 cl%');

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

update public.inventario
set cantidad_formato_compra = 0.20,
    unidad_formato_compra = 'l',
    unidad_medida = 'l'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '200 ml%' or unidad_formato_compra ilike '% 200 ml%');

update public.inventario
set cantidad_formato_compra = 0.25,
    unidad_formato_compra = 'l',
    unidad_medida = 'l'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '250 ml%' or unidad_formato_compra ilike '% 250 ml%');

update public.inventario
set cantidad_formato_compra = 1,
    unidad_formato_compra = 'l',
    unidad_medida = 'l'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '1 l%' or unidad_formato_compra ilike '% 1 l%');

update public.inventario
set cantidad_formato_compra = 5,
    unidad_formato_compra = 'l',
    unidad_medida = 'l'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '5 l%' or unidad_formato_compra ilike '% 5 l%');

-- ============================================================================
-- 5. Unidades y sobres
-- ============================================================================

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

update public.inventario
set cantidad_formato_compra = 100,
    unidad_formato_compra = 'sobre',
    unidad_medida = 'sobre'
where cantidad_formato_compra is null
  and unidad_formato_compra is not null
  and lower(trim(unidad_formato_compra)) not in ('kg', 'l', 'ud', 'sobre', 'botella', 'lata', 'paquete', 'caja', 'bandeja', 'hoja')
  and (unidad_formato_compra ilike '100 sobres%' or unidad_formato_compra ilike '% 100 sobres%');

-- ============================================================================
-- 6. Comprobaciones posteriores
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
