// Genera docs/manual/Manual_Gestor_Escandallos.docx
// Uso: ver README.md de esta carpeta.

const fs = require("fs");
const path = require("path");
const {
  AlignmentType, BorderStyle, Document, Footer, Header, HeadingLevel, ImageRun,
  LevelFormat, PageBreak, PageNumber, Packer, Paragraph, ShadingType, Table,
  TableCell, TableOfContents, TableRow, TextRun, VerticalAlign, WidthType,
} = require("docx");
const { figura, tamPng, IMG_DIR } = require("./figuras");

const VERSION = "1.0";
const FECHA = "Octubre de 2026";
const SALIDA = path.resolve(__dirname, "..", "Manual_Gestor_Escandallos.docx");

// Marca Samirarte
const MARRON = "5C3A21";
const DORADO = "B8904F";
const DORADO_CLARO = "F6EEDF";
const TEXTO = "2B2B2B";
const GRIS = "6B6B6B";

const ANCHO = 9638; // A4 con márgenes de 2 cm, en DXA
const CM_PX = 37.8; // píxeles (96 ppp) por centímetro

// ── Texto con **negrita** ───────────────────────────────────────────────
function runs(texto, base = {}) {
  const partes = String(texto).split(/(\*\*.+?\*\*)/g).filter(Boolean);
  return partes.map((p) =>
    p.startsWith("**")
      ? new TextRun({ ...base, text: p.slice(2, -2), bold: true })
      : new TextRun({ ...base, text: p })
  );
}

function etiquetaGerente() {
  return new TextRun({
    text: " SOLO GERENTE ",
    bold: true,
    size: 16,
    color: "FFFFFF",
    shading: { type: ShadingType.CLEAR, color: "auto", fill: MARRON },
  });
}

const H1 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_1, pageBreakBefore: true, children: [new TextRun(t)] });
const H2 = (t, gerente = false) =>
  new Paragraph({
    heading: HeadingLevel.HEADING_2,
    children: gerente ? [new TextRun(t + "  "), etiquetaGerente()] : [new TextRun(t)],
  });
const H3 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_3, children: [new TextRun(t)] });
const P = (t) => new Paragraph({ children: runs(t), spacing: { after: 120 } });
const PG = (t) =>
  new Paragraph({ children: [etiquetaGerente(), new TextRun("  "), ...runs(t)], spacing: { after: 120 } });

let instanciaPasos = 0;
function pasos(lista) {
  instanciaPasos += 1;
  const inst = instanciaPasos;
  return lista.map(
    (t) => new Paragraph({ numbering: { reference: "pasos", level: 0, instance: inst }, children: runs(t), spacing: { after: 60 } })
  );
}
const vinetas = (lista) =>
  lista.map((t) => new Paragraph({ numbering: { reference: "vinetas", level: 0 }, children: runs(t), spacing: { after: 60 } }));

// ── Figuras ──────────────────────────────────────────────────────────────
let numFigura = 0;
function fig(id, pie) {
  numFigura += 1;
  const f = figura(id);
  const piePar = new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { after: 240 },
    keepLines: true,
    children: [
      new TextRun({ text: `Figura ${numFigura}. `, bold: true, italics: true, size: 18, color: GRIS }),
      new TextRun({ text: pie || f.desc, italics: true, size: 18, color: GRIS }),
    ],
  });
  if (f.pendiente) {
    const texto = `[Captura pendiente: ${id} – ${f.desc}]`;
    const celda = new TableCell({
      width: { size: 7200, type: WidthType.DXA },
      shading: { type: ShadingType.CLEAR, color: "auto", fill: "E4E4E4" },
      verticalAlign: VerticalAlign.CENTER,
      margins: { top: 500, bottom: 500, left: 300, right: 300 },
      borders: bordes("BDBDBD", 4, BorderStyle.DASHED),
      children: [
        new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text: texto, color: "555555", size: 20 })] }),
        ...(f.nota
          ? [new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text: `(${f.nota})`, color: "777777", size: 16, italics: true })] })]
          : []),
        new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text: `Fichero: docs/manual/capturas/${f.file}`, color: "888888", size: 16 })] }),
      ],
    });
    return [
      new Table({ alignment: AlignmentType.CENTER, columnWidths: [7200], width: { size: 7200, type: WidthType.DXA }, rows: [new TableRow({ cantSplit: true, children: [celda] })] }),
      piePar,
    ];
  }
  const { w, h } = tamPng(f.path);
  const maxW = 15 * CM_PX;
  const maxH = 12 * CM_PX;
  const esc = Math.min(1, maxW / w, maxH / h);
  return [
    new Paragraph({
      alignment: AlignmentType.CENTER,
      keepNext: true,
      spacing: { before: 120, after: 60 },
      children: [
        new ImageRun({
          type: "png",
          data: fs.readFileSync(f.path),
          transformation: { width: Math.round(w * esc), height: Math.round(h * esc) },
          altText: { title: `Figura ${numFigura}`, description: pie || f.desc, name: f.file },
        }),
      ],
    }),
    piePar,
  ];
}

// ── Recuadros ────────────────────────────────────────────────────────────
function bordes(color, size = 8, style = BorderStyle.SINGLE) {
  const b = { style, size, color };
  return { top: b, bottom: b, left: b, right: b };
}

function recuadro(titulo, parrafos, { fill = DORADO_CLARO, borde = DORADO } = {}) {
  const hijos = [
    new Paragraph({ spacing: { after: 100 }, children: [new TextRun({ text: titulo, bold: true, color: MARRON, size: 24, font: "Cambria" })] }),
    ...parrafos.flatMap((p) =>
      Array.isArray(p)
        ? vinetas(p)
        : [new Paragraph({ spacing: { after: 80 }, children: runs(p) })]
    ),
  ];
  return [
    new Table({
      columnWidths: [ANCHO],
      width: { size: ANCHO, type: WidthType.DXA },
      rows: [
        new TableRow({
          cantSplit: true,
          children: [
            new TableCell({
              width: { size: ANCHO, type: WidthType.DXA },
              shading: { type: ShadingType.CLEAR, color: "auto", fill },
              borders: bordes(borde, 12),
              margins: { top: 180, bottom: 180, left: 240, right: 240 },
              children: hijos,
            }),
          ],
        }),
      ],
    }),
    new Paragraph({ spacing: { after: 120 }, children: [] }),
  ];
}

