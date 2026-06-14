# Esquema de recetas y menus

Este documento resume el proposito del esquema definido en `sql/013_crear_base_datos_recetas_y_menus.sql`.

## Tablas creadas

El SQL prepara cuatro tablas nuevas:

- `recetas`: cabecera de cada ficha tecnica de receta.
- `receta_ingredientes`: lineas de escandallo de cada receta.
- `menus`: cabecera de menus o propuestas completas.
- `menu_recetas`: relacion entre menus y recetas incluidas.

## Relaciones

Una receta puede tener muchos ingredientes mediante `receta_ingredientes.receta_id`.

Un menu puede tener muchas recetas mediante `menu_recetas.menu_id`, y cada linea de `menu_recetas` apunta a una receta con `menu_recetas.receta_id`.

Las tablas `recetas` y `menus` incluyen `user_id`, preparado para que mas adelante cada usuario pueda tener sus propias recetas y menus. De momento queda listo para un futuro sistema de usuarios, sin cambiar el funcionamiento actual de la app.

## Recetas

`recetas` guarda la cabecera de la ficha tecnica. Incluye, entre otros datos:

- nombre;
- categoria;
- tipo de plato;
- raciones base;
- costes indirectos;
- margen;
- IVA;
- coste total;
- precio de venta sin IVA y con IVA.

La columna `raciones_base` representa el numero de raciones para el que estan calculadas las cantidades de la receta.

## Escandallo de ingredientes

`receta_ingredientes` guarda el escandallo de cada receta. Cada fila representa un ingrediente o linea de coste e incluye:

- ingrediente;
- cantidad bruta;
- unidad;
- merma;
- cantidad neta;
- precio unidad;
- coste total;
- si el ingrediente es temporal o esta vinculado al inventario.

El campo `codigo_ingrediente` queda preparado para relacionarse con el inventario, pero el SQL aun no crea una clave foranea contra `inventario.codigo`.

## Menus

`menus` y `menu_recetas` quedan preparados para una fase posterior de la app:

- crear menus;
- anadir recetas o platos;
- ajustar raciones;
- calcular costes y precios totales.

`menu_recetas.raciones` permite indicar cuantas raciones de una receta concreta se incluyen en un menu.

## Inventario

El esquema de recetas y menus no modifica `inventario`.

La relacion con ingredientes se mantiene por ahora mediante `codigo_ingrediente`, sin clave foranea contra `inventario.codigo`, para evitar bloquear la carga de ingredientes temporales o pendientes de normalizar.

## Precaucion antes de ejecutar

El SQL `sql/013_crear_base_datos_recetas_y_menus.sql` no debe ejecutarse contra Supabase sin revision previa.

Antes de aplicarlo en un entorno real, conviene revisar nombres de columnas, defaults, indices, triggers y comentarios, y confirmar que encajan con la version actual de la app.

## Futuras funciones de la app

Mas adelante la app podra implementar:

- guardar receta;
- cargar receta;
- actualizar receta;
- duplicar receta;
- crear menu;
- anadir receta al menu;
- calcular coste total del menu;
- separar recetas por usuario.

## Orden recomendado de ejecucion

1. Revisar SQL.
2. Ejecutar SQL en Supabase.
3. Comprobar tablas.
4. Modificar app para guardar/cargar recetas.

## Consulta de comprobacion para Supabase

```sql
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in ('recetas', 'receta_ingredientes', 'menus', 'menu_recetas')
order by table_name;
```
