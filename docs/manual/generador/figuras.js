// Catálogo de figuras del manual (Word y PowerPoint).
//
// Cada figura apunta a una imagen de _build/img (la prepara preparar_imagenes.py
// a partir de docs/manual/capturas). Si la imagen no existe, o la figura está en
// REHACER, los generadores ponen un recuadro "[Captura pendiente: …]".
//
// Para sustituir un marcador: guarda la captura en docs/manual/capturas/ con el
// nombre indicado, quítala de REHACER si estaba, y vuelve a generar (ver README.md).

const fs = require("fs");
const path = require("path");

const IMG_DIR = path.join(__dirname, "_build", "img");

// Capturas que existen pero no deben usarse tal cual.
const REHACER = {};

const FIGURAS = {
  "00": { file: "00-portada.png", desc: "Portada con el botón «Entrar a la aplicación»" },
  "01": { file: "01-login.png", desc: "Acceso en la barra lateral: Entrar con Google, email y contraseña" },
  "10": { file: "10-inicio-sidebar.png", desc: "Pantalla principal del chef con la barra lateral" },
  "12": { file: "12-receta-nueva.png", desc: "Receta nueva: nombre, categoría, tipo de plato y raciones base" },
  "17b": { file: "17b-ia-texto-resultado.png", desc: "Tabla de ingredientes con cantidades y unidades" },
  "14": { file: "14-ficha-ingrediente.png", desc: "Ficha de ingrediente en la barra lateral" },
  "15": { file: "15-costes-pvp.png", desc: "Coste por ración, PVP por ración y Food Cost" },
  "16": { file: "16-alergenos-receta.png", desc: "Bloque «Alérgenos detectados»" },
  "17": { file: "17-ia-generar-receta.png", desc: "IA con texto: receta escrita antes de analizar" },
  "13": { file: "13-receta-ingredientes.png", desc: "Ingredientes rellenados por la IA a partir del texto" },
  "17c": { file: "17c-ia-imagen-subida.png", desc: "IA con imagen: foto de una receta subida, antes de escanear" },
  "17d": { file: "17d-ia-imagen-resultado.png", desc: "IA con imagen: ingredientes rellenados tras «Escanear imagen con IA Vision»" },
  "18": { file: "18-parametros-avanzados.png", desc: "Parámetros avanzados abiertos" },
  "19": { file: "19-elaboracion.png", desc: "Elaboración y observaciones, y botones de guardar" },
  "20": { file: "20-recetas-guardadas.png", desc: "Recetas guardadas con el selector desplegado" },
  "21": { file: "21-ajuste-raciones.png", desc: "Aviso de ajuste de raciones base (Confirmar ajuste / Cancelar)" },
  "22": { file: "22-descarga-ficha.png", desc: "Botón «Descargar ficha Excel»" },
  "22b": { file: "22b-ficha-excel.png", desc: "Ficha técnica abierta en Excel" },
  "23": { file: "23-recetas-compartidas.png", desc: "Recetas compartidas con mi organización y su vista previa" },
  "24a": { file: "24a-chef-recetas-solo-lectura.png", desc: "Recetas de otros chefs marcadas «de otro chef (solo lectura)»" },
  "24b": { file: "24b-chef-receta-solo-lectura.png", desc: "Receta en solo lectura: «Actualizar receta» desactivado" },
  "30": { file: "30-menu-nuevo.png", desc: "Menú con recetas añadidas y acciones por plato" },
  "31": { file: "31-menu-alergenos.png", desc: "Alérgenos del menú, descarga de fichas y botones de guardar" },
  "33": { file: "33-menu-cargar.png", desc: "Cargar un menú guardado" },
  "41": { file: "41-cliente-nuevo.png", desc: "Formulario «Nuevo cliente» relleno" },
  "40": { file: "40-clientes-lista.png", desc: "Editar cliente: selector de clientes guardados" },
  "60": { file: "60-documentos-lista.png", desc: "Documentos guardados (Cargar / Duplicar / Crear factura desde presupuesto)" },
  "61a": { file: "61a-presupuesto-cabecera.png", desc: "Cabecera del documento en borrador" },
  "61": { file: "61-presupuesto-borrador.png", desc: "Presupuesto en borrador con un menú añadido" },
  "50": { file: "50-chef-borrador.png", desc: "Borrador de presupuesto creado por el chef (sin número)" },
  "51": { file: "51-chef-sin-emitir.png", desc: "El chef ve «Solo el gerente puede emitir el documento»" },
  "62a": { file: "62a-antes-de-emitir.png", desc: "Botón «Emitir documento» en un borrador guardado" },
  "62": { file: "62-emitido.png", desc: "Mensaje tras emitir (PRE-2026-0001)" },
  "63": { file: "63-documento-emitido.png", desc: "Documento emitido: acciones disponibles" },
  "64": { file: "64-pdf-presupuesto.png", desc: "PDF del presupuesto descargado" },
  "65": { file: "65-factura-emitida.png", desc: "Factura emitida (FAC-2026-0001)" },
  "66": { file: "66-marcar-cobrado.png", desc: "Factura en estado cobrada" },
  "67": { file: "67-rectificativa.png", desc: "Borrador rectificativo: tipo «Factura rectificativa» y concepto" },
  "68": { file: "68-anular-presupuesto.png", desc: "Presupuesto anulado" },
  "70": { file: "70-nav-gerente.png", desc: "Navegación App / Gerente y página de gestión" },
  "71": { file: "71-miembros.png", desc: "Miembros de la organización" },
  "72": { file: "72-invitaciones.png", desc: "Generar una invitación (código oculto en la captura)" },
  "72b": { file: "72b-invitar-desde-archivo.png", desc: "Invitar chefs desde un archivo (CSV o Excel)" },
  "79a": { file: "79a-recetas-chefs-conceder.png", desc: "Recetas de chefs → Conceder acceso (correos de ejemplo)" },
  "79b": { file: "79b-recetas-chefs-permisos.png", desc: "Recetas de chefs → Permisos actuales (correos de ejemplo)" },
  "79c": { file: "79c-recetas-chefs-propietario.png", desc: "Recetas de chefs → Propietario de recetas (correo de ejemplo)" },
  "73": { file: "73-datos-org.png", desc: "Datos de la organización: datos fiscales" },
  "74": { file: "74-logo-org.png", desc: "Subir y guardar el logotipo" },
  "75": { file: "75-inventario-propio.png", desc: "Precio propio de un ingrediente del catálogo" },
  "76": { file: "76-ingrediente-privado.png", desc: "Añadir un ingrediente privado con sus alérgenos" },
  "77": { file: "77-compartir-receta.png", desc: "Compartir una receta con otra organización" },
  "78": { file: "78-comparticiones-activas.png", desc: "Comparticiones activas de la organización (destino oculto en la captura)" },
};

// Devuelve { id, desc, path|null, pendiente, nota } para una figura.
// Con { ppt: true } usa el recorte para diapositivas si existe.
function figura(id, { ppt = false } = {}) {
  const f = FIGURAS[id];
  if (!f) throw new Error(`Figura desconocida: ${id}`);
  const rutaPpt = path.join(IMG_DIR, `ppt-${f.file}`);
  const ruta = ppt && fs.existsSync(rutaPpt) ? rutaPpt : path.join(IMG_DIR, f.file);
  const rehacer = REHACER[f.file];
  const existe = fs.existsSync(ruta);
  return {
    id,
    desc: f.desc,
    file: f.file,
    path: existe && !rehacer ? ruta : null,
    pendiente: !existe || Boolean(rehacer),
    nota: rehacer || null,
  };
}

// Tamaño en píxeles de un PNG (cabecera IHDR).
function tamPng(ruta) {
  const b = fs.readFileSync(ruta);
  return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) };
}

module.exports = { figura, tamPng, IMG_DIR };