const nota = (t) => recuadro("Ten en cuenta", [t], { fill: "F3F3F3", borde: "C8C8C8" });

function avisosObligatorios() {
  return recuadro("⚠ Avisos importantes", [
    "**Alérgenos.** La app te ayuda a detectar los alérgenos a partir de los ingredientes, pero la responsabilidad final es del establecimiento. Revisa siempre las etiquetas de los productos que compras.",
    [
      "Los **ingredientes privados** llevan los alérgenos que declara tu organización: revísalos con cuidado.",
      "Las **recetas copiadas** de otra organización deben revisarse antes de usarlas: los alérgenos de sus ingredientes privados quedan pendientes de revisión.",
    ],
    "**Facturación.** La app no está certificada VERI*FACTU. Consulta con tu gestoría antes de usarla como sistema fiscal.",
  ], { fill: "FBF3E4", borde: "C0392B" });
}

// ── Tablas ───────────────────────────────────────────────────────────────
function tabla(cabecera, filas, anchos) {
  const celda = (t, esCab, i) =>
    new TableCell({
      width: { size: anchos[i], type: WidthType.DXA },
      shading: esCab ? { type: ShadingType.CLEAR, color: "auto", fill: MARRON } : undefined,
      margins: { top: 80, bottom: 80, left: 120, right: 120 },
      borders: bordes("D9CBB4", 4),
      verticalAlign: VerticalAlign.CENTER,
      children: [
        new Paragraph({
          alignment: i > 0 && t.length <= 16 ? AlignmentType.CENTER : AlignmentType.LEFT,
          children: esCab ? [new TextRun({ text: t, bold: true, color: "FFFFFF" })] : runs(t),
        }),
      ],
    });
  return [
    new Table({
      columnWidths: anchos,
      width: { size: anchos.reduce((a, b) => a + b, 0), type: WidthType.DXA },
      rows: [
        new TableRow({ tableHeader: true, children: cabecera.map((t, i) => celda(t, true, i)) }),
        ...filas.map((f) => new TableRow({ cantSplit: true, children: f.map((t, i) => celda(t, false, i)) })),
      ],
    }),
    new Paragraph({ spacing: { after: 120 }, children: [] }),
  ];
}

// ── Contenido ────────────────────────────────────────────────────────────
function portada() {
  const logo = path.join(IMG_DIR, "logo_fondo_blanco.png");
  return [
    new Paragraph({ spacing: { before: 1200 }, children: [] }),
    ...(fs.existsSync(logo)
      ? [new Paragraph({ alignment: AlignmentType.CENTER, children: [new ImageRun({ type: "png", data: fs.readFileSync(logo), transformation: { width: 260, height: 260 }, altText: { title: "Samirarte", description: "Logotipo de Samirarte", name: "logo" } })] })]
      : []),
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 600, after: 120 }, children: [new TextRun({ text: "Gestor de Escandallos", font: "Cambria", size: 60, bold: true, color: MARRON })] }),
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 600 }, children: [new TextRun({ text: "Manual de usuario para Chef y Gerente", font: "Cambria", size: 32, italics: true, color: DORADO })] }),
    new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text: "Samirarte", bold: true, size: 26, color: TEXTO })] }),
    new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text: `Versión ${VERSION} · ${FECHA}`, size: 22, color: GRIS })] }),
    new Paragraph({ children: [new PageBreak()] }),
    new Paragraph({ spacing: { after: 240 }, children: [new TextRun({ text: "Índice", font: "Cambria", size: 36, bold: true, color: MARRON })] }),
    new TableOfContents("Índice", { hyperlink: true, headingStyleRange: "1-2" }),
  ];
}

function capIntroduccion() {
  return [
    H1("1. Introducción"),
    H2("1.1 Qué es el Gestor de Escandallos"),
    P("El Gestor de Escandallos es una aplicación web para calcular el coste de tus recetas, montar menús, guardar clientes y preparar presupuestos y facturas. Todo en el mismo sitio y siempre con los precios de tu organización."),
    P("Con la app puedes:"),
    ...vinetas([
      "Crear recetas (escandallos) con sus ingredientes, cantidades y mermas, y ver al momento el **coste por ración**, el **PVP por ración** y el **Food Cost**.",
      "Ver los **alérgenos** que aporta cada ingrediente a la receta y al menú.",
      "Rellenar recetas con ayuda de la **inteligencia artificial**, a partir de un texto o de una foto.",
      "Combinar recetas en **menús** y descargar sus fichas técnicas.",
      "Guardar **clientes** y preparar **presupuestos y facturas** a partir de tus menús.",
    ]),
    H2("1.2 Organizaciones"),
    P("La app la usan varias empresas a la vez. Cada empresa es una **organización** y sus datos están separados: nadie de otra organización ve tus recetas, menús, clientes ni documentos."),
    ...vinetas([
      "Todo lo que guardas pertenece a la **organización activa**, no a ti personalmente. Cualquier miembro de tu organización puede verlo y editarlo.",
      "Si perteneces a más de una organización, eliges con cuál trabajas en la barra lateral (apartado 2.5).",
      "Verás el nombre y el logotipo de tu organización en la cabecera de la app. En este manual usamos la organización de ejemplo **Demo**, con datos inventados.",
      "Todas las organizaciones comparten un **catálogo común de ingredientes** con sus precios. El gerente puede poner precios propios y crear ingredientes privados para su organización.",
    ]),
    H2("1.3 Roles: Chef y Gerente"),
    P("Cada persona tiene un rol dentro de la organización. El rol decide qué puede hacer:"),
    ...tabla(
      ["Qué puedes hacer", "Chef", "Gerente"],
      [
        ["Crear, editar y guardar recetas", "Sí", "Sí"],
        ["Usar la IA para rellenar recetas", "Sí", "Sí"],
        ["Descargar fichas técnicas", "Sí", "Sí"],
        ["Crear y guardar menús", "Sí", "Sí"],
        ["Crear y editar clientes", "Sí", "Sí"],
        ["Preparar y guardar borradores de presupuestos y facturas", "Sí", "Sí"],
        ["Descargar el PDF de un documento", "Sí", "Sí"],
        ["Emitir documentos (asignar número definitivo)", "No", "Sí"],
        ["Marcar como cobrado, anular presupuestos y crear rectificativas", "No", "Sí"],
        ["Ver recetas compartidas con la organización", "Sí", "Sí"],
        ["Copiar recetas compartidas y compartir recetas", "No", "Sí"],
        ["Guardar ingredientes en el inventario (ingredientes privados)", "No", "Sí"],
        ["Poner precios propios a ingredientes del catálogo", "No", "Sí"],
        ["Gestionar miembros e invitaciones", "No", "Sí"],
        ["Editar los datos de la organización y el logotipo", "No", "Sí"],
      ],
      [6038, 1800, 1800]
    ),
    H2("1.4 Cómo leer este manual"),
    ...vinetas([
      "Cada tarea se explica con **pasos numerados** y una captura de pantalla.",
      "Los nombres de botones y campos aparecen tal como los verás en la pantalla, por ejemplo **Guardar receta**.",
      "Algunas capturas aún no están disponibles. En su lugar verás un recuadro gris **[Captura pendiente]**.",
    ]),
    new Paragraph({ spacing: { before: 60, after: 120 }, children: [new TextRun("La etiqueta  "), etiquetaGerente(), new TextRun("  marca lo que el chef no puede hacer.")] }),
    ...avisosObligatorios(),
  ];
}

