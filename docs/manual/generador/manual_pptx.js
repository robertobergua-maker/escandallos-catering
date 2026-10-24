// Genera docs/manual/Manual_Gestor_Escandallos.pptx (versión de formación).
// Uso: ver README.md de esta carpeta.

const fs = require("fs");
const path = require("path");
const pptxgen = require("pptxgenjs");
const { figura, tamPng, IMG_DIR } = require("./figuras");

const SALIDA = path.resolve(__dirname, "..", "Manual_Gestor_Escandallos.pptx");
const VERSION = "1.0 · Octubre de 2026";

const C = {
  marron: "5C3A21",
  marronOsc: "3B2414",
  dorado: "B8904F",
  doradoClaro: "E8CD9A",
  crema: "F7F1E6",
  texto: "2B2B2B",
  gris: "6B6B6B",
  grisClaro: "E6E6E6",
  rojo: "A93226",
  blanco: "FFFFFF",
};
const F_TIT = "Cambria";
const F_TXT = "Calibri";

const pres = new pptxgen();
pres.layout = "LAYOUT_16x9"; // 10 x 5.625 in
pres.author = "Samirarte";
pres.company = "Samirarte";
pres.title = "Gestor de Escandallos – Formación para Chef y Gerente";
pres.theme = { headFontFace: F_TIT, bodyFontFace: F_TXT };

// ── Diseños (layouts) ───────────────────────────────────────────────────
pres.defineSlideMaster({
  title: "PORTADA",
  background: { color: C.marronOsc },
  objects: [],
});
pres.defineSlideMaster({
  title: "SECCION",
  background: { color: C.marron },
  objects: [
    { placeholder: { options: { name: "num", type: "body", x: 0.7, y: 1.3, w: 3, h: 1.4, fontFace: F_TIT, fontSize: 72, bold: true, color: C.doradoClaro, margin: 0, align: "left" }, text: "" } },
    { placeholder: { options: { name: "title", type: "title", x: 0.7, y: 2.75, w: 8.6, h: 0.9, fontFace: F_TIT, fontSize: 36, bold: true, color: C.blanco, margin: 0, valign: "top", align: "left" }, text: "" } },
    { placeholder: { options: { name: "body", type: "body", x: 0.7, y: 3.65, w: 8.6, h: 0.8, fontFace: F_TXT, fontSize: 16, color: C.doradoClaro, margin: 0, valign: "top", align: "left" }, text: "" } },
  ],
});
pres.defineSlideMaster({
  title: "CONTENIDO",
  background: { color: C.blanco },
  margin: [0.5, 0.5, 0.5, 0.5],
  objects: [
    { placeholder: { options: { name: "title", type: "title", x: 0.5, y: 0.3, w: 7.2, h: 0.65, fontFace: F_TIT, fontSize: 26, bold: true, color: C.marron, margin: 0, valign: "middle", align: "left" }, text: "" } },
    { text: { text: "Gestor de Escandallos · Formación", options: { x: 0.5, y: 5.25, w: 5, h: 0.25, fontFace: F_TXT, fontSize: 9, color: C.gris, margin: 0 } } },
  ],
  slideNumber: { x: 9.0, y: 5.25, w: 0.5, h: 0.25, fontFace: F_TXT, fontSize: 9, color: C.gris, align: "right" },
});

// ── Utilidades ──────────────────────────────────────────────────────────
let seccionActual = "";
function seccion(titulo) {
  seccionActual = titulo;
  pres.addSection({ title: titulo });
}

function etiquetaGerente(s, x, y) {
  s.addText("SOLO GERENTE", {
    x, y, w: 1.3, h: 0.3, shape: pres.shapes.ROUNDED_RECTANGLE, rectRadius: 0.06,
    fill: { color: C.marron }, color: C.blanco, fontFace: F_TXT, fontSize: 10, bold: true,
    align: "center", valign: "middle", margin: 0, isTextBox: true, objectName: "Etiqueta solo gerente",
  });
}

function nuevaDiapositiva(titulo, { gerente = false } = {}) {
  const s = pres.addSlide({ masterName: "CONTENIDO", sectionTitle: seccionActual });
  s.addText(titulo, { placeholder: "title" });
  if (gerente) etiquetaGerente(s, 8.2, 0.48);
  return s;
}

// Coloca una figura (o su marcador) dentro de la caja dada, sin ampliarla
// por encima de su tamaño real (96 ppp).
function ponerFigura(s, id, caja) {
  const f = figura(id, { ppt: true });
  if (f.pendiente) {
    s.addText(
      [
        { text: `[Captura pendiente: ${id}]`, options: { bold: true, fontSize: 14, color: "555555", breakLine: true } },
        { text: f.desc, options: { fontSize: 12, color: "666666", breakLine: true } },
        ...(f.nota ? [{ text: `(${f.nota})`, options: { fontSize: 10, italic: true, color: "777777", breakLine: true } }] : []),
        { text: `docs/manual/capturas/${f.file}`, options: { fontSize: 10, color: "888888" } },
      ],
      {
        x: caja.x, y: caja.y, w: caja.w, h: Math.min(caja.h, 2.6), shape: pres.shapes.ROUNDED_RECTANGLE, rectRadius: 0.1,
        fill: { color: C.grisClaro }, line: { color: "AAAAAA", width: 1, dashType: "dash" },
        align: "center", valign: "middle", fontFace: F_TXT, margin: 12, isTextBox: true, objectName: `Captura pendiente ${id}`,
      }
    );
    return { x: caja.x, y: caja.y, w: caja.w, h: Math.min(caja.h, 2.6) };
  }
  const { w, h } = tamPng(f.path);
  const nativoW = w / 96;
  const nativoH = h / 96;
  const esc = Math.min(1, caja.w / nativoW, caja.h / nativoH);
  const iw = nativoW * esc;
  const ih = nativoH * esc;
  const x = caja.x + (caja.w - iw) / 2;
  const y = caja.y;
  s.addImage({
    path: f.path, x, y, w: iw, h: ih, altText: f.desc, objectName: `Captura ${id}`,
    shadow: { type: "outer", color: "000000", opacity: 0.25, blur: 6, offset: 2, angle: 90 },
  });
  return { x, y, w: iw, h: ih };
}

