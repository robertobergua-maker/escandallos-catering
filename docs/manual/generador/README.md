# Generador del manual de usuario

Genera `docs/manual/Manual_Gestor_Escandallos.docx` (manual completo) y
`docs/manual/Manual_Gestor_Escandallos.pptx` (formación) a partir de las capturas
de `docs/manual/capturas/`.

## Sustituir una captura pendiente

1. Guarda la captura en `docs/manual/capturas/` con el nombre exacto que aparece
   en el recuadro gris (por ejemplo `64-pdf-presupuesto.png`).
2. Si la figura estaba en `REHACER` (`figuras.js`), quítala de esa lista.
3. Vuelve a generar (abajo). El recuadro se sustituye por la imagen.

## Generar

Requisitos: Python 3 con Pillow, Node.js 18+, y para el índice LibreOffice y
`pdftotext` (poppler).

```bash
cd docs/manual/generador
npm install                      # docx y pptxgenjs
python3 preparar_imagenes.py     # recortes y datos ocultos -> _build/img
node manual_docx.js              # Word
python3 rellenar_indice.py ../Manual_Gestor_Escandallos.docx   # opcional: índice ya relleno
node manual_pptx.js              # PowerPoint
```

Sin el paso del índice, Word lo rellena al abrir el fichero (pregunta si quieres
actualizar los campos: responde que sí).

## Ficheros

- `figuras.js`: catálogo de figuras (nombre de fichero y descripción) y lista `REHACER`.
- `preparar_imagenes.py`: recortes (Word y PowerPoint) y zonas ocultas, como el código de invitación de la captura 72.
- `manual_docx.js` / `manual_pptx.js`: textos y maquetación.