function capAcceso() {
  return [
    H1("2. Acceso a la aplicación"),
    H2("2.1 Entrar"),
    ...pasos([
      "Abre la dirección de la app en tu navegador. Verás la portada del Gestor de Escandallos.",
      "Pulsa **Entrar a la aplicación**.",
      "Elige cómo entrar: pulsa **Entrar con Google**, o escribe tu **Email** y tu **Contraseña** y pulsa **Iniciar sesión**.",
      "Cuando entres, verás en la barra lateral el mensaje **Sesión iniciada** con tu correo.",
    ]),
    ...fig("00"),
    ...fig("01"),
    ...nota("Si todavía no tienes cuenta, puedes crearla con **Crear cuenta**. Para trabajar con los datos de tu empresa necesitarás además una invitación de tu gerente (apartado 2.3). La opción **Continuar como invitado** sirve solo para probar: los cambios no se guardan."),
    H2("2.2 Recuperar la contraseña"),
    ...pasos([
      "En la pantalla de acceso, abre **¿Has olvidado tu contraseña?**.",
      "Escribe el **Email de tu cuenta** y pulsa **Enviar enlace de recuperación**.",
      "Abre el correo que recibirás y pulsa el enlace.",
      "En la app, escribe la **Nueva contraseña**, repítela en **Repite la contraseña** y pulsa **Guardar contraseña**.",
    ]),
    P("Si ya has iniciado sesión, también tienes **¿Has olvidado tu contraseña?** en la barra lateral, debajo de **Cerrar sesión**."),
    H2("2.3 Canjear una invitación"),
    P("Para unirte a una organización necesitas un **código de invitación**. Te lo da tu gerente."),
    ...pasos([
      "Entra en la app con el mismo correo al que se envió la invitación.",
      "Si aún no perteneces a ninguna organización, verás el mensaje «Aún no perteneces a ninguna organización».",
      "Pega el código en el campo **Código de invitación**.",
      "Pulsa **Canjear invitación**. Verás «¡Te has unido a…!» y la app se recargará con tu organización.",
    ]),
    ...fig("02"),
    P("Si te ha llegado un enlace de invitación en lugar de un código, ábrelo con la sesión iniciada: la invitación se canjea sola."),
    H2("2.4 La pantalla principal"),
    P("Al entrar verás dos zonas:"),
    ...vinetas([
      "**Barra lateral** (izquierda): logotipo y nombre de tu organización, estado de las conexiones, tu sesión (**Recargar permisos**, **Cerrar sesión**) y la **Ficha de ingrediente**. El gerente ve además **Navegación** con las opciones **App** y **Gerente**.",
      "**Zona central**: las pestañas **Recetas**, **Menús**, **Clientes** y **Facturas**.",
    ]),
    ...fig("10"),
    P("Si acabas de recibir un cambio de rol o de organización y no lo ves, pulsa **Recargar permisos**."),
    H2("2.5 Cambiar de organización activa"),
    P("Solo si perteneces a más de una organización:"),
    ...pasos([
      "En la barra lateral, abre el desplegable **Organización activa**.",
      "Elige la organización con la que quieres trabajar.",
      "La app se recarga con las recetas, menús, clientes y documentos de esa organización, y con su logotipo.",
    ]),
    ...fig("11"),
    ...nota("Al cambiar de organización se limpia el documento que tuvieras abierto en Facturas. Guarda antes lo que estés haciendo."),
    H2("2.6 Cerrar sesión"),
    P("Pulsa **Cerrar sesión** en la barra lateral. Hazlo siempre si usas un ordenador compartido."),
  ];
}