// Lista de pasos con círculos dorados numerados (motivo visual del curso).
function pasos(s, lista, { x = 0.5, y = 1.2, w = 4.6, alto = 0.62, tam = 14 } = {}) {
  lista.forEach((t, i) => {
    const yy = y + i * alto;
    s.addText(String(i + 1), {
      x, y: yy + 0.02, w: 0.34, h: 0.34, shape: pres.shapes.OVAL, fill: { color: C.dorado },
      color: C.blanco, bold: true, fontSize: 13, fontFace: F_TXT, align: "center", valign: "middle", margin: 0,
      isTextBox: true, objectName: `Paso ${i + 1}`,
    });
    s.addText(conNegrita(t), {
      x: x + 0.48, y: yy - 0.04, w: w - 0.48, h: alto, fontFace: F_TXT, fontSize: tam, color: C.texto,
      valign: "top", margin: 0, isTextBox: true, objectName: `Texto paso ${i + 1}`,
    });
  });
}

// Puntos: un párrafo por punto. (pptxgenjs abre un párrafo nuevo en cada run con
// viñeta, así que no se usan viñetas para poder mezclar negrita y texto normal.)
function puntos(s, lista, { x = 0.5, y = 1.2, w = 4.6, h = 3.6, tam = 14 } = {}) {
  const runs = [];
  lista.forEach((t, i) => {
    conNegrita(t).forEach((r, j, arr) => {
      runs.push({
        text: r.text,
        options: { ...r.options, ...(j === arr.length - 1 && i < lista.length - 1 ? { breakLine: true } : {}) },
      });
    });
  });
  s.addText(runs, {
    x, y, w, h, fontFace: F_TXT, fontSize: tam, color: C.texto, valign: "top", margin: 0,
    paraSpaceAfter: 12, isTextBox: true, objectName: "Puntos",
  });
}

// **negrita** → runs
function conNegrita(t) {
  return String(t)
    .split(/(\*\*.+?\*\*)/g)
    .filter(Boolean)
    .map((p) => (p.startsWith("**") ? { text: p.slice(2, -2), options: { bold: true } } : { text: p, options: {} }));
}

// Recuadro de aviso.
function aviso(s, texto, { x = 0.5, y = 4.3, w = 4.6, h = 0.75, color = C.rojo, fondo = "FBF3E4", tam = 12 } = {}) {
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w, h, rectRadius: 0.08, fill: { color: fondo }, line: { color, width: 1.25 }, objectName: "Aviso" });
  s.addText("!", {
    x: x + 0.15, y: y + (h - 0.34) / 2, w: 0.34, h: 0.34, shape: pres.shapes.OVAL, fill: { color },
    color: C.blanco, bold: true, fontSize: 14, align: "center", valign: "middle", margin: 0, isTextBox: true, objectName: "Icono aviso",
  });
  s.addText(conNegrita(texto), {
    x: x + 0.62, y, w: w - 0.75, h, fontFace: F_TXT, fontSize: tam, color: C.texto, valign: "middle", margin: 0,
    isTextBox: true, objectName: "Texto aviso",
  });
}

const CAJA_DER = { x: 5.4, y: 1.1, w: 4.1, h: 4.0 };

// Diapositiva estándar: pasos o puntos a la izquierda, captura a la derecha.
function diapo({ titulo, gerente, fig, figs, horizontal, pasos: ps, puntos: pt, aviso: av, notas, tamTexto }) {
  const s = nuevaDiapositiva(titulo, { gerente });
  const largo = ps && ps.some((t) => t.replace(/\*\*/g, "").length > 85);
  if (ps) pasos(s, ps, { tam: tamTexto || 14, alto: largo ? 0.8 : ps.length > 4 ? 0.58 : 0.66 });
  if (pt) puntos(s, pt, { tam: tamTexto || 14, h: av ? 3.0 : 3.8 });
  if (av) aviso(s, av);
  if (fig) ponerFigura(s, fig, CAJA_DER);
  if (figs && horizontal) {
    const ancho = (CAJA_DER.w - 0.2 * (figs.length - 1)) / figs.length;
    figs.forEach((id, i) => ponerFigura(s, id, { ...CAJA_DER, x: CAJA_DER.x + i * (ancho + 0.2), w: ancho }));
  } else if (figs) {
    let y = CAJA_DER.y;
    const hueco = (CAJA_DER.h - 0.2 * (figs.length - 1)) / figs.length;
    figs.forEach((id) => {
      const r = ponerFigura(s, id, { ...CAJA_DER, y, h: hueco });
      y = r.y + r.h + 0.2;
    });
  }
  if (notas) s.addNotes(notas);
  return s;
}

