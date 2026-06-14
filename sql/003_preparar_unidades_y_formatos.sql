-- 1. Productos con formato de compra pero sin cantidad
select codigo, descripcion, formato_compra, precio_unidad, precio_formato_compra
from public.inventario
where nullif(trim(formato_compra), '') is not null
  and cantidad_formato_compra is null
order by descripcion;

-- 2. Propuesta automatica orientativa de unidad base segun descripcion/formato
-- Esta consulta no actualiza datos. Sirve para revisar grupos antes de preparar updates.
select
  codigo,
  descripcion,
  formato_compra,
  unidad_medida,
  unidad_formato_compra,
  case
    when upper(coalesce(descripcion, '') || ' ' || coalesce(formato_compra, '')) similar to '%(ACEITE|LECHE|NATA|AGUA|CALDO|ZUMO|VINO|CERVEZA|LICOR|COCA COLA)%'
      then 'l'
    when upper(coalesce(descripcion, '') || ' ' || coalesce(formato_compra, '')) similar to '%(HUEVO|HUEVOS|MONODOSIS)%'
      then 'ud'
    when upper(coalesce(descripcion, '') || ' ' || coalesce(formato_compra, '')) like '%BOTELLA%'
      then 'botella'
    when upper(coalesce(descripcion, '') || ' ' || coalesce(formato_compra, '')) like '%LATA%'
      then 'lata'
    when upper(coalesce(descripcion, '') || ' ' || coalesce(formato_compra, '')) like '%SOBRE%'
      then 'sobre'
    when upper(coalesce(descripcion, '') || ' ' || coalesce(formato_compra, '')) similar to '%(BANDEJA|CAJA|PAQUETE)%'
      then 'revisar manualmente'
    else 'kg'
  end as unidad_medida_propuesta
from public.inventario
order by unidad_medida_propuesta, descripcion;

-- 3. Formatos que parecen contener litros, mililitros o centilitros
select codigo, descripcion, formato_compra, unidad_medida, unidad_formato_compra
from public.inventario
where formato_compra like '% L%'
   or formato_compra like '%L %'
   or formato_compra like '%ml%'
   or formato_compra like '%ML%'
   or formato_compra like '%cl%'
   or formato_compra like '%CL%'
order by descripcion;

-- 4. Formatos que parecen contener kilos o gramos
select codigo, descripcion, formato_compra, unidad_medida, unidad_formato_compra
from public.inventario
where formato_compra like '%kg%'
   or formato_compra like '%KG%'
   or formato_compra like '%g%'
   or formato_compra like '%GR%'
   or formato_compra like '%gr%'
   or lower(formato_compra) like '%gramos%'
order by descripcion;

-- 5. Formatos que parecen contener unidades
select codigo, descripcion, formato_compra, unidad_medida, unidad_formato_compra
from public.inventario
where lower(formato_compra) like '%ud%'
   or lower(formato_compra) like '%uds%'
   or lower(formato_compra) like '%unidad%'
   or lower(formato_compra) like '%unidades%'
   or lower(formato_compra) like '%x %'
   or lower(formato_compra) like '%docena%'
   or lower(formato_compra) like '%monodosis%'
order by descripcion;