function capRecetas() {
  return [
    H1("3. Recetas"),
    P("En la pestaña **Recetas** creas los escandallos: qué ingredientes lleva cada plato, en qué cantidad y cuánto cuesta. Las recetas se guardan **siempre referidas a 1 ración**."),
    H2("3.1 Crear una receta"),
    ...pasos([
      "Ve a la pestaña **Recetas**.",
      "Escribe el **Nombre de la receta**, por ejemplo «Croquetas de jamón».",
      "Escribe la **Categoría** (por ejemplo «Entrantes») y el **Tipo de plato** (por ejemplo «Frito»).",
      "Deja **Raciones base receta** en 1 o indica cuántas raciones salen con las cantidades que vas a escribir (apartado 3.6).",
    ]),
    ...fig("12"),
    H2("3.2 Añadir ingredientes"),
    P("Los ingredientes se escriben en la tabla **Ingredientes**. La última fila de la tabla es un borrador: escribir en ella no crea una fila real hasta que eliges un ingrediente del inventario o usas la ficha lateral."),
    ...pasos([
      "En la última fila, escribe el nombre del ingrediente (por ejemplo «harina»).",
      "Debajo de la tabla aparecen las **Coincidencias de inventario para la última fila**. Elige la buena y pulsa **Usar**.",
      "Escribe la **Cantidad compra** y revisa la **Unidad** (kg, l, ud…).",
      "Repite con el resto de ingredientes.",
    ]),
    ...fig("17b", "Tabla de ingredientes de las croquetas de jamón"),
    ...nota("**Cantidad compra** es la cantidad **bruta** que compras, antes de limpiar o pelar. La cantidad neta se obtiene aplicando la **merma** (en %). El coste se calcula siempre sobre la cantidad bruta."),
    P("Para empezar de cero, pulsa **Limpiar todos** y confirma con **Sí, limpiar todos los ingredientes**. Esto solo vacía la receta que tienes en pantalla: no borra el inventario ni la versión guardada."),
    H2("3.3 La ficha de ingrediente"),
    P("Al marcar una fila de la tabla, sus datos se abren en la **Ficha de ingrediente** de la barra lateral. Ahí puedes revisarlos y corregirlos con calma."),
    ...pasos([
      "Marca la casilla de la fila en la columna **Seleccionar**.",
      "En la barra lateral, revisa o cambia **Merma %**, **Precio unidad (€)**, **Cantidad de compra (bruta)**, **Observaciones** y **Alérgenos**.",
      "Pulsa **Actualizar fila de receta** para aplicar los cambios a esta receta, o **Eliminar de esta receta** para quitarla.",
    ]),
    ...fig("14"),
    PG("Los botones **Guardar/actualizar en inventario** y **Añadir a receta y guardar en inventario** crean un **ingrediente privado** de tu organización. Solo puede hacerlo el gerente; al chef la app le pedirá que se lo pida a su gerente."),
    H2("3.4 Costes, PVP y Food Cost"),
    P("Encima de la tabla verás tres indicadores que se actualizan al momento:"),
    ...tabla(
      ["Indicador", "Qué significa"],
      [
        ["**Coste por ración**", "Suma de cantidad de compra × precio de cada ingrediente, por ración."],
        ["**PVP por ración**", "Precio de venta con IVA: coste + costes indirectos, más el margen de beneficio, más el IVA (apartado 3.5)."],
        ["**Food Cost**", "Porcentaje que supone el coste sobre el precio de venta **sin IVA**. Cuanto más bajo, más margen."],
      ],
      [2600, 7038]
    ),
    ...fig("15"),
    P("**Ejemplo** (figura anterior): coste 0,38 €, con 10 % de costes indirectos y 30 % de margen da un PVP sin IVA de unos 0,54 €. Con 10 % de IVA, el PVP por ración es 0,60 €. El Food Cost es 0,38 ÷ 0,54 = 69,9 %."),
    P("Si ves «-» en PVP o en Food Cost, es que la receta aún no tiene coste: revisa que los ingredientes tengan cantidad y precio."),
    H2("3.5 Parámetros avanzados"),
    ...pasos([
      "Abre **Parámetros avanzados**, debajo de los alérgenos.",
      "Ajusta **Costes Indirectos (%)**, **Margen Beneficio (%)** e **IVA Evento (%)**.",
      "El PVP y el Food Cost se recalculan al momento.",
    ]),
    ...fig("18"),
    P("El margen se aplica sobre el coste y admite valores por encima del 100 %. Por ejemplo, con un coste de 10 € y un margen del 150 %, el PVP sin IVA es 25 €."),
    H2("3.6 Raciones base: ajustar la receta a 1 ración"),
    P("Si copias una receta pensada para varias raciones, escribe las cantidades tal cual y luego indica cuántas raciones salen:"),
    ...pasos([
      "Cambia **Raciones base receta**, por ejemplo a 4.",
      "Aparece un aviso: todas las cantidades se dividirán entre 4 y la receta quedará ajustada a 1 ración.",
      "Pulsa **Confirmar ajuste** para aplicarlo, o **Cancelar** para dejarlo como estaba.",
    ]),
    ...fig("21"),
    H2("3.7 Alérgenos de la receta"),
    P("El bloque **Alérgenos detectados** muestra los alérgenos que aportan los ingredientes de la receta. Si cambias ingredientes y no se actualiza, pulsa **Refrescar alérgenos**."),
    ...fig("16"),
    P("Si la receta lleva ingredientes privados cuyos alérgenos aún no se han revisado, la app muestra un aviso en rojo. No uses esa receta en producción hasta que el gerente los revise (apartado 7.7)."),
    ...recuadro("⚠ Alérgenos: seguridad alimentaria", [
      "La lista de alérgenos se calcula a partir de lo declarado en cada ingrediente. La app te ayuda, pero **la responsabilidad final es del establecimiento**.",
      "Comprueba siempre las etiquetas de los productos que compras y avisa a tu gerente si un ingrediente tiene alérgenos que no aparecen, o al revés.",
    ], { fill: "FBF3E4", borde: "C0392B" }),
    H2("3.8 Rellenar una receta con IA a partir de un texto"),
    ...pasos([
      "Abre **IA: Generar receta con IA** y elige la pestaña **Texto**.",
      "En **Texto para analizar**, escribe o pega la receta con sus cantidades. Por ejemplo: «Crema de calabaza para 4 raciones: 800 g de calabaza, 150 g de cebolla…».",
      "Pulsa **Analizar texto con IA**.",
      "La IA rellena la tabla de ingredientes. Revisa cada fila: ingrediente elegido, cantidad y unidad.",
      "Si el texto era para varias raciones, ajusta las **Raciones base receta** (apartado 3.6).",
    ]),
    ...fig("17"),
    ...fig("13"),
    ...nota("La IA puede equivocarse al elegir un ingrediente o una cantidad, y puede dejar filas sin cantidad (en el ejemplo, la sal y la pimienta). Revisa siempre el resultado antes de guardar."),
    H2("3.9 Rellenar una receta con IA a partir de una foto"),
    ...pasos([
      "Abre **IA: Generar receta con IA** y elige la pestaña **Imagen**.",
      "En **Foto de receta, factura o albarán (JPG/PNG)**, sube la imagen.",
      "Pulsa **Escanear imagen con IA Vision**.",
      "Revisa los ingredientes que se han rellenado, igual que con el texto.",
    ]),
    ...fig("17c"),
    ...fig("17d"),
    H2("3.10 Elaboración y guardar la receta"),
    ...pasos([
      "Baja hasta **Guardar**. Revisa el **Nombre de receta**.",
      "Abre **Elaboración y observaciones** y escribe los pasos de la elaboración.",
      "Pulsa **Guardar receta**. La app le asigna un código automático, por ejemplo **REC-0023**.",
    ]),
    ...fig("19"),
    P("Los otros dos botones:"),
    ...vinetas([
      "**Actualizar receta**: guarda los cambios sobre la receta que has cargado.",
      "**Duplicar receta**: guarda una copia nueva, con otro código. Útil para hacer variantes.",
    ]),
    H2("3.11 Abrir una receta guardada"),
    ...pasos([
      "En **Recetas guardadas**, abre el desplegable y elige la receta.",
      "Pulsa **Cargar receta**. La receta se abre con sus ingredientes, costes y alérgenos.",
    ]),
    ...fig("20"),
    PG("Junto a **Cargar receta**, el gerente ve el botón **Compartir** (apartado 7.8)."),
    P("Para borrar una receta: cárgala, abre **Mantenimiento**, escribe ELIMINAR y pulsa **Borrar receta seleccionada**. No se puede deshacer."),
    H2("3.12 Descargar la ficha técnica"),
    ...pasos([
      "Con la receta en pantalla, pulsa **Descargar ficha Excel** (debajo de **Parámetros avanzados**).",
      "Se descarga un fichero Excel con la ficha técnica de la receta.",
    ]),
    ...fig("22"),
    ...fig("22b"),
    H2("3.13 Recetas compartidas con mi organización"),
    P("Otras organizaciones pueden compartir recetas con la tuya. Las verás al final de la pestaña **Recetas**, en **Recetas compartidas con mi organización**, con el nombre de la organización que las comparte."),
    ...vinetas([
      "Al abrir una, ves su categoría, tipo de plato y raciones base.",
      "Con ✅ se marcan las que tu organización ya ha copiado.",
    ]),
    PG("Para copiar una receta compartida a tu organización:"),
    ...pasos([
      "Pulsa **Ver y copiar**. Se abre la **Vista previa de la receta compartida**: ingredientes con sus cantidades (sin los precios de origen), elaboración y alérgenos.",
      "Pulsa **Copiar a mi organización**, o **Cerrar vista previa** si no te interesa.",
      "La copia es una receta nueva e independiente, con los precios de tu organización.",
      "Revisa los precios y el PVP: los márgenes no se copian.",
    ]),
    ...fig("23"),
    ...recuadro("⚠ Revisa los alérgenos de las recetas copiadas", [
      "Si la receta usa ingredientes privados de la otra organización, se crean como ingredientes privados de la tuya con sus alérgenos **pendientes de revisión**. La app te los lista al copiar.",
      "Revísalos en **Gerente → Inventario propio** antes de usar la receta.",
    ], { fill: "FBF3E4", borde: "C0392B" }),
  ];
}