function diapoSeccion(num, titulo, sub) {
  seccion(titulo);
  const s = pres.addSlide({ masterName: "SECCION", sectionTitle: titulo });
  s.addText(num, { placeholder: "num" });
  s.addText(titulo, { placeholder: "title" });
  if (sub) s.addText(sub, { placeholder: "body" });
  return s;
}

// ── Portada ─────────────────────────────────────────────────────────────
seccion("Portada");
{
  const s = pres.addSlide({ masterName: "PORTADA", sectionTitle: "Portada" });
  const logo = path.join(IMG_DIR, "samirarte_logo_white.png");
  if (fs.existsSync(logo)) s.addImage({ path: logo, x: 0.6, y: 1.0, w: 2.6, h: 2.6, altText: "Logotipo de Samirarte", objectName: "Logo" });
  s.addText("Gestor de Escandallos", { x: 3.6, y: 1.45, w: 6, h: 0.9, fontFace: F_TIT, fontSize: 40, bold: true, color: C.blanco, margin: 0, isTextBox: true });
  s.addText("Formación para Chef y Gerente", { x: 3.6, y: 2.35, w: 6, h: 0.5, fontFace: F_TIT, fontSize: 22, italic: true, color: C.doradoClaro, margin: 0, isTextBox: true });
  s.addText(`Samirarte · Versión ${VERSION}`, { x: 3.6, y: 3.1, w: 6, h: 0.4, fontFace: F_TXT, fontSize: 14, color: C.doradoClaro, margin: 0, isTextBox: true });
  s.addNotes("Bienvenida. Este curso recorre la app de principio a fin con la organización de ejemplo «Demo» (datos inventados).");
}

// ── Contenido del curso ────────────────────────────────────────────────
seccion("Introducción");
{
  const s = nuevaDiapositiva("Qué vamos a ver");
  const temas = [
    ["1", "Acceso", "Entrar, contraseña, invitación, organización"],
    ["2", "Recetas", "Ingredientes, costes, alérgenos, IA"],
    ["3", "Menús", "Combinar recetas y fichas técnicas"],
    ["4", "Clientes", "Fichas para presupuestos y facturas"],
    ["5", "Facturas", "Borrador, emitir, cobrar, rectificar"],
    ["6", "Gerente", "Miembros, datos, inventario, compartir"],
  ];
  temas.forEach(([n, t, d], i) => {
    const col = i % 3;
    const fila = Math.floor(i / 3);
    const x = 0.5 + col * 3.05;
    const y = 1.25 + fila * 1.95;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: 2.85, h: 1.7, rectRadius: 0.1, fill: { color: C.crema }, line: { color: C.doradoClaro, width: 1 }, objectName: `Tarjeta ${t}` });
    s.addText(n, { x: x + 0.2, y: y + 0.2, w: 0.5, h: 0.5, shape: pres.shapes.OVAL, fill: { color: C.dorado }, color: C.blanco, bold: true, fontSize: 18, align: "center", valign: "middle", margin: 0, isTextBox: true });
    s.addText(t, { x: x + 0.85, y: y + 0.2, w: 1.9, h: 0.5, fontFace: F_TIT, fontSize: 20, bold: true, color: C.marron, valign: "middle", margin: 0, isTextBox: true });
    s.addText(d, { x: x + 0.2, y: y + 0.85, w: 2.5, h: 0.7, fontFace: F_TXT, fontSize: 13, color: C.texto, valign: "top", margin: 0, isTextBox: true });
  });
  s.addNotes("Orden del curso. Cada bloque tiene pasos y una captura. Lo marcado como «Solo gerente» no lo puede hacer el chef.");
}
{
  const s = nuevaDiapositiva("Organizaciones y roles");
  puntos(s, [
    "Cada empresa es una **organización** con sus datos separados.",
    "Lo que guardas es de la **organización**, no tuyo: todos sus miembros lo ven.",
    "Hay dos roles: **Chef** y **Gerente**.",
  ], { w: 3.9, h: 2.4 });
  const filas = [
    ["", "Chef", "Gerente"],
    ["Recetas, menús y clientes", "Sí", "Sí"],
    ["Borradores y PDF", "Sí", "Sí"],
    ["Emitir, cobrar, anular, rectificar", "No", "Sí"],
    ["Copiar y compartir recetas", "No", "Sí"],
    ["Precios propios e ingredientes privados", "No", "Sí"],
    ["Miembros, datos y logo", "No", "Sí"],
  ];
  const cab = { bold: true, color: C.blanco, fill: { color: C.marron }, align: "center" };
  s.addTable(
    filas.map((f, i) =>
      f.map((t, j) => ({
        text: t,
        options: i === 0 ? cab : { align: j === 0 ? "left" : "center", color: t === "No" ? C.rojo : C.texto, bold: j > 0, fill: { color: i % 2 ? C.blanco : C.crema } },
      }))
    ),
    { x: 4.6, y: 1.2, w: 4.9, colW: [2.9, 1.0, 1.0], fontFace: F_TXT, fontSize: 12, border: { type: "solid", pt: 0.5, color: "D9CBB4" }, rowH: 0.42, valign: "middle" }
  );
  s.addNotes("Explica que la propiedad es de la organización. El gerente es quien emite documentos y gestiona la organización.");
}
{
  const s = nuevaDiapositiva("Avisos importantes");
  const tarjeta = (x, titulo, lineas) => {
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y: 1.2, w: 4.4, h: 3.7, rectRadius: 0.1, fill: { color: "FBF3E4" }, line: { color: C.rojo, width: 1.5 }, objectName: `Aviso ${titulo}` });
    s.addText("!", { x: x + 0.25, y: 1.4, w: 0.5, h: 0.5, shape: pres.shapes.OVAL, fill: { color: C.rojo }, color: C.blanco, bold: true, fontSize: 20, align: "center", valign: "middle", margin: 0, isTextBox: true });
    s.addText(titulo, { x: x + 0.9, y: 1.4, w: 3.3, h: 0.5, fontFace: F_TIT, fontSize: 20, bold: true, color: C.marron, valign: "middle", margin: 0, isTextBox: true });
    puntos(s, lineas, { x: x + 0.3, y: 2.1, w: 3.85, h: 2.7, tam: 14 });
  };
  tarjeta(0.5, "Alérgenos", [
    "La app ayuda, pero la **responsabilidad final es del establecimiento**.",
    "Revisa siempre las **etiquetas** de los productos.",
    "**Ingredientes privados** y **recetas copiadas**: revisa sus alérgenos antes de usarlos.",
  ]);
  tarjeta(5.1, "Facturación", [
    "La app **no está certificada VERI*FACTU**.",
    "Consulta con tu **gestoría** antes de usarla como sistema fiscal.",
  ]);
  s.addNotes("Estos dos avisos son obligatorios en cualquier formación. Alérgenos = seguridad alimentaria.");
}

