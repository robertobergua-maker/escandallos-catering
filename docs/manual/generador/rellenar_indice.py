"""Rellena el índice (campo TOC) del Word con números de página.

docx-js deja el índice vacío y Word lo actualiza al abrir el fichero. Este paso
opcional lo deja ya relleno, para que también se vea en visores que no
actualizan campos (LibreOffice, vista previa del navegador, Google Drive…).
Los números de página se toman de una conversión a PDF con LibreOffice; Word los
recalcula igualmente al actualizar el índice.

Uso:  python rellenar_indice.py ../Manual_Gestor_Escandallos.docx [ruta_soffice]
Necesita LibreOffice (soffice) y pdftotext (poppler).
"""
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from html import escape
from pathlib import Path

ANCHO_TEXTO = 9638  # DXA, igual que en manual_docx.js
PAGINAS_SIN_NUMERO = 2  # portada e índice


def titulos(xml):
    """Lista (nivel, texto) de los párrafos Heading1/Heading2 en orden."""
    res = []
    for par in re.findall(r"<w:p>.*?</w:p>", xml, flags=re.S):
        m = re.search(r'<w:pStyle w:val="Heading([12])"/>', par)
        if not m:
            continue
        texto = "".join(re.findall(r"<w:t[^>]*>([^<]*)</w:t>", par))
        texto = texto.replace("SOLO GERENTE", "").strip()
        res.append((int(m.group(1)), texto))
    return res


def _norm(t):
    t = t.replace("&amp;", "&").replace("&quot;", '"').replace("&lt;", "<").replace("&gt;", ">")
    return re.sub(r"\s+", " ", t).strip().lower()


def paginas(docx, soffice):
    with tempfile.TemporaryDirectory() as tmp:
        perfil = Path(tmp, "perfil").as_uri()
        subprocess.run(
            [soffice, f"-env:UserInstallation={perfil}", "--headless", "--convert-to", "pdf", "--outdir", tmp, str(docx)],
            check=True, capture_output=True,
        )
        pdf = Path(tmp) / (Path(docx).stem + ".pdf")
        texto = subprocess.run(["pdftotext", "-layout", str(pdf), "-"], check=True, capture_output=True, text=True).stdout
    return [_norm(p) for p in texto.split("\f")]


def entrada(nivel, texto, pagina, primera):
    indent = 0 if nivel == 1 else 440
    negrita = "<w:b/>" if nivel == 1 else ""
    antes = 160 if nivel == 1 else 40
    inicio = (
        '<w:r><w:fldChar w:fldCharType="begin" w:dirty="true"/></w:r>'
        '<w:r><w:instrText xml:space="preserve">TOC \\h \\o "1-2"</w:instrText></w:r>'
        '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
    ) if primera else ""
    return (
        f'<w:p><w:pPr><w:tabs><w:tab w:val="right" w:leader="dot" w:pos="{ANCHO_TEXTO}"/></w:tabs>'
        f'<w:spacing w:before="{antes}" w:after="40"/><w:ind w:left="{indent}"/></w:pPr>'
        f"{inicio}"
        f'<w:r><w:rPr>{negrita}</w:rPr><w:t xml:space="preserve">{escape(texto, quote=False)}</w:t></w:r>'
        f'<w:r><w:rPr>{negrita}</w:rPr><w:tab/><w:t>{pagina}</w:t></w:r></w:p>'
    )


def main():
    docx = Path(sys.argv[1]).resolve()
    soffice = sys.argv[2] if len(sys.argv) > 2 else (shutil.which("soffice") or "soffice")
    with zipfile.ZipFile(docx) as z:
        partes = {n: z.read(n) for n in z.namelist()}
    xml = partes["word/document.xml"].decode("utf-8")

    pags = paginas(docx, soffice)
    entradas, desde = [], PAGINAS_SIN_NUMERO
    for nivel, texto in titulos(xml):
        clave = _norm(texto)[:40]
        for i in range(desde, len(pags)):
            if clave in pags[i]:
                desde = i
                break
        else:
            print(f"Aviso: no encuentro «{texto}» en el PDF")
        entradas.append((nivel, texto, desde + 1 - PAGINAS_SIN_NUMERO))

    vacio = re.search(
        r'<w:sdtContent><w:p><w:r><w:fldChar w:fldCharType="begin"[^>]*/>.*?'
        r'<w:fldChar w:fldCharType="end"/></w:r></w:p></w:sdtContent>',
        xml, flags=re.S,
    )
    if not vacio:
        sys.exit("No encuentro el índice vacío (¿ya estaba relleno?)")
    cuerpo = "".join(entrada(n, t, p, i == 0) for i, (n, t, p) in enumerate(entradas))
    cuerpo += '<w:p><w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>'
    xml = xml[: vacio.start()] + "<w:sdtContent>" + cuerpo + "</w:sdtContent>" + xml[vacio.end():]
    partes["word/document.xml"] = xml.encode("utf-8")

    tmp = docx.with_suffix(".tmp")
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
        for n, datos in partes.items():
            z.writestr(n, datos)
    tmp.replace(docx)
    print(f"Índice relleno con {len(entradas)} entradas")


if __name__ == "__main__":
    main()