function capMenus() {
  return [
    H1("4. Menús"),
    P("En la pestaña **Menús** combinas recetas guardadas para montar un menú: cóctel, buffet, menú sentado… El menú calcula su coste total y reúne los alérgenos y las fichas técnicas de sus platos."),
    H2("4.1 Crear un menú"),
    ...pasos([
      "Ve a la pestaña **Menús**.",
      "Escribe el **Nombre del menú**, por ejemplo «Menú cóctel otoño».",
      "Elige el **Tipo de menú**: Cóctel, Buffet, Menú sentado, Catering u Otro.",
      "Indica el **Pax de referencia**. Es un dato informativo: no cambia las raciones de cada receta.",
      "En **Añadir recetas**, elige una receta en **Recetas guardadas**, indica las **Raciones de esta receta** y, si quieres, la **Sección** (Aperitivo, Entrante, Principal, Postre, Bebida u Otro).",
      "Pulsa **Añadir receta al menú**. Repite con el resto de platos.",
    ]),
    ...fig("30"),
    H2("4.2 Ordenar y quitar platos"),
    P("En **Acciones por plato**, cada receta tiene tres botones:"),
    ...vinetas([
      "**Subir** y **Bajar**: cambian el orden del plato en el menú.",
      "**Quitar del menú**: lo quita del menú (la receta no se borra).",
    ]),
    P("Debajo verás el resumen: **Recetas / platos**, **Coste total del menú**, **Precio total del menú** y **Pax de referencia**."),
    H2("4.3 Alérgenos y fichas técnicas del menú"),
    P("En **Fichas técnicas del menú** verás los **Alérgenos del menú**, que reúnen los de todas sus recetas. Pulsa **Refrescar alérgenos** si has cambiado alguna receta."),
    ...pasos([
      "Abre cualquier **Ficha técnica** para consultarla en pantalla.",
      "Pulsa **Descargar fichas técnicas del menú** para bajar todas en un Excel.",
    ]),
    ...fig("31"),
    H2("4.4 Guardar el menú"),
    ...vinetas([
      "**Guardar menú**: guarda un menú nuevo.",
      "**Actualizar menú seleccionado**: guarda los cambios del menú que has cargado.",
      "**Duplicar menú seleccionado**: crea una copia para hacer una variante.",
      "**Limpiar menú actual**: vacía la pantalla para empezar otro (no borra lo guardado).",
    ]),
    H2("4.5 Abrir un menú guardado"),
    ...pasos([
      "En **Cargar menú guardado**, abre el desplegable **Menús guardados** y elige el menú.",
      "Pulsa **Cargar menú**.",
    ]),
    ...fig("33"),
    P("Para borrar un menú, cárgalo, abre **Eliminar menú**, escribe ELIMINAR y pulsa **Eliminar menú seleccionado**. Las recetas no se borran. No se puede eliminar un menú usado en presupuestos o facturas."),
  ];
}

