"""Prepara las capturas para el manual (recortes y ocultación de datos).

Lee docs/manual/capturas/*.png y escribe en docs/manual/generador/_build/img/.
Si una captura no existe, no hace nada: el generador pondrá un marcador
"[Captura pendiente: …]" en su lugar.

Uso:  python docs/manual/generador/preparar_imagenes.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

RAIZ = Path(__file__).resolve().parents[3]
CAPTURAS = RAIZ / "docs" / "manual" / "capturas"
SALIDA = Path(__file__).resolve().parent / "_build" / "img"
ASSETS = RAIZ / "assets"

# nombre de salida -> (captura de origen, recorte (x0, y0, x1, y1) o None)
# Los recortes evitan zonas que en la captura muestran un estado provisional
# (p. ej. el campo "Estado" sin refrescar tras emitir) o repetidas.
RECORTES = {
    "62-emitido.png": ("62-emitido.png", (210, 55, 720, 175)),
    "62a-antes-de-emitir.png": ("62a-antes-de-emitir.png", (210, 570, 720, 750)),
    "63-documento-emitido.png": ("63-documento-emitido.png", (210, 572, 720, 750)),
    "65-factura-emitida.png": ("65-factura-emitida.png", (210, 548, 720, 740)),
    "66-marcar-cobrado.png": ("66-marcar-cobrado.png", (210, 40, 720, 100)),
    "68-anular-presupuesto.png": ("68-anular-presupuesto.png", (235, 45, 800, 110)),
    "61-presupuesto-borrador.png": ("61-presupuesto-borrador.png", (0, 0, 720, 612)),
    "61a-presupuesto-cabecera.png": ("61a-presupuesto-cabecera.png", (0, 0, 720, 700)),
    "31-menu-alergenos.png": ("30-menu-nuevo.png", (263, 675, 720, 935)),
    "22-descarga-ficha.png": ("16-alergenos-receta.png", (263, 540, 720, 745)),
    # La 67 muestra el identificador interno del borrador y los totales sin recalcular.
    "67-rectificativa.png": ("67-rectificativa.png", (211, 92, 720, 345)),
    # 79a: sin la barra lateral (sesión de un usuario real).
    "79a-recetas-chefs-conceder.png": ("79a-recetas-chefs-conceder.png", (263, 60, 720, 620)),
}

# Recortes para el PowerPoint: solo la zona de la pantalla de la que habla cada
# diapositiva, para que se lea sin ampliar la imagen. Se guardan como "ppt-<nombre>".
RECORTES_PPT = {
    "12-receta-nueva.png": (298, 60, 800, 440),
    "17b-ia-texto-resultado.png": (0, 190, 738, 910),
    "14-ficha-ingrediente.png": (0, 330, 720, 935),
    "15-costes-pvp.png": (263, 170, 720, 330),
    "16-alergenos-receta.png": (263, 535, 720, 700),
    "17-ia-generar-receta.png": (210, 330, 800, 530),
    "13-receta-ingredientes.png": (210, 130, 800, 700),
    "18-parametros-avanzados.png": (263, 440, 720, 760),
    "19-elaboracion.png": (263, 500, 720, 900),
    "20-recetas-guardadas.png": (263, 440, 720, 935),
    "21-ajuste-raciones.png": (177, 150, 590, 470),
    "30-menu-nuevo.png": (263, 100, 720, 680),
    "33-menu-cargar.png": (263, 180, 720, 640),
    "41-cliente-nuevo.png": (263, 180, 720, 770),
    "40-clientes-lista.png": (263, 380, 720, 935),
    "60-documentos-lista.png": (211, 140, 720, 480),
    "61-presupuesto-borrador.png": (211, 230, 720, 612),
    "71-miembros.png": (263, 200, 720, 330),
    "72-invitaciones.png": (298, 290, 800, 700),
    "73-datos-org.png": (298, 230, 800, 953),
    "74-logo-org.png": (298, 280, 800, 700),
    "75-inventario-propio.png": (263, 190, 720, 680),
    "76-ingrediente-privado.png": (263, 140, 720, 600),
    "77-compartir-receta.png": (263, 130, 720, 460),
    "00-portada.png": (84, 28, 628, 545),
    "01-login.png": (0, 350, 263, 700),
    "17d-ia-imagen-resultado.png": (0, 60, 720, 560),
    "17c-ia-imagen-subida.png": (0, 100, 720, 330),
    "50-chef-borrador.png": (211, 40, 720, 265),
    "51-chef-sin-emitir.png": (211, 335, 720, 470),
    "78-comparticiones-activas.png": (263, 130, 720, 370),
    "79a-recetas-chefs-conceder.png": (263, 60, 720, 620),
}

# Zonas a tapar (datos que no deben circular): código de invitación real.
OCULTAR = {
    "72-invitaciones.png": [((322, 662, 792, 700), "código de invitación oculto")],
    # La captura muestra el identificador interno de la organización destino.
    "78-comparticiones-activas.png": [((444, 296, 582, 362), "(oculto)")],
}


# Correos reales de producción sustituidos por correos de ejemplo:
# (caja a tapar, texto nuevo, color de fondo, color de texto, tamaño, (x, y) del texto).
_ROJO, _BLANCO = (255, 75, 75), (255, 255, 255)
SUSTITUIR = {
    "79a-recetas-chefs-conceder.png": [
        ((286, 336, 462, 361), "chef.ana@ejemplo.com  ×", _ROJO, _BLANCO, 12, (295, 341)),
        ((286, 462, 460, 488), "chef.luis@ejemplo.com  ×", _ROJO, _BLANCO, 12, (295, 468)),
        # Barra lateral (el recorte de 79a la deja fuera; por si se usa entera)
        ((40, 462, 250, 486), "gerente@ejemplo.com", (220, 240, 228), (40, 120, 70), 14, (42, 465)),
    ],
    "79b-recetas-chefs-permisos.png": [
        ((126, 262, 300, 288), "chef.ana@ejemplo.com", _BLANCO, (49, 51, 63), 11, (130, 268)),
        ((312, 262, 590, 288), "Todas las recetas de chef.luis@ejemplo.com", _BLANCO, (49, 51, 63), 11, (316, 268)),
    ],
    "79c-recetas-chefs-propietario.png": [
        ((24, 343, 300, 370), "chef.ana@ejemplo.com", (240, 242, 246), (49, 51, 63), 12, (28, 349)),
    ],
}


def _abrir(nombre):
    """Abre una captura y aplica las zonas ocultas y los correos sustituidos."""
    im = Image.open(CAPTURAS / nombre).convert("RGB")
    d = ImageDraw.Draw(im)
    for (caja, texto) in OCULTAR.get(nombre, []):
        d.rectangle(caja, fill=(225, 225, 225))
        d.text((caja[0] + 12, caja[1] + 9), texto, fill=(90, 90, 90), font=_fuente(15))
    for (caja, texto, fondo, color, tam, pos) in SUSTITUIR.get(nombre, []):
        d.rounded_rectangle(caja, radius=4, fill=fondo) if fondo == _ROJO else d.rectangle(caja, fill=fondo)
        d.text(pos, texto, fill=color, font=_fuente(tam))
    return im


def _fuente(tam):
    for nombre in ("DejaVuSans.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(nombre, tam)
        except OSError:
            continue
    return ImageFont.load_default()


def main():
    SALIDA.mkdir(parents=True, exist_ok=True)
    hechas = 0
    for png in sorted(CAPTURAS.glob("*.png")):
        im = _abrir(png.name)
        im.save(SALIDA / png.name, optimize=True)
        if png.name in RECORTES_PPT:
            im.crop(RECORTES_PPT[png.name]).save(SALIDA / f"ppt-{png.name}", optimize=True)
        hechas += 1
    for destino, (origen, caja) in RECORTES.items():
        ruta = CAPTURAS / origen
        if not ruta.exists():
            continue
        im = _abrir(origen)
        if caja:
            im = im.crop(caja)
        im.save(SALIDA / destino, optimize=True)
    # Logos de la marca, reducidos para no inflar los documentos.
    for nombre, tam in (("logo_fondo_blanco.png", 700), ("samirarte_logo_white.png", 700)):
        ruta = ASSETS / nombre
        if ruta.exists():
            im = Image.open(ruta)
            im.thumbnail((tam, tam))
            im.save(SALIDA / nombre, optimize=True)
    print(f"{hechas} capturas preparadas en {SALIDA}")


if __name__ == "__main__":
    main()
