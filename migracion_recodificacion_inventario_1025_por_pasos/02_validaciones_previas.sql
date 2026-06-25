-- PASO 2: Validaciones previas.
-- Todas estas consultas deben devolver 0 filas.
-- Si devuelven algo, NO ejecutes el paso 3 y pásame el resultado.

-- 3) Validaciones previas.
-- Debe devolver 0 filas: códigos nuevos duplicados en el mapeo.
select codigo_nuevo, count(*) as veces
from public.tmp_recodificacion_inventario
group by codigo_nuevo
having count(*) > 1;

-- Debe devolver 0 filas: códigos actuales del mapeo que no existen en inventario.
select m.codigo_actual
from public.tmp_recodificacion_inventario m
left join public.inventario i on i.codigo = m.codigo_actual
where i.codigo is null;

-- Debe devolver 0 filas: códigos nuevos que ya existen en inventario y no son el mismo registro.
select m.codigo_actual, m.codigo_nuevo
from public.tmp_recodificacion_inventario m
join public.inventario i on i.codigo = m.codigo_nuevo
where m.codigo_actual <> m.codigo_nuevo;