function capClientes() {
  return [
    H1("5. Clientes"),
    P("En la pestaña **Clientes** guardas los datos de las personas y empresas a las que haces presupuestos y facturas."),
    H2("5.1 Crear un cliente"),
    ...pasos([
      "Ve a la pestaña **Clientes**.",
      "En **Nuevo cliente**, rellena **Nombre**, **Tipo cliente**, **NIF/CIF**, **Email**, **Teléfono**, **Dirección**, **Código postal**, **Ciudad**, **Provincia** y **País**.",
      "Añade **Observaciones** si las necesitas.",
      "Pulsa **Guardar cliente**.",
    ]),
    ...fig("41"),
    ...nota("Los datos del cliente salen en los presupuestos y facturas. Revisa bien el nombre fiscal, el NIF/CIF y la dirección."),
    H2("5.2 Editar un cliente"),
    ...pasos([
      "En **Editar cliente**, abre **Clientes guardados** y elige el cliente.",
      "Cambia los datos que necesites.",
      "Pulsa **Actualizar cliente**.",
    ]),
    ...fig("40"),
    P("Para eliminar un cliente, escribe ELIMINAR y pulsa **Eliminar cliente seleccionado**. No se puede deshacer: no elimines clientes con documentos asociados."),
  ];
}

function capFacturas() {
  return [
    H1("6. Presupuestos y facturas"),
    ...recuadro("⚠ Facturación", [
      "La app **no está certificada VERI*FACTU**. Consulta con tu gestoría antes de usarla como sistema fiscal.",
    ], { fill: "FBF3E4", borde: "C0392B" }),
    H2("6.1 Cómo funciona"),
    P("Todos los documentos (presupuestos y facturas) siguen el mismo camino:"),
    ...tabla(
      ["Estado", "Qué significa", "Quién"],
      [
        ["**Borrador**", "Se puede editar. Aún no tiene número.", "Chef y gerente"],
        ["**Emitido**", "Tiene número definitivo y ya no se puede editar.", "Gerente"],
        ["**Cobrado**", "El cliente ha pagado.", "Gerente"],
        ["**Anulado**", "Solo para presupuestos emitidos que ya no valen.", "Gerente"],
      ],
      [1900, 5338, 2400]
    ),
    P("Al emitir, la app asigna un número correlativo por año y por tipo de documento:"),
    ...tabla(
      ["Documento", "Formato", "Ejemplo"],
      [
        ["Presupuesto", "PRE-AAAA-NNNN", "PRE-2026-0001"],
        ["Factura", "FAC-AAAA-NNNN", "FAC-2026-0001"],
        ["Factura rectificativa", "REC-AAAA-NNNN", "REC-2026-0001"],
      ],
      [3238, 3200, 3200]
    ),
    ...vinetas([
      "Un documento **emitido no se puede modificar**. Solo cambian su estado y su cobro.",
      "Una **factura** emitida no se anula: si hay un error, se corrige con una **factura rectificativa**.",
      "Un **presupuesto** emitido sí se puede anular.",
    ]),
    H2("6.2 Documentos guardados"),
    P("Arriba de la pestaña **Facturas** tienes **Documentos guardados**, con todos los documentos de tu organización."),
    ...vinetas([
      "**Cargar documento**: abre el documento elegido para verlo o seguir editándolo.",
      "**Duplicar documento**: crea un borrador nuevo a partir de él.",
      "**Crear factura desde presupuesto**: crea un borrador de factura con los menús del presupuesto elegido.",
    ]),
    ...fig("60"),
    H2("6.3 Crear un borrador"),
    ...pasos([
      "Ve a la pestaña **Facturas**. En **Documento actual**, elige el **Cliente** y el **Tipo de documento** (presupuesto o factura).",
      "Revisa la **Fecha de emisión**, la **Fecha de vencimiento**, el **Método de pago**, la **Retención (%)** y el **IVA (%)**. El IVA viene por defecto del que tenga configurado tu organización.",
      "Escribe el **Concepto** (por ejemplo «Cóctel de bienvenida – evento de empresa») y, si quieres, unas **Notas**.",
      "En **Crear documento desde menú**, elige un **Menú guardado** y pulsa **Añadir menú**. Puedes añadir varios menús.",
      "Pulsa **Guardar borrador**. Si vuelves a cambiar algo, pulsa **Actualizar borrador**.",
    ]),
    P("El campo **Número de documento** aparece vacío («Sin número (se asigna al emitir)»): el número llega al emitir."),
    ...fig("61a"),
    ...fig("61"),
    P("Para corregir, usa **Quitar último menú** o **Limpiar documento**. Con **Descargar PDF** puedes bajar el borrador para revisarlo."),
    H3("Si eres chef"),
    P("Puedes preparar y guardar el borrador igual que el gerente. Cuando esté listo, avisa a tu gerente para que lo emita: en lugar del botón de emitir verás el mensaje «Solo el gerente puede emitir el documento (asignar número definitivo)»."),
    ...fig("50"),
    ...fig("51"),
    H2("6.4 Emitir un documento", true),
    P("Antes de emitir por primera vez, el gerente debe rellenar los datos fiscales de la organización (apartado 7.4). Sin razón social, NIF/CIF y dirección fiscal la app no deja emitir."),
    ...pasos([
      "Carga el borrador (o guárdalo si es nuevo) y revisa todos los datos.",
      "Pulsa **Emitir documento**.",
      "Verás el mensaje «Documento emitido con número PRE-2026-0001» (o FAC-… si es una factura).",
    ]),
    ...fig("62a"),
    ...fig("62"),
    ...nota("Emitir no se puede deshacer. Revisa cliente, menús, IVA y totales antes de pulsar el botón."),
    H2("6.5 El documento emitido y su PDF"),
    P("Un documento emitido se muestra en solo lectura con el aviso «Los documentos emitidos no se pueden editar». Debajo tienes **Descargar PDF** y las **Acciones sobre el documento emitido**."),
    ...fig("63"),
    P("El PDF de un documento emitido usa siempre el número, las líneas y los totales que se guardaron al emitir. Lleva los datos fiscales y el logotipo de tu organización."),
    ...fig("64"),
    H2("6.6 Pasar de presupuesto a factura"),
    ...pasos([
      "En **Documentos guardados**, elige el presupuesto.",
      "Pulsa **Crear factura desde presupuesto**. Se crea un borrador de factura con los mismos menús.",
      "Revisa el borrador, pulsa **Guardar borrador** y, si eres gerente, **Emitir documento**.",
    ]),
    ...fig("65"),
    H2("6.7 Marcar como cobrado", true),
    ...pasos([
      "Carga el documento emitido.",
      "En **Acciones sobre el documento emitido**, pulsa **Marcar como cobrado**.",
      "El documento pasa al estado **cobrada**.",
    ]),
    ...fig("66"),
    H2("6.8 Corregir una factura: rectificativa", true),
    P("Una factura emitida no se puede cambiar ni anular. Si tiene un error, crea una rectificativa:"),
    ...pasos([
      "Carga la factura emitida.",
      "Pulsa **Crear rectificativa**. Se crea un borrador rectificativo y se abre en pantalla.",
      "Corrige lo que haga falta y guárdalo.",
      "Pulsa **Emitir documento**. La rectificativa recibe un número **REC-AAAA-NNNN**.",
    ]),
    ...fig("67"),
    H2("6.9 Anular un presupuesto", true),
    ...pasos([
      "Carga el presupuesto emitido.",
      "Pulsa **Anular presupuesto**. Si la app te pide confirmación, pulsa **Sí, anular presupuesto**.",
      "El presupuesto pasa al estado **anulada**. La anulación no se puede deshacer.",
    ]),
    ...fig("68"),
    ...nota("Por ahora no se pueden eliminar documentos desde la app."),
  ];
}