diapoSeccion("01", "Acceso", "Entrar, recuperar la contraseña y unirte a tu organización");
diapo({
  titulo: "Entrar en la aplicación",
  figs: ["00", "01"],
  horizontal: true,
  pasos: [
    "Abre la app y pulsa **Entrar a la aplicación**.",
    "En la barra lateral, pulsa **Entrar con Google**, o escribe **Email** y **Contraseña** y pulsa **Iniciar sesión**.",
    "Verás **Sesión iniciada** con tu correo en la barra lateral.",
    "¿Olvidaste la contraseña? **¿Has olvidado tu contraseña?** → **Enviar enlace de recuperación**.",
  ],
  notas: "Desde el correo de recuperación se llega a «Nueva contraseña» / «Repite la contraseña» / «Guardar contraseña». «Continuar como invitado» es solo para probar: no guarda cambios.",
});
{
  const s = nuevaDiapositiva("Unirte a tu organización");
  const etapas = [
    ["Recibe el código", "Te lo da tu gerente: es tu **código de invitación**."],
    ["Entra", "Con el **mismo correo** al que se envió la invitación."],
    ["Pega el código", "En el campo **Código de invitación**."],
    ["Canjea", "Pulsa **Canjear invitación**: verás «¡Te has unido a…!»."],
  ];
  etapas.forEach(([t, d], i) => {
    const x = 0.5 + i * 2.3;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y: 1.5, w: 2.05, h: 2.4, rectRadius: 0.1, fill: { color: C.crema }, line: { color: C.doradoClaro, width: 1 }, objectName: `Etapa ${i + 1}` });
    s.addText(String(i + 1), { x: x + 0.75, y: 1.7, w: 0.55, h: 0.55, shape: pres.shapes.OVAL, fill: { color: C.dorado }, color: C.blanco, bold: true, fontSize: 18, align: "center", valign: "middle", margin: 0, isTextBox: true });
    s.addText(t, { x: x + 0.15, y: 2.4, w: 1.75, h: 0.4, fontFace: F_TIT, fontSize: 16, bold: true, color: C.marron, align: "center", margin: 0, isTextBox: true });
    s.addText(conNegrita(d), { x: x + 0.15, y: 2.85, w: 1.75, h: 0.95, fontFace: F_TXT, fontSize: 13, color: C.texto, align: "center", valign: "top", margin: 0, isTextBox: true });
    if (i < 3) s.addShape(pres.shapes.RIGHT_ARROW, { x: x + 2.08, y: 2.6, w: 0.19, h: 0.22, fill: { color: C.dorado }, line: { color: C.dorado }, objectName: "Flecha" });
  });
  s.addText("Si te llega un enlace de invitación, ábrelo con la sesión iniciada: se canjea solo.", { x: 0.5, y: 4.3, w: 9, h: 0.4, fontFace: F_TXT, fontSize: 14, italic: true, color: C.gris, margin: 0, isTextBox: true });
  s.addNotes("Este paso solo aparece si el usuario aún no pertenece a ninguna organización.");
}
diapo({
  titulo: "La pantalla principal",
  fig: "10",
  puntos: [
    "**Barra lateral**: logo y organización, tu sesión, **Ficha de ingrediente**.",
    "**Pestañas**: Recetas, Menús, Clientes y Facturas.",
    "El gerente ve además **Navegación**: App / Gerente.",
    "¿Varias organizaciones? Elige en **Organización activa**.",
    "¿No ves un cambio de rol? Pulsa **Recargar permisos**.",
  ],
  notas: "Cerrar sesión siempre en ordenadores compartidos. Al cambiar de organización activa se limpia el documento abierto en Facturas: guardar antes.",
});

