# Migracion de estructura de inventario

Este directorio contiene SQL para ordenar la estructura de precios de `public.inventario` sin ejecutar cambios destructivos.

## 001_migracion_estructura_inventario.sql

La migracion anade, si no existen, las columnas necesarias para separar el precio operativo del escandallo de la trazabilidad del formato comprado:

- `unidad_medida`: unidad base de trabajo del escandallo, por ejemplo `kg`, `l`, `ud`, `sobre` o `botella`.
- `cantidad_formato_compra`: cantidad contenida en el formato comprado.
- `unidad_formato_compra`: unidad del formato comprado.
- `precio_formato_compra`: precio total del formato comprado.

Tambien copia datos antiguos cuando procede:

- `precio_original` se copia a `precio_formato_compra` si este ultimo esta vacio.
- `unidad_original` se copia a `unidad_formato_compra` si este ultimo esta vacio.
- `unidad_medida` se rellena con `kg` cuando esta vacia.

La migracion no borra columnas.

## 002_auditoria_inventario_precios.sql

La auditoria ayuda a detectar productos que necesitan revision despues de la migracion:

- Productos sin unidad base.
- Productos sin precio normalizado util.
- Productos con formato de compra pero sin cantidad.
- Unidades base no reconocidas.
- Posibles precios sin normalizar cuando `precio_unidad` coincide con `precio_formato_compra` y el formato contiene mas de una unidad.

## Criterio funcional

`precio_unidad` debe seguir siendo siempre el precio operativo normalizado usado en los escandallos.

`precio_formato_compra` es solo un dato de trazabilidad del formato comprado y no debe usarse directamente para calcular costes de recetas.

Primero debe ejecutarse `001_migracion_estructura_inventario.sql` y despues `002_auditoria_inventario_precios.sql`.

Todavia no deben eliminarse `precio_original` ni `unidad_original`. Deben conservarse hasta completar la migracion, revisar la auditoria y confirmar que todos los datos fueron interpretados correctamente.
