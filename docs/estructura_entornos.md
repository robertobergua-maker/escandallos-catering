# Estructura de entornos

La navegación principal de la app queda organizada en cinco entornos claros:

## Ingredientes

Agrupa el inventario, la búsqueda de ingredientes, la edición de datos del ingrediente y las altas o actualizaciones de ingredientes cuando ya existen en el inventario.

## Recetas

Agrupa la creación de receta, carga de recetas guardadas, guardado, actualización, duplicado, eliminación, tabla de ingredientes de la receta y herramientas de CIA para recetas.

Las recetas nuevas se guardan siempre dimensionadas a 1 ración. El coste total de la receta se interpreta como coste de esa ración.

Las recetas antiguas pueden tener una base de raciones distinta de 1. Al cargarlas, la app avisa de que pueden necesitar normalización antes de usarlas en menús.

La normalización automática a 1 ración queda pendiente para una fase posterior; por ahora no se dividen cantidades antiguas automáticamente.

## Menús

Agrupa la creación y carga de menús, guardado, actualización, duplicado, recetas incluidas dentro del menú y gestión de raciones o comensales del menú.

## Clientes

Agrupa la creación, listado, edición y eliminación de clientes.

## Facturas

Agrupa presupuestos, facturas, documentos guardados, creación de documentos desde menú y descarga de documentos.