diapoSeccion("02", "Recetas", "Escandallos, costes, alérgenos e inteligencia artificial");
diapo({
  titulo: "Crear una receta",
  fig: "12",
  pasos: [
    "Pestaña **Recetas**.",
    "Escribe **Nombre**, **Categoría** y **Tipo de plato**.",
    "Indica las **Raciones base receta** (1 si ya es por ración).",
    "Las recetas se guardan siempre **a 1 ración**.",
  ],
});
diapo({
  titulo: "Añadir ingredientes",
  fig: "17b",
  pasos: [
    "Escribe el ingrediente en la **última fila** de la tabla.",
    "Elige la coincidencia del inventario y pulsa **Usar**.",
    "Escribe la **Cantidad compra** (bruta) y revisa la **Unidad**.",
    "La merma (%) da la cantidad neta; el coste va sobre la bruta.",
  ],
  notas: "«Limpiar todos» vacía la receta en pantalla, con confirmación. No borra el inventario ni la versión guardada.",
});
diapo({
  titulo: "La ficha de ingrediente",
  fig: "14",
  pasos: [
    "Marca una fila en la columna **Seleccionar**.",
    "Revisa en la barra lateral merma, precio, cantidad y alérgenos.",
    "Pulsa **Actualizar fila de receta** o **Eliminar de esta receta**.",
  ],
  aviso: "**Guardar en inventario** crea un ingrediente privado: **solo gerente**.",
});
{
  const s = nuevaDiapositiva("Coste, PVP y Food Cost");
  const datos = [
    ["0,38 €", "Coste por ración", "Cantidad × precio de cada ingrediente"],
    ["0,60 €", "PVP por ración", "Coste + indirectos + margen + IVA"],
    ["69,9 %", "Food Cost", "Coste ÷ precio de venta sin IVA"],
  ];
  datos.forEach(([v, t, d], i) => {
    const y = 1.15 + i * 1.3;
    s.addText(v, { x: 0.5, y, w: 1.9, h: 0.75, fontFace: F_TIT, fontSize: 30, bold: true, color: C.dorado, margin: 0, valign: "middle", isTextBox: true });
    s.addText(t, { x: 2.5, y, w: 2.7, h: 0.4, fontFace: F_TXT, fontSize: 16, bold: true, color: C.marron, margin: 0, isTextBox: true });
    s.addText(d, { x: 2.5, y: y + 0.4, w: 2.7, h: 0.6, fontFace: F_TXT, fontSize: 13, color: C.texto, margin: 0, valign: "top", isTextBox: true });
  });
  ponerFigura(s, "15", CAJA_DER);
  s.addNotes("Ejemplo de las croquetas: coste 0,38 €; con 10 % de costes indirectos y 30 % de margen, PVP sin IVA ≈ 0,54 €; con 10 % de IVA, 0,60 €. Food Cost = 0,38 / 0,54 = 69,9 %. Si sale «-», faltan cantidades o precios.");
}
diapo({
  titulo: "Parámetros avanzados",
  fig: "18",
  pasos: [
    "Abre **Parámetros avanzados**.",
    "Ajusta **Costes Indirectos (%)**, **Margen Beneficio (%)** e **IVA Evento (%)**.",
    "El PVP y el Food Cost se recalculan al momento.",
  ],
  notas: "El margen se aplica sobre el coste y puede superar el 100 %: coste 10 € con margen 150 % = PVP sin IVA 25 €.",
});
diapo({
  titulo: "Ajustar la receta a 1 ración",
  fig: "21",
  pasos: [
    "Escribe las cantidades de la receta original.",
    "Cambia **Raciones base receta** (por ejemplo, 4).",
    "Lee el aviso: las cantidades se dividirán entre 4.",
    "Pulsa **Confirmar ajuste** o **Cancelar**.",
  ],
});
diapo({
  titulo: "Alérgenos de la receta",
  fig: "16",
  puntos: [
    "**Alérgenos detectados** reúne los de todos los ingredientes.",
    "Si no se actualiza, pulsa **Refrescar alérgenos**.",
    "Aviso rojo = hay ingredientes privados **sin revisar**.",
  ],
  aviso: "La app ayuda, pero la **responsabilidad final es del establecimiento**. Revisa las etiquetas.",
});
diapo({
  titulo: "IA: receta a partir de un texto",
  figs: ["17", "13"],
  pasos: [
    "Abre **IA: Generar receta con IA** → pestaña **Texto**.",
    "Pega la receta con cantidades en **Texto para analizar**.",
    "Pulsa **Analizar texto con IA**.",
    "**Revisa** cada fila: ingrediente, cantidad y unidad.",
    "Ajusta las **Raciones base** si era para varias.",
  ],
  notas: "La IA puede equivocarse o dejar filas sin cantidad (en el ejemplo, sal y pimienta). Revisar siempre antes de guardar.",
});
diapo({
  titulo: "IA: receta a partir de una foto",
  figs: ["17c", "17d"],
  pasos: [
    "Abre **IA: Generar receta con IA** → pestaña **Imagen**.",
    "Sube la foto (JPG o PNG) de la receta, factura o albarán.",
    "Pulsa **Escanear imagen con IA Vision**.",
    "**Revisa** los ingredientes rellenados.",
  ],
});
diapo({
  titulo: "Elaboración y guardar",
  fig: "19",
  pasos: [
    "Abre **Elaboración y observaciones** y escribe los pasos.",
    "Pulsa **Guardar receta**: recibe un código (REC-0023).",
    "**Actualizar receta** guarda cambios en la receta cargada.",
    "**Duplicar receta** crea una variante con otro código.",
  ],
});
diapo({
  titulo: "Recetas guardadas y ficha técnica",
  fig: "20",
  pasos: [
    "Elige la receta en **Recetas guardadas**.",
    "Pulsa **Cargar receta**.",
    "Pulsa **Descargar ficha Excel** para la ficha técnica.",
    "Borrar: **Mantenimiento** → escribe ELIMINAR.",
  ],
  notas: "El gerente ve además el botón «Compartir» junto a «Cargar receta».",
});
{
  const s = nuevaDiapositiva("La ficha técnica en Excel");
  puntos(s, [
    "Por ingrediente: código, cantidad bruta, **merma**, cantidad neta, precio y coste.",
    "Al final: costes indirectos, beneficio, IVA y **precio por ración**.",
  ], { w: 9, h: 0.9 });
  ponerFigura(s, "22b", { x: 0.5, y: 2.05, w: 9, h: 3.05 });
  s.addNotes("Se descarga con «Descargar ficha Excel». Un precio de 0,00 € en la ficha indica un ingrediente sin precio: revisarlo antes de dar el coste por bueno.");
}
diapo({
  titulo: "Recetas compartidas con mi organización",
  gerente: true,
  fig: "23",
  pasos: [
    "Abre la receta compartida y pulsa **Ver y copiar**.",
    "Revisa la vista previa (sin precios de origen).",
    "Pulsa **Copiar a mi organización**.",
    "Revisa precios y PVP: los márgenes no se copian.",
  ],
  aviso: "Los ingredientes privados copiados llegan con alérgenos **pendientes de revisión**.",
  notas: "El chef ve la lista de recetas compartidas, pero solo el gerente puede copiarlas. La copia es independiente de la receta original.",
});

