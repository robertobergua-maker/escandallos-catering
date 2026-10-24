# Actualización del manual — 028 «Recetas por chef» (24/10/2026)

En producción desde el 24/10/2026: main 100382b (ramas recetas-por-chef + mejoras-028).
Hay que actualizar el Word y el PowerPoint (rama `manual-usuario`, `docs/manual/`).
No rehacer el manual: añadir las secciones nuevas y corregir los textos indicados.

## Capturas nuevas (docs/manual/capturas/)

| Archivo | Rol | Qué muestra |
|---|---|---|
| 24a-chef-recetas-solo-lectura.png | Chef | Desplegable «Recetas guardadas» con recetas marcadas «de otro chef (solo lectura)» |
| 24b-chef-receta-solo-lectura.png | Chef | Receta de otro chef cargada: aviso de solo lectura y «Actualizar receta» en gris |
| 72b-invitar-desde-archivo.png | Gerente | Miembros e invitaciones → Invitaciones → «Invitar chefs desde un archivo» |
| 79a-recetas-chefs-conceder.png | Gerente | Recetas de chefs → Conceder acceso (formulario relleno de ejemplo) |
| 79b-recetas-chefs-permisos.png | Gerente | Recetas de chefs → Permisos actuales (tabla con «Quitar») |
| 79c-recetas-chefs-propietario.png | Gerente | Recetas de chefs → Propietario de recetas |

## Cambios de contenido

### Manual del chef — sección Recetas (después de «Recetas guardadas», captura 20)
Nuevo apartado **«Qué recetas ves y cuáles puedes modificar»**:
- Cada receta tiene un propietario: el chef que la creó.
- Un chef ve: sus propias recetas; las recetas que están en algún menú de la organización (los menús son de todos); y las recetas a las que el gerente le haya dado acceso.
- En el desplegable, las recetas de otros chefs aparecen como «de otro chef» (con permiso de edición) o «de otro chef (solo lectura)» (captura 24a).
- Al cargar una receta en solo lectura se puede consultar todo (ingredientes, costes, alérgenos, ficha Excel), pero el botón «Actualizar receta» está desactivado (captura 24b).
- Para trabajar sobre ella: «Guardar receta» o «Duplicar receta» crean una copia propia del chef.
- Si necesita modificar la original, debe pedir al gerente permiso de edición.
- Borrar una receta: solo su propietario o el gerente.

### Manual del gerente — nueva sección **«Recetas de chefs»** (después de «Miembros e invitaciones», capturas 79a, 79b, 79c)
Introducción: cada chef ve y edita solo sus recetas; el gerente ve y edita todas y decide qué chefs pueden consultar o editar recetas de otros. Cuando el gerente edita una receta de un chef, la receta sigue siendo de ese chef.

1. **Conceder acceso (79a)**
   - «Chefs que reciben el acceso»: uno o varios chefs.
   - «Acceso a»: «Todas las recetas de estos chefs» (elige propietarios; incluye las recetas que creen en el futuro) o «Recetas concretas».
   - «Permiso»: «Solo lectura» o «Lectura y edición».
   - Botón «Conceder acceso». Si ya existía el permiso, se actualiza el nivel.
2. **Permisos actuales (79b)**: tabla con chef, a qué tiene acceso y el permiso. Marcar «Quitar» y pulsar «Quitar seleccionados».
3. **Propietario de recetas (79c)**: cambiar el propietario de una o varias recetas. Casilla «Mostrar solo recetas sin propietario» para localizar recetas antiguas sin dueño (solo las ve el gerente, salvo que estén en un menú). Elegir recetas, «Nuevo propietario» y «Asignar propietario».

La pantalla se queda en el apartado en el que estabas después de cada acción.

### Manual del gerente — «Miembros e invitaciones» (después de captura 72)
Nuevo apartado **«Invitar chefs desde un archivo» (72b)**: subir un CSV o Excel con una columna «email» (un chef por fila). Se crea una invitación de chef por cada email válido y se pueden descargar los códigos. Botón «Descargar plantilla CSV» para tener el formato.

### Correcciones de texto
- Quitar cualquier frase que diga que todos los miembros ven y editan todas las recetas de la organización (el modelo ahora es por chef, ver arriba).
- La barra de pestañas del gerente es ahora: Miembros e invitaciones · **Recetas de chefs** · Datos de la organización · Inventario propio · Compartir recetas.
- La barra lateral ya no muestra el consejo «el inventario común se gestiona desde Administración…». Si el manual lo menciona, quitarlo. Las capturas antiguas que aún lo muestran se pueden mantener.