function capGerente() {
  return [
    H1("7. Funciones del gerente"),
    PG("Todo este capítulo es solo para gerentes."),
    H2("7.1 La página Gerente"),
    ...pasos([
      "En la barra lateral, en **Navegación**, elige **Gerente**.",
      "Verás **Gestión de Demo** (con el nombre de tu organización) y cuatro pestañas: **Miembros e invitaciones**, **Datos de la organización**, **Inventario propio** y **Compartir recetas**.",
      "Para volver a las recetas, menús y facturas, elige **App** en **Navegación**.",
    ]),
    ...fig("70"),
    H2("7.2 Miembros"),
    P("En **Miembros e invitaciones → Miembros** verás quién forma parte de tu organización, con su rol (chef o gerente) y si está activo."),
    P("Para quitar el acceso a alguien, pulsa **Desactivar** en su fila."),
    ...fig("71"),
    H2("7.3 Invitar a una persona"),
    ...pasos([
      "Ve a **Miembros e invitaciones → Invitaciones**.",
      "Escribe el **Email del invitado**, elige el **Rol** (chef o gerente) y los **Días de validez**.",
      "Pulsa **Generar invitación**.",
      "**Copia el código ahora**: no se vuelve a mostrar.",
      "Envía el código a la persona. Ella entra con ese mismo correo y lo pega en **Código de invitación** (apartado 2.3).",
    ]),
    ...fig("72"),
    P("En **Invitaciones activas** ves si cada invitación está pendiente, canjeada o revocada. Para anular una invitación pendiente, pulsa **Revocar**. Si se perdió el código, revoca la invitación y genera otra."),
    H2("7.4 Datos de la organización"),
    P("Estos datos salen en los presupuestos y facturas. **Razón social**, **NIF / CIF** y **Dirección fiscal** son obligatorios para poder emitir documentos."),
    ...pasos([
      "Ve a **Datos de la organización**.",
      "Rellena los **Datos fiscales**: razón social, NIF/CIF, dirección fiscal, código postal, provincia, ciudad, teléfono y email.",
      "Indica el **IVA por defecto (%)** y, si quieres, el **Texto de pie de factura**.",
      "Pulsa **Guardar datos**. Verás «Datos de la organización guardados».",
    ]),
    ...fig("73"),
    H2("7.5 Logotipo"),
    ...pasos([
      "En **Datos de la organización → Logotipo**, sube tu logo (PNG, JPG o WEBP, de 300 KB como máximo).",
      "Comprueba la **Vista previa** y pulsa **Guardar logo**.",
      "El logo aparecerá en la cabecera de la app y en tus documentos. Para cambiarlo por el nombre en texto, pulsa **Quitar logo**.",
    ]),
    ...fig("74"),
    H2("7.6 Precios propios"),
    P("El catálogo común de ingredientes trae un precio de referencia. Si tu organización compra a otro precio, pon el tuyo: tus recetas usarán tu precio."),
    ...pasos([
      "Ve a **Inventario propio → Precios propios sobre el catálogo global**.",
      "En **Buscar ingrediente del catálogo**, escribe el nombre o el código.",
      "Abre el ingrediente. Escribe tu **Precio/unidad (€)** y tu **Merma (%)**.",
      "Pulsa **Guardar precio propio**. El ingrediente pasará a mostrar «(precio propio)».",
    ]),
    ...fig("75"),
    H2("7.7 Ingredientes privados"),
    P("Si un ingrediente no existe en el catálogo común, créalo como **ingrediente privado**. Solo lo verá tu organización y recibirá un código del tipo **P-…-0001**."),
    ...pasos([
      "Ve a **Inventario propio → Añadir ingrediente privado**.",
      "Escribe la **Descripción** y elige la **Familia** y la **Unidad de medida**.",
      "Declara sus **Alérgenos (de los 14 de la UE)**. Si no tiene ninguno, marca **No contiene ninguno de los 14 alérgenos de la UE**.",
      "Pulsa **Crear ingrediente privado**.",
    ]),
    ...fig("76"),
    P("En **Ingredientes privados** verás la lista. Los marcados con ⚠️ tienen los alérgenos **pendientes de revisión** (por ejemplo, los que llegan al copiar una receta compartida). Revísalos antes de usarlos. Si de verdad no contiene ninguno de los 14 alérgenos, pulsa **Marcar como 'Sin alérgenos de los 14'**."),
    P("Para borrar un ingrediente privado, pulsa **Eliminar ingrediente**. La app no lo deja borrar si alguna receta lo usa."),
    ...recuadro("⚠ Alérgenos de los ingredientes privados", [
      "Los alérgenos de un ingrediente privado los declara tu organización. Comprueba la etiqueta del producto y no marques «No contiene ninguno» sin estar seguro.",
    ], { fill: "FBF3E4", borde: "C0392B" }),
    H2("7.8 Compartir recetas"),
    P("Puedes compartir una receta con otra organización concreta o con todas. Ellas verán una vista previa sin tus precios y podrán hacer una copia independiente."),
    ...pasos([
      "Ve a **Compartir recetas → Compartir una receta**.",
      "Elige la **Receta a compartir**.",
      "Elige el **Destino**: una organización o **Todas las organizaciones**.",
      "Pulsa **Compartir**.",
    ]),
    ...fig("77"),
    P("También puedes compartir desde **Recetas → Recetas guardadas** con el botón **Compartir**."),
    P("En **Comparticiones activas** ves lo que has compartido. Para dejar de compartir una receta, pulsa **Desactivar**. Las copias que ya hicieron otras organizaciones siguen siendo suyas."),
    ...fig("78"),
  ];
}