diapoSeccion("03", "Menús", "Combina recetas, consulta alérgenos y descarga fichas");
diapo({
  titulo: "Crear un menú",
  fig: "30",
  pasos: [
    "Pestaña **Menús**: nombre, **Tipo de menú** y **Pax de referencia**.",
    "Elige receta, **Raciones** y **Sección**.",
    "Pulsa **Añadir receta al menú**.",
    "Ordena con **Subir** / **Bajar**; **Quitar del menú** para quitar.",
  ],
  notas: "Tipos de menú: Cóctel, Buffet, Menú sentado, Catering y Otro. El pax es informativo: no cambia las raciones.",
});
diapo({
  titulo: "Alérgenos, fichas y guardar",
  fig: "31",
  puntos: [
    "**Alérgenos del menú**: los de todas sus recetas.",
    "**Descargar fichas técnicas del menú** en Excel.",
    "**Guardar menú**, **Actualizar menú seleccionado** o **Duplicar menú seleccionado**.",
    "**Limpiar menú actual** vacía la pantalla, no borra nada.",
  ],
});
diapo({
  titulo: "Abrir un menú guardado",
  fig: "33",
  pasos: [
    "Abre **Menús guardados**.",
    "Elige el menú y pulsa **Cargar menú**.",
    "Borrar: **Eliminar menú** → escribe ELIMINAR.",
  ],
  notas: "Un menú usado en presupuestos o facturas no se puede eliminar. Las recetas nunca se borran al eliminar un menú.",
});

diapoSeccion("04", "Clientes", "Las fichas que usarás en presupuestos y facturas");
diapo({
  titulo: "Crear un cliente",
  fig: "41",
  pasos: [
    "Pestaña **Clientes** → **Nuevo cliente**.",
    "Rellena nombre, NIF/CIF, contacto y dirección.",
    "Pulsa **Guardar cliente**.",
  ],
  aviso: "Revisa nombre fiscal, NIF/CIF y dirección: salen en los documentos.",
  notas: "Ejemplo con datos inventados: Eventos Mediterráneo S.L.",
});
diapo({
  titulo: "Editar un cliente",
  fig: "40",
  pasos: [
    "En **Editar cliente**, abre **Clientes guardados**.",
    "Elige el cliente y cambia sus datos.",
    "Pulsa **Actualizar cliente**.",
  ],
  notas: "Eliminar cliente pide escribir ELIMINAR. No eliminar clientes con documentos asociados.",
});

