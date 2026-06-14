-- BORRADOR: revisar resultados antes de ejecutar.
-- Estos updates estan agrupados por patrones evidentes, pero no calculan
-- cantidad_formato_compra de forma automatica.

-- Aceites con formato en litros
/*
update public.inventario
set unidad_medida = 'l',
    unidad_formato_compra = 'l'
where upper(coalesce(descripcion, '') || ' ' || coalesce(formato_compra, '')) like '%ACEITE%'
  and (
    formato_compra like '% L%'
    or formato_compra like '%L %'
    or formato_compra like '%l%'
  );
*/

-- Leche, nata, caldos y bebidas
/*
update public.inventario
set unidad_medida = 'l',
    unidad_formato_compra = 'l'
where upper(coalesce(descripcion, '') || ' ' || coalesce(formato_compra, '')) similar to '%(LECHE|NATA|AGUA|CALDO|ZUMO|VINO|CERVEZA|LICOR|COCA COLA)%';
*/

-- Harinas, arroz, azucar, frutos secos, carnes, pescados y verduras
/*
update public.inventario
set unidad_medida = 'kg',
    unidad_formato_compra = 'kg'
where upper(coalesce(descripcion, '') || ' ' || coalesce(formato_compra, '')) similar to '%(HARINA|ARROZ|AZUCAR|AZÚCAR|FRUTO SECO|ALMENDRA|NUEZ|CARNE|POLLO|TERNERA|CERDO|PESCADO|MERLUZA|SALMON|SALMÓN|VERDURA|PATATA|CEBOLLA|TOMATE|PIMIENTO)%';
*/

-- Huevos
/*
update public.inventario
set unidad_medida = 'ud',
    unidad_formato_compra = 'ud'
where upper(coalesce(descripcion, '') || ' ' || coalesce(formato_compra, '')) similar to '%(HUEVO|HUEVOS|DOCENA)%';
*/

-- Monodosis
/*
update public.inventario
set unidad_medida = 'ud',
    unidad_formato_compra = 'ud'
where upper(coalesce(descripcion, '') || ' ' || coalesce(formato_compra, '')) like '%MONODOSIS%';
*/

-- Sobres cuando el producto se trabaja por sobre
/*
update public.inventario
set unidad_medida = 'sobre',
    unidad_formato_compra = 'ud'
where upper(coalesce(descripcion, '') || ' ' || coalesce(formato_compra, '')) like '%SOBRE%';
*/

-- Antes de ejecutar cualquier bloque:
-- 1. Convertir el update en select con las mismas condiciones.
-- 2. Revisar los productos afectados.
-- 3. Ejecutar solo el bloque validado.
-- 4. Pasar despues sql/005_auditoria_post_unidades_formatos.sql.
