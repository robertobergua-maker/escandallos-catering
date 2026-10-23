# Tarea: manual de usuario del Gestor de Escandallos (Word + PowerPoint)

Lee primero `CLAUDE.md` (normas del proyecto) y este fichero completo.

## Objetivo
Crear dos documentos en español que expliquen cómo usar la app a los roles **Chef** y **Gerente**
(no incluir Administración ni nada técnico de despliegue o base de datos):
1. `docs/manual/Manual_Gestor_Escandallos.docx` — manual completo, paso a paso.
2. `docs/manual/Manual_Gestor_Escandallos.pptx` — versión de formación, visual (1 captura + 3-5 puntos por diapositiva).

## Material
- Capturas reales en `docs/manual/capturas/` (nombres y contenido en `docs/manual/CAPTURAS.md`;
  las notas al final de ese fichero indican capturas que faltan o son distintas).
- El código (`generador_fichas.py`) para confirmar textos de botones, reglas y permisos. No inventes
  funciones: si algo no se ve en las capturas ni en el código, no lo documentes.

## Estructura del Word
1. Portada (título, "Samirarte", versión y fecha) e índice.
2. Introducción: qué es la app; organizaciones; roles Chef y Gerente (tabla de qué puede hacer cada uno).
3. Acceso: entrar, recuperar contraseña, canjear invitación, cambiar de organización activa.
4. Recetas: crear, ingredientes, costes/PVP/Food Cost, alérgenos, IA, parámetros, guardar/cargar, ficha técnica,
   recetas compartidas con mi organización.
5. Menús. 6. Clientes.
7. Presupuestos y facturas: borrador → emitir (solo gerente) → PDF → cobrado; numeración
   FAC/REC/PRE-AAAA-NNNN; documentos emitidos inmutables; rectificativa; anular presupuesto.
8. Funciones del gerente: miembros e invitaciones, datos de la organización y logo, inventario propio
   (precios propios, ingredientes privados), compartir recetas.
9. Preguntas frecuentes y avisos.

Avisos obligatorios (en un recuadro destacado):
- Alérgenos: la app ayuda pero la responsabilidad final es del establecimiento; revisar etiquetas;
  ingredientes privados y recetas copiadas requieren revisión de alérgenos.
- Facturación: la app no está certificada VERI*FACTU; consultar con la gestoría antes de usarla como sistema fiscal.

## Estilo
- Tono claro y cercano, segunda persona ("pulsa…", "verás…"). Frases cortas.
- Cada procedimiento: pasos numerados + captura con pie de figura.
- Marca con una etiqueta "Solo gerente" lo que no puede hacer el chef.
- Colores sobrios (dorado/marrón de la marca Samirarte, ver `assets/`), tipografía legible.

## Normas
- Trabaja en la rama `manual-usuario` (ya existe y contiene las capturas). Commit y push de esa rama. NUNCA a main.
- No toques el código de la app ni la carpeta `sql/`.
- Al terminar: abre los dos ficheros generados y revísalos (renderiza páginas/diapositivas a imagen y compruébalas),
  y dame un resumen con lo que falte o no estuviera claro.

## Capturas que faltan (importante)
- Algunas capturas aún no existen (ver la sección "Notas" al final de CAPTURAS.md). Donde falte una, deja en el
  Word un recuadro gris "[Captura pendiente: NN – descripción]" y en el PowerPoint un marcador equivalente,
  para sustituirlas más adelante sin rehacer el documento.
- Pendientes ahora: 00, 01, 02 (acceso sin sesión), 10, 11, 50, 51 (chef), 17c, 17d (IA con imagen),
  22b (Excel), 23 (recetas compartidas), 64 (PDF), 67 (rectificativa).
- Ignora `error-rectificativa.png`: es un informe de fallo, no va en el manual.
- Las capturas tienen ~720-800 px de ancho: insértalas a un ancho máximo de 15 cm en Word y sin ampliarlas por
  encima de su tamaño en el PowerPoint, para que no se pixelen.
- No describas como funciones del manual cosas que en las capturas aparecen como error o en estado raro.
- Organización de ejemplo de las capturas: "Demo" (datos inventados). Úsala en los textos de ejemplo.