diapoSeccion("05", "Presupuestos y facturas", "Del borrador al documento emitido");
{
  const s = nuevaDiapositiva("Cómo funciona un documento");
  const estados = [
    ["Borrador", "Editable, sin número", "Chef y gerente"],
    ["Emitido", "Número definitivo, no editable", "Gerente"],
    ["Cobrado / Anulado", "Fin del recorrido", "Gerente"],
  ];
  estados.forEach(([t, d, q], i) => {
    const x = 0.5 + i * 3.1;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y: 1.2, w: 2.8, h: 1.45, rectRadius: 0.1, fill: { color: i === 0 ? C.crema : C.marron }, line: { color: C.dorado, width: 1 }, objectName: `Estado ${t}` });
    s.addText(t, { x: x + 0.15, y: 1.3, w: 2.5, h: 0.45, fontFace: F_TIT, fontSize: 18, bold: true, color: i === 0 ? C.marron : C.blanco, margin: 0, isTextBox: true });
    s.addText(d, { x: x + 0.15, y: 1.78, w: 2.5, h: 0.4, fontFace: F_TXT, fontSize: 13, color: i === 0 ? C.texto : C.doradoClaro, margin: 0, isTextBox: true });
    s.addText(q, { x: x + 0.15, y: 2.18, w: 2.5, h: 0.35, fontFace: F_TXT, fontSize: 12, italic: true, color: i === 0 ? C.gris : C.doradoClaro, margin: 0, isTextBox: true });
    if (i < 2) s.addShape(pres.shapes.RIGHT_ARROW, { x: x + 2.83, y: 1.8, w: 0.24, h: 0.26, fill: { color: C.dorado }, line: { color: C.dorado }, objectName: "Flecha" });
  });
  const num = [["Presupuesto", "PRE-2026-0001"], ["Factura", "FAC-2026-0001"], ["Rectificativa", "REC-2026-0001"]];
  num.forEach(([t, n], i) => {
    const x = 0.5 + i * 3.1;
    s.addText(t, { x, y: 2.95, w: 2.8, h: 0.35, fontFace: F_TXT, fontSize: 13, color: C.gris, margin: 0, isTextBox: true });
    s.addText(n, { x, y: 3.25, w: 2.8, h: 0.45, fontFace: F_TIT, fontSize: 20, bold: true, color: C.dorado, margin: 0, isTextBox: true });
  });
  aviso(s, "Factura emitida: no se edita ni se anula → **rectificativa**. La app **no está certificada VERI*FACTU**.", { x: 0.5, y: 4.05, w: 9.0, h: 0.8, tam: 13 });
  s.addNotes("Numeración anual por organización y tipo: PRE-AAAA-NNNN, FAC-AAAA-NNNN, REC-AAAA-NNNN. Un presupuesto emitido sí puede anularse.");
}
diapo({
  titulo: "Documentos guardados",
  fig: "60",
  puntos: [
    "**Cargar documento**: abrirlo para ver o seguir editando.",
    "**Duplicar documento**: nuevo borrador a partir de él.",
    "**Crear factura desde presupuesto**: borrador de factura con sus menús.",
  ],
  notas: "Por ahora no se pueden eliminar documentos desde la app.",
});
diapo({
  titulo: "Crear un borrador",
  fig: "61",
  pasos: [
    "Elige **Cliente** y **Tipo de documento**.",
    "Revisa fechas, pago, retención e **IVA (%)**.",
    "Escribe el **Concepto**.",
    "Elige un menú y pulsa **Añadir menú**.",
    "Pulsa **Guardar borrador**.",
  ],
  notas: "El IVA viene por defecto de la organización. «Quitar último menú» y «Limpiar documento» para corregir. El número se asigna al emitir.",
});
diapo({
  titulo: "Si eres chef",
  figs: ["50", "51"],
  puntos: [
    "Preparas y guardas el **borrador** igual que el gerente.",
    "En lugar de **Emitir** verás: «Solo el gerente puede emitir el documento».",
    "Avisa a tu gerente cuando el borrador esté listo.",
  ],
});
diapo({
  titulo: "Emitir un documento",
  gerente: true,
  figs: ["62a", "62"],
  pasos: [
    "Rellena antes los **datos fiscales** de la organización.",
    "Carga el borrador guardado y revísalo.",
    "Pulsa **Emitir documento**.",
    "Verás el número asignado (PRE-2026-0001).",
  ],
  aviso: "Emitir **no se puede deshacer**.",
});
diapo({
  titulo: "Documento emitido y PDF",
  figs: ["63", "64"],
  puntos: [
    "Un documento emitido está en **solo lectura**.",
    "**Descargar PDF**: usa los datos guardados al emitir.",
    "El PDF lleva los datos fiscales y el logo de tu organización.",
  ],
});
diapo({
  titulo: "Factura y cobro",
  gerente: true,
  figs: ["65", "66"],
  pasos: [
    "Desde un presupuesto: **Crear factura desde presupuesto**.",
    "Guarda el borrador y pulsa **Emitir documento**.",
    "Al cobrar: **Marcar como cobrado**.",
  ],
});
diapo({
  titulo: "Corregir una factura: rectificativa",
  gerente: true,
  fig: "67",
  pasos: [
    "Carga la factura emitida.",
    "Pulsa **Crear rectificativa**.",
    "Tipo «Factura rectificativa» (fijo); corrige y pulsa **Actualizar borrador**.",
    "Pulsa **Emitir documento**: número **REC-AAAA-NNNN**.",
  ],
});
diapo({
  titulo: "Anular un presupuesto",
  gerente: true,
  figs: ["63", "68"],
  pasos: [
    "Carga el presupuesto emitido.",
    "Pulsa **Anular presupuesto** y confirma con **Sí, anular presupuesto**.",
    "Queda en estado **anulada**.",
  ],
  aviso: "Solo presupuestos. La anulación **no se puede deshacer**.",
});

