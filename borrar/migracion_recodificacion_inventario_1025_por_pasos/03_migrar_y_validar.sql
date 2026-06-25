-- PASO 3: Migración y validaciones finales.
-- Ejecuta solo si el paso 1 creó 1025 filas de mapeo y el paso 2 no devolvió incidencias.
-- La tabla public.tmp_recodificacion_inventario NO se borra al final para poder auditar.

-- 4) Insertar clones con el código nuevo.
-- Esto evita errores si receta_ingredientes tiene FK hacia inventario.codigo sin ON UPDATE CASCADE.
insert into public.inventario (
    codigo,
    familia,
    descripcion,
    merma,
    precio_unidad,
    proveedor_precio,
    formato_compra,
    precio_original,
    unidad_original,
    fecha_precio,
    url_precio,
    observaciones_precio,
    unidad_medida,
    cantidad_formato_compra,
    unidad_formato_compra,
    precio_formato_compra
)
select
    m.codigo_nuevo as codigo,
    coalesce(nullif(m.familia_nombre_nueva, ''), i.familia) as familia,
    i.descripcion,
    i.merma,
    i.precio_unidad,
    i.proveedor_precio,
    i.formato_compra,
    i.precio_original,
    i.unidad_original,
    i.fecha_precio,
    i.url_precio,
    i.observaciones_precio,
    i.unidad_medida,
    i.cantidad_formato_compra,
    i.unidad_formato_compra,
    i.precio_formato_compra
from public.inventario i
join public.tmp_recodificacion_inventario m on m.codigo_actual = i.codigo
where not exists (
    select 1
    from public.inventario destino
    where destino.codigo = m.codigo_nuevo
);

-- 5) Actualizar referencias de recetas a los códigos nuevos.
update public.receta_ingredientes ri
set codigo_ingrediente = m.codigo_nuevo
from public.tmp_recodificacion_inventario m
where ri.codigo_ingrediente = m.codigo_actual;

-- 6) Borrar códigos antiguos de inventario ya migrados.
-- Solo borra antiguos que tienen clon nuevo y que ya no están referenciados.
delete from public.inventario i
using public.tmp_recodificacion_inventario m
where i.codigo = m.codigo_actual
  and exists (
      select 1
      from public.inventario nuevo
      where nuevo.codigo = m.codigo_nuevo
  )
  and not exists (
      select 1
      from public.receta_ingredientes ri
      where ri.codigo_ingrediente = i.codigo
  );

-- 7) Validaciones posteriores.
-- Debe devolver 0 filas: receta_ingredientes con código que no existe en inventario.
select ri.codigo_ingrediente, count(*) as lineas
from public.receta_ingredientes ri
left join public.inventario i on i.codigo = ri.codigo_ingrediente
where ri.codigo_ingrediente is not null
  and ri.codigo_ingrediente <> ''
  and i.codigo is null
group by ri.codigo_ingrediente
order by ri.codigo_ingrediente;

-- Debe devolver 1025: registros de inventario después de migrar.
select count(*) as total_inventario
from public.inventario;

-- Debe devolver 0: códigos antiguos que siguen existiendo en inventario.
select count(*) as codigos_antiguos_restantes
from public.inventario i
join public.tmp_recodificacion_inventario m on m.codigo_actual = i.codigo;

-- Debe devolver el total de líneas de receta: 28 según el CSV aportado.
select count(*) as total_receta_ingredientes
from public.receta_ingredientes;



-- Cuando hayas comprobado todo, podrás borrar la tabla auxiliar con:
-- drop table if exists public.tmp_recodificacion_inventario;
