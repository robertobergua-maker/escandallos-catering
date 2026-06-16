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

Agrupa la creación y carga de menús, guardado, actualización, duplicado, recetas incluidas dentro del menú y gestión de raciones del menú.

Cada menú tiene unas raciones base. Ese valor se guarda en `menus.numero_comensales` por compatibilidad con la estructura actual y se aplica por defecto a las recetas añadidas al menú.

Cada receta incluida en un menú puede tener raciones propias distintas de las raciones base del menú. Esas raciones específicas se guardan en `menu_recetas.raciones`.

Las recetas normalizadas se calculan como 1 ración: el coste y el precio de línea se obtienen multiplicando el coste o precio por ración de la receta por las raciones específicas de esa receta dentro del menú.

## Clientes

Agrupa la creación, listado, edición y eliminación de clientes.

## Facturas

Agrupa presupuestos, facturas, documentos guardados, creación de documentos desde menú y descarga de documentos.
