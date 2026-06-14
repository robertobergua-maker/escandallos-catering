-- 1. Productos con formato de compra pero sin cantidad
select codigo, descripcion, formato_compra, cantidad_formato_compra, precio_formato_compra
from public.inventario
where nullif(trim(formato_compra), '') is not null
  and cantidad_formato_compra is null
order by descripcion;

-- 2. Productos con precio de formato pero sin precio normalizado operativo
select codigo, descripcion, precio_unidad, precio_formato_compra
from public.inventario
where precio_formato_compra is not null
  and (precio_unidad is null or precio_unidad = 0)
order by descripcion;

-- 3. Sospecha de precio sin normalizar
select codigo, descripcion, precio_unidad, cantidad_formato_compra, precio_formato_compra
from public.inventario
where cantidad_formato_compra > 1
  and precio_formato_compra is not null
  and precio_unidad = precio_formato_compra
order by descripcion;

-- 4. Productos con unidad base fuera de lista
select codigo, descripcion, unidad_medida
from public.inventario
where nullif(trim(unidad_medida), '') is not null
  and lower(trim(unidad_medida)) not in (
    'kg', 'g', 'l', 'ml', 'ud', 'sobre', 'botella',
    'lata', 'paquete', 'bandeja', 'caja', 'hoja'
  )
order by descripcion;

-- 5. Productos con unidad de formato fuera de lista
select codigo, descripcion, formato_compra, unidad_formato_compra
from public.inventario
where nullif(trim(unidad_formato_compra), '') is not null
  and lower(trim(unidad_formato_compra)) not in (
    'kg', 'g', 'l', 'ml', 'ud', 'sobre', 'botella',
    'lata', 'paquete', 'bandeja', 'caja', 'hoja'
  )
order by descripcion;