function capFaq() {
  const qa = (q, a) => [
    new Paragraph({ spacing: { before: 160, after: 60 }, keepNext: true, children: [new TextRun({ text: q, bold: true, color: MARRON })] }),
    P(a),
  ];
  return [
    H1("8. Preguntas frecuentes y avisos"),
    ...qa("No veo la opción «Gerente» en la barra lateral.", "Solo la ven los gerentes. Si te acaban de cambiar el rol, pulsa **Recargar permisos**."),
    ...qa("He entrado y la app dice que no pertenezco a ninguna organización.", "Pide una invitación a tu gerente y canjéala (apartado 2.3). Entra con el mismo correo al que se envió."),
    ...qa("No me aparece el botón «Emitir documento».", "Solo el gerente puede emitir, y solo sobre un borrador ya guardado. Si eres gerente, pulsa antes **Guardar borrador**."),
    ...qa("La app no me deja emitir: faltan datos fiscales.", "Completa razón social, NIF/CIF y dirección fiscal en **Gerente → Datos de la organización**."),
    ...qa("Me he equivocado en una factura emitida.", "No se puede editar ni anular. Crea una **rectificativa** (apartado 6.8)."),
    ...qa("¿Puedo borrar un presupuesto o una factura?", "No. Un presupuesto emitido se puede anular; una factura se corrige con una rectificativa."),
    ...qa("El PVP o el Food Cost salen con «-».", "La receta no tiene coste todavía. Revisa que los ingredientes tengan cantidad y precio."),
    ...qa("Un ingrediente tiene un precio distinto al que pago.", "El gerente puede poner un precio propio (apartado 7.6). Si eres chef, pídeselo."),
    ...qa("He cambiado de organización y ha desaparecido lo que tenía en pantalla.", "Cada organización tiene sus propios datos. Guarda siempre antes de cambiar de organización activa."),
    ...qa("No encuentro un ingrediente en el inventario.", "Escríbelo en la última fila de la tabla y revisa las coincidencias. Si no existe, el gerente puede crearlo como ingrediente privado (apartado 7.7)."),
    ...qa("He perdido el código de una invitación.", "No se puede volver a ver. Revoca la invitación y genera una nueva (apartado 7.3)."),
    ...qa("He copiado una receta compartida y sale un aviso de alérgenos.", "Los ingredientes privados copiados llegan con los alérgenos pendientes de revisión. El gerente debe revisarlos en **Gerente → Inventario propio** antes de usar la receta."),
    new Paragraph({ spacing: { after: 200 }, children: [] }),
    ...avisosObligatorios(),
  ];
}

// ── Documento ────────────────────────────────────────────────────────────
const doc = new Document({
  creator: "Samirarte",
  title: "Gestor de Escandallos – Manual de usuario",
  description: "Manual de usuario para los roles Chef y Gerente",
  features: { updateFields: true },
  styles: {
    default: { document: { run: { font: "Calibri", size: 22, color: TEXTO } } },
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { font: "Cambria", size: 36, bold: true, color: MARRON },
        paragraph: { spacing: { before: 240, after: 240 }, outlineLevel: 0,
          border: { bottom: { style: BorderStyle.SINGLE, size: 8, color: DORADO, space: 6 } } } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { font: "Cambria", size: 28, bold: true, color: MARRON },
        paragraph: { spacing: { before: 320, after: 120 }, outlineLevel: 1, keepNext: true } },
      { id: "Heading3", name: "Heading 3", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { font: "Cambria", size: 24, bold: true, color: DORADO },
        paragraph: { spacing: { before: 200, after: 80 }, outlineLevel: 2, keepNext: true } },
    ],
  },
  numbering: {
    config: [
      { reference: "pasos", levels: [{ level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT,
        style: { run: { bold: true, color: DORADO }, paragraph: { indent: { left: 440, hanging: 360 } } } }] },
      { reference: "vinetas", levels: [{ level: 0, format: LevelFormat.BULLET, text: "•", alignment: AlignmentType.LEFT,
        style: { run: { color: DORADO }, paragraph: { indent: { left: 440, hanging: 300 } } } }] },
    ],
  },
  sections: [
    {
      properties: { page: { size: { width: 11906, height: 16838 }, margin: { top: 1134, bottom: 1134, left: 1134, right: 1134 } } },
      children: portada(),
    },
    {
      properties: { page: { size: { width: 11906, height: 16838 }, margin: { top: 1134, bottom: 1134, left: 1134, right: 1134 }, pageNumbers: { start: 1 } } },
      headers: {
        default: new Header({ children: [new Paragraph({ alignment: AlignmentType.RIGHT, children: [new TextRun({ text: "Gestor de Escandallos · Manual de usuario", size: 16, color: GRIS })] })] }),
      },
      footers: {
        default: new Footer({ children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [
          new TextRun({ text: "Samirarte · Página ", size: 16, color: GRIS }),
          new TextRun({ children: [PageNumber.CURRENT], size: 16, color: GRIS }),
        ] })] }),
      },
      children: [
        ...capIntroduccion(),
        ...capAcceso(),
        ...capRecetas(),
        ...capMenus(),
        ...capClientes(),
        ...capFacturas(),
        ...capGerente(),
        ...capFaq(),
      ],
    },
  ],
});

Packer.toBuffer(doc).then((buf) => {
  fs.writeFileSync(SALIDA, buf);
  console.log(`Escrito ${SALIDA} (${numFigura} figuras)`);
});
