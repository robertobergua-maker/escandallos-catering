# Estructura de entornos

La navegación principal de la app queda organizada en cinco entornos claros:

## Ingredientes

Agrupa el inventario, la búsqueda de ingredientes, la edición de datos del ingrediente y las altas o actualizaciones de ingredientes cuando ya existen en el inventario.

## Recetas

Agrupa la creación de receta, carga de recetas guardadas, guardado, actualización, duplicado, eliminación, tabla de ingredientes de la receta y herramientas de CIA para recetas.

Las recetas nuevas se guardan siempre dimensionadas a 1 ración. El coste total de la receta se interpreta como coste de esa ración.

Las recetas antiguas pueden tener una base de raciones distinta de 1. Al cargarlas, la app avisa de que pueden necesitar normalización antes de usarlas en menús.

Las recetas antiguas se normalizan mediante copia manual: la app crea una receta nueva a 1 ración dividiendo las cantidades entre la base antigua y no modifica la receta original.

Los menús que usen la receta antigua no se actualizan automáticamente. Si se quiere usar la copia normalizada, debe sustituirse manualmente la receta dentro del menú.

## Menús

Agrupa la creación y carga de menús, guardado, actualización, duplicado, recetas incluidas dentro del menú y gestión de raciones del menú.

Cada menú tiene unas raciones base. Ese valor se guarda en `menus.numero_comensales` por compatibilidad con la estructura actual y se aplica por defecto a las recetas añadidas al menú.

Cada receta incluida en un menú puede tener raciones propias distintas de las raciones base del menú. Esas raciones específicas se guardan en `menu_recetas.raciones`.

Las recetas normalizadas se calculan como 1 ración: el coste y el precio de línea se obtienen multiplicando el coste o precio por ración de la receta por las raciones específicas de esa receta dentro del menú.

## Clientes

Agrupa la creación, listado, edición y eliminación de clientes.

## Facturas

Agrupa presupuestos, facturas, documentos guardados, creación de documentos desde menú y descarga de documentos.

Cada presupuesto o factura debe estar asociado a un cliente mediante `facturas.cliente_id`.

Los documentos pueden crearse desde un menú. Mientras no exista una relación directa en `facturas`, la relación menú-documento se conserva temporalmente en las líneas mediante `factura_lineas.origen_tipo` y `factura_lineas.origen_id`.

Cuando el documento se genera desde menú, las líneas guardan `origen_tipo = "menu"` y `origen_id` con el identificador del menú. Queda pendiente una migración futura para añadir `facturas.menu_id` y representar esta relación de forma directa.