diapoSeccion("06", "Funciones del gerente", "Miembros, datos de la organización, inventario y compartir");
diapo({
  titulo: "La página Gerente",
  gerente: true,
  fig: "70",
  pasos: [
    "En **Navegación**, elige **Gerente**.",
    "Pestañas: **Miembros e invitaciones**, **Datos de la organización**, **Inventario propio** y **Compartir recetas**.",
    "Para volver, elige **App**.",
  ],
});
diapo({
  titulo: "Miembros e invitaciones",
  gerente: true,
  fig: "72",
  pasos: [
    "**Invitaciones**: email, **Rol** y **Días de validez**.",
    "Pulsa **Generar invitación**.",
    "**Copia el código ahora**: no se vuelve a mostrar.",
    "**Revocar** anula una invitación pendiente.",
  ],
  notas: "En la pestaña Miembros se ve cada persona con su rol y estado; «Desactivar» le quita el acceso. En la captura, el código está oculto a propósito.",
});
diapo({
  titulo: "Datos de la organización y logo",
  gerente: true,
  fig: "74",
  pasos: [
    "Rellena razón social, **NIF/CIF** y dirección fiscal.",
    "Indica el **IVA por defecto (%)** y pulsa **Guardar datos**.",
    "Sube el logo (PNG, JPG o WEBP, máx. 300 KB).",
    "Pulsa **Guardar logo** (o **Quitar logo**).",
  ],
  notas: "Sin razón social, NIF/CIF y dirección no se puede emitir. El logo sale en la cabecera de la app y en los documentos.",
});
diapo({
  titulo: "Precios propios",
  gerente: true,
  fig: "75",
  pasos: [
    "**Inventario propio** → busca el ingrediente del catálogo.",
    "Escribe **Precio/unidad (€)** y **Merma (%)**.",
    "Pulsa **Guardar precio propio**.",
    "Tus recetas usarán tu precio.",
  ],
});
diapo({
  titulo: "Ingredientes privados",
  gerente: true,
  fig: "76",
  pasos: [
    "**Añadir ingrediente privado**: descripción, familia y unidad.",
    "**Obligatorio**: declara sus **Alérgenos** o marca «No contiene ninguno».",
    "Pulsa **Crear ingrediente privado** (código P-…).",
  ],
  aviso: "⚠️ = alérgenos **pendientes de revisión**. Revísalos antes de usarlos.",
  notas: "Un ingrediente privado en uso no se puede eliminar. Los que llegan al copiar recetas compartidas quedan pendientes de revisión.",
});
diapo({
  titulo: "Compartir recetas",
  gerente: true,
  figs: ["77", "78"],
  pasos: [
    "**Compartir recetas** → elige la receta.",
    "Elige el **Destino**: una organización o todas.",
    "Pulsa **Compartir**.",
    "**Comparticiones activas** → **Desactivar** para dejar de compartir.",
  ],
  notas: "Las otras organizaciones ven una vista previa sin precios y pueden hacer una copia independiente. En la captura 78 se ha ocultado el destino.",
});

seccion("Cierre");
{
  const s = nuevaDiapositiva("Preguntas frecuentes");
  const faq = [
    ["No veo «Gerente»", "Solo lo ven los gerentes. Prueba **Recargar permisos**."],
    ["No puedo emitir", "Solo el gerente, sobre un borrador guardado y con datos fiscales."],
    ["Error en una factura emitida", "Crea una **rectificativa**."],
    ["PVP o Food Cost en «-»", "Faltan cantidades o precios en los ingredientes."],
    ["Perdí un código de invitación", "Revoca la invitación y genera otra."],
    ["Aviso de alérgenos al copiar", "El gerente revisa los privados en **Inventario propio**."],
  ];
  faq.forEach(([q, a], i) => {
    const col = i % 2;
    const fila = Math.floor(i / 2);
    const x = 0.5 + col * 4.6;
    const y = 1.15 + fila * 1.3;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: 4.4, h: 1.15, rectRadius: 0.08, fill: { color: C.crema }, line: { color: C.doradoClaro, width: 1 }, objectName: `FAQ ${i + 1}` });
    s.addText(q, { x: x + 0.2, y: y + 0.1, w: 4.0, h: 0.4, fontFace: F_TXT, fontSize: 14, bold: true, color: C.marron, margin: 0, isTextBox: true });
    s.addText(conNegrita(a), { x: x + 0.2, y: y + 0.5, w: 4.0, h: 0.55, fontFace: F_TXT, fontSize: 13, color: C.texto, margin: 0, valign: "top", isTextBox: true });
  });
}
{
  const s = pres.addSlide({ masterName: "PORTADA", sectionTitle: "Cierre" });
  s.addText("Recuerda", { x: 0.7, y: 0.7, w: 8.6, h: 0.8, fontFace: F_TIT, fontSize: 36, bold: true, color: C.blanco, margin: 0, isTextBox: true });
  const lineas = [
    "Los **alérgenos** los revisa siempre el establecimiento: etiquetas, ingredientes privados y recetas copiadas.",
    "Un documento **emitido** no se modifica: las facturas se corrigen con **rectificativa**.",
    "La facturación **no está certificada VERI*FACTU**: consulta con tu gestoría.",
  ];
  lineas.forEach((t, i) => {
    const y = 1.75 + i * 1.0;
    s.addText(String(i + 1), { x: 0.7, y, w: 0.5, h: 0.5, shape: pres.shapes.OVAL, fill: { color: C.dorado }, color: C.blanco, bold: true, fontSize: 18, align: "center", valign: "middle", margin: 0, isTextBox: true });
    s.addText(conNegrita(t).map((r) => ({ text: r.text, options: { ...r.options, color: r.options.bold ? C.doradoClaro : C.blanco } })), {
      x: 1.45, y: y - 0.1, w: 7.9, h: 0.75, fontFace: F_TXT, fontSize: 17, valign: "middle", margin: 0, isTextBox: true,
    });
  });
  s.addText("Samirarte · Gestor de Escandallos", { x: 0.7, y: 4.85, w: 8.6, h: 0.35, fontFace: F_TXT, fontSize: 12, color: C.doradoClaro, margin: 0, isTextBox: true });
}

pres.writeFile({ fileName: SALIDA }).then(() => console.log(`Escrito ${SALIDA}`));
