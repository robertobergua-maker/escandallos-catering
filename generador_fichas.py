import streamlit as st
import openpyxl
from openpyxl.styles import Font, Alignment, PatternFill
from openpyxl.utils import get_column_letter
import io
import re

# Configuración de la página obligatoria al inicio
st.set_page_config(page_title="Gestor de Fichas Técnicas", page_icon="👨‍🍳", layout="wide")

# Inicializar de forma segura el estado de la sesión antes de cualquier renderizado
if 'ingredientes' not in st.session_state:
    st.session_state['ingredientes'] = []
if 'parse_feedback' not in st.session_state:
    st.session_state['parse_feedback'] = []

def normalizar_numero(valor, defecto=0.0):
    try:
        if valor is None:
            return defecto
        texto = str(valor).strip()
        if ',' in texto and '.' in texto:
            if texto.rfind(',') > texto.rfind('.'):
                texto = texto.replace('.', '').replace(',', '.')
            else:
                texto = texto.replace(',', '')
        else:
            texto = texto.replace(',', '.')
        return float(texto)
    except (TypeError, ValueError):
        return defecto

def parsear_ingredientes_desde_texto(texto):
    ingredientes = []
    errores = []

    if not texto:
        return ingredientes, errores

    unidades = r"kg|kilo(?:s)?|l|lt|litro(?:s)?|g|gr|gramo(?:s)?|ml|ud|uds|unidad(?:es)?|pack(?:s)?"
    patron_numero = re.compile(r"(?<![\w])\d+(?:[.,]\d+)*(?![\w])")
    patron_unidad = re.compile(rf"^\s*(?:{unidades})\b", re.IGNORECASE)
    patron_precio = re.compile(
        r"(?:€\s*(?P<precio_pre>\d+(?:[.,]\d+)*))|"
        r"(?:(?P<precio_post>\d+(?:[.,]\d+)*)\s*(?:€|eur|euro(?:s)?))",
        re.IGNORECASE,
    )
    patron_ruido_duro = re.compile(
        r"\b(?:page|pagina|página|total|invoice|factura|fecha|subtotal)\b",
        re.IGNORECASE,
    )
    patron_cabecera = re.compile(
        r"\b(?:descripcion|descripción|producto|ingrediente|cantidad|cant\.?|unidad|precio|"
        r"importe|merma|bruto|neto|coste|costo)\b",
        re.IGNORECASE,
    )
    patron_limpieza_descripcion = re.compile(
        rf"(?:€|%|\b(?:eur|euro(?:s)?|precio|price|merma|desperdicio|waste|"
        rf"{unidades})\b|\d+(?:[.,]\d+)*)",
        re.IGNORECASE,
    )

    def limpiar_linea(linea):
        linea = re.sub(r"[|;\t]+", " ", linea)
        linea = re.sub(r"\s+", " ", linea).strip()
        return linea

    def es_ruido(linea):
        if patron_ruido_duro.search(linea):
            return True
        tiene_numero = bool(patron_numero.search(linea))
        palabras = re.findall(r"\b[a-záéíóúüñ]+\b", linea.lower())
        if not tiene_numero and palabras and patron_cabecera.search(linea):
            palabras_cabecera = [palabra for palabra in palabras if patron_cabecera.fullmatch(palabra)]
            return len(palabras_cabecera) >= max(1, len(palabras) - 1)
        return False

    def numero_es_precio(match_numero, match_precio):
        if not match_precio:
            return False
        return (
            match_numero.start() >= match_precio.start()
            and match_numero.end() <= match_precio.end()
        )

    def buscar_precio(linea, numeros):
        match_precio = patron_precio.search(linea)
        if match_precio:
            precio_texto = match_precio.group('precio_pre') or match_precio.group('precio_post')
            return normalizar_numero(precio_texto), match_precio
        if numeros:
            ultimo = numeros[-1]
            return ultimo['valor'], None
        return 0.0, None

    def buscar_cantidad_bruta(linea, numeros, match_precio):
        candidatos = []
        for numero in numeros:
            texto_despues = linea[numero['fin']:]
            unidad_match = patron_unidad.match(texto_despues)
            if unidad_match:
                valor = numero['valor']
                unidad = unidad_match.group(0).strip().lower()
                if unidad in {'g', 'gr', 'gramo', 'gramos', 'ml'}:
                    valor = valor / 1000
                candidatos.append({**numero, 'valor': valor, 'unidad': unidad})

        if not candidatos:
            candidatos = [
                numero for numero in numeros
                if not numero_es_precio(numero['match'], match_precio)
            ]

        if not candidatos and numeros:
            candidatos = [numeros[0]]

        if len(candidatos) >= 2:
            primero, segundo = candidatos[0], candidatos[1]
            cantidad_bruta = max(primero['valor'], segundo['valor'])
            cantidad_neta = min(primero['valor'], segundo['valor'])
            merma = ((cantidad_bruta - cantidad_neta) / cantidad_bruta) * 100 if cantidad_bruta else 0.0
            return cantidad_bruta, merma

        if candidatos:
            return candidatos[0]['valor'], 0.0

        return 0.0, 0.0

    def limpiar_descripcion(linea):
        descripcion = patron_limpieza_descripcion.sub(" ", linea)
        descripcion = re.sub(r"[-_:,./()?]+", " ", descripcion)
        descripcion = re.sub(r"\s+", " ", descripcion).strip()
        return descripcion

    for num_linea, linea in enumerate(texto.splitlines(), start=1):
        linea = limpiar_linea(linea)
        if not linea:
            continue
        if es_ruido(linea):
            continue

        numeros = [
            {
                'texto': match.group(0),
                'valor': normalizar_numero(match.group(0)),
                'inicio': match.start(),
                'fin': match.end(),
                'match': match,
            }
            for match in patron_numero.finditer(linea)
        ]
        precio, match_precio = buscar_precio(linea, numeros)
        cantidad, merma = buscar_cantidad_bruta(linea, numeros, match_precio)
        descripcion = limpiar_descripcion(linea)

        if not numeros and descripcion:
            cantidad = 0.0
            precio = 0.0
            merma = 0.0
        if not descripcion:
            if numeros:
                errores.append(f"Línea {num_linea}: se encontraron números, pero falta el nombre del ingrediente.")
            continue

        ingredientes.append({
            'descripcion': descripcion,
            'cantidad_bruta': cantidad,
            'merma': max(0.0, min(100.0, merma)),
            'precio_unidad': precio
        })

    return ingredientes, errores

def extraer_texto_ocr(archivo_imagen):
    if archivo_imagen is None:
        return "", "Sube una imagen JPG o PNG para leerla."

    try:
        from PIL import Image
        imagen = Image.open(archivo_imagen)
    except Exception as exc:
        return "", f"No se pudo abrir la imagen: {exc}"

    try:
        import pytesseract
        texto = pytesseract.image_to_string(imagen, lang="spa+eng")
        if texto and texto.strip():
            return texto, None
    except Exception:
        pass

    try:
        import easyocr
        import numpy as np
        lector = easyocr.Reader(['es', 'en'], gpu=False)
        resultados = lector.readtext(np.array(imagen), detail=0, paragraph=True)
        texto = "\n".join(resultados)
        if texto.strip():
            return texto, None
    except Exception:
        pass

    return "", "No se pudo extraer texto. Instala/configura pytesseract o easyocr y prueba con una imagen más nítida."

def generar_excel(nombre_plato, ingredientes, costes_indirectos_pct, margen_beneficio_pct, iva_pct):
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Ficha Técnica"

    # Título principal en el Excel
    ws.merge_cells('A1:F1')
    titulo_cell = ws['A1']
    titulo_cell.value = f"FICHA TÉCNICA: {nombre_plato.upper()}"
    titulo_cell.font = Font(bold=True, size=14, color="FFFFFF")
    titulo_cell.fill = PatternFill(start_color="1F497D", end_color="1F497D", fill_type="solid")
    titulo_cell.alignment = Alignment(horizontal='center', vertical='center')
    ws.row_dimensions[1].height = 40

    ws.append([]) # Fila vacía

    # Encabezados
    headers = ['Ingrediente', 'Cantidad Bruta (kg/l)', '% Merma', 'Peso Neto Real (kg/l)', 'Precio Unidad (€)', 'Coste Total (€)']
    ws.append(headers)
    
    for col_num, header in enumerate(headers, 1):
        cell = ws.cell(row=3, column=col_num)
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = PatternFill(start_color="2F75B5", end_color="2F75B5", fill_type="solid")
        cell.alignment = Alignment(horizontal='center', vertical='center')
    ws.row_dimensions[3].height = 25

    # Agregar filas de datos
    start_row = 4
    for i, ing in enumerate(ingredientes):
        row = start_row + i
        ws.cell(row=row, column=1, value=ing['descripcion'])
        ws.cell(row=row, column=2, value=ing['cantidad_bruta']).number_format = '#,##0.000'
        ws.cell(row=row, column=3, value=ing['merma']/100).number_format = '0.00%'
        ws.cell(row=row, column=4, value=f"=B{row}*(1-C{row})").number_format = '#,##0.000'
        ws.cell(row=row, column=5, value=ing['precio_unidad']).number_format = '#,##0.00 €'
        ws.cell(row=row, column=6, value=f"=B{row}*E{row}").number_format = '#,##0.00 €'

    last_row = start_row + len(ingredientes) - 1 if ingredientes else start_row
    res = last_row + 2
    
    # Cálculos en celdas de Excel
    ws.cell(row=res, column=5, value="Subtotal Ingredientes:").font = Font(bold=True)
    ws.cell(row=res, column=6, value=f"=SUM(F4:F{last_row})").number_format = '#,##0.00 €'

    # Si vienen nulos o vacíos en el formulario, asignamos valores por defecto seguros para evitar errores en Excel
    ci = costes_indirectos_pct if costes_indirectos_pct is not None else 10.0
    mb = margen_beneficio_pct if margen_beneficio_pct is not None else 30.0
    iva = iva_pct if iva_pct is not None else 10.0

    ws.cell(row=res+1, column=5, value=f"Costes Indirectos ({ci}%):")
    ws.cell(row=res+1, column=6, value=f"=F{res}*({ci}/100)").number_format = '#,##0.00 €'

    ws.cell(row=res+2, column=5, value="COSTE TOTAL DEL PLATO:").font = Font(bold=True)
    ws.cell(row=res+2, column=6, value=f"=F{res}+F{res+1}").number_format = '#,##0.00 €'

    ws.cell(row=res+4, column=5, value=f"Margen Deseado ({mb}%):").font = Font(bold=True)
    
    ws.cell(row=res+5, column=5, value="PRECIO VENTA (SIN IVA):").font = Font(bold=True)
    pvp_sin_iva = ws.cell(row=res+5, column=6, value=f"=F{res+2}/(1-({mb}/100))")
    pvp_sin_iva.number_format = '#,##0.00 €'
    pvp_sin_iva.font = Font(bold=True)

    ws.cell(row=res+6, column=5, value=f"IVA Aplicado ({iva}%):")
    iva_calc = ws.cell(row=res+6, column=6, value=f"=F{res+5}*({iva}/100)")
    iva_calc.number_format = '#,##0.00 €'

    ws.cell(row=res+7, column=5, value="PRECIO DE VENTA TOTAL (PVP):").font = Font(bold=True, color="FFFFFF")
    ws.cell(row=res+7, column=5).fill = PatternFill(start_color="375623", end_color="375623", fill_type="solid")
    
    pvp_total = ws.cell(row=res+7, column=6, value=f"=F{res+5}+F{res+6}")
    pvp_total.number_format = '#,##0.00 €'
    pvp_total.font = Font(bold=True)
    pvp_total.fill = PatternFill(start_color="E2EFDA", end_color="E2EFDA", fill_type="solid")

    # Autoajuste de columnas protegiendo la fila 1
    for col in ws.columns:
        max_len = 0
        col_idx = col[0].column
        col_letter = get_column_letter(col_idx)
        for cell in col:
            if cell.row == 1:
                continue
            if cell.value:
                max_len = max(max_len, len(str(cell.value)))
        ws.column_dimensions[col_letter].width = max(max_len + 3, 22)

    virtual_workbook = io.BytesIO()
    wb.save(virtual_workbook)
    virtual_workbook.seek(0)
    return virtual_workbook

# --- INTERFAZ VISUAL ---
st.title("👨‍🍳 Asistente Financiero de Catering")
st.markdown("Generador automático de escandallos con control de mermas e IVA variable.")

# Configuración inicial (Usamos placeholders indicativos y limpiamos el valor inicial para que sea cómodo escribir)
col1, col2, col3, col4 = st.columns(4)
with col1:
    nombre_plato = st.text_input("📝 Nombre del Plato", value="Mi Receta")
with col2:
    costes_indirectos_pct = st.number_input("⚡ Costes Indirectos (%)", min_value=0.0, value=10.0)
with col3:
    margen_beneficio_pct = st.number_input("💰 Margen Beneficio (%)", min_value=0.0, max_value=99.9, value=30.0)
with col4:
    iva_pct = st.number_input("📊 IVA Evento (%)", min_value=0.0, max_value=100.0, value=10.0, step=1.0)

st.divider()

# Sección de Entrada de Ingredientes
st.subheader("✍️ Añadir ingredientes al plato")
for tipo_feedback, mensaje_feedback in st.session_state.get('parse_feedback', []):
    if tipo_feedback == 'success':
        st.success(mensaje_feedback)
    else:
        st.warning(mensaje_feedback)
st.session_state['parse_feedback'] = []

tab_manual, tab_texto, tab_ocr = st.tabs(["✍️ Manual", "📝 Texto Plano", "📸 Imagen OCR"])

with tab_manual:
    with st.form("form_ingrediente", clear_on_submit=True):
        c_m1, c_m2, c_m3, c_m4 = st.columns(4)
        desc_man = c_m1.text_input("Ingrediente", placeholder="Ej: Solomillo de Cerdo")
        
        # VALUE=NONE ELIMINA EL 0.00 SE QUEDA VACÍO HASTA QUE SE ESCRIBE
        cant_man = c_m2.number_input("Cant. Bruta (kg/l)", min_value=0.0, step=0.001, format="%.3f", value=None, placeholder="0.000")
        merma_man = c_m3.number_input("% Merma", min_value=0.0, max_value=100.0, step=1.0, value=None, placeholder="0%")
        precio_man = c_m4.number_input("Precio Unidad (€)", min_value=0.0, step=0.01, format="%.2f", value=None, placeholder="0.00 €")
        
        enviado = st.form_submit_button("Añadir Ingrediente")
        if enviado and desc_man:
            # Controlar si el usuario dejó vacíos los números para salvar la matemática de python
            c_bruta = cant_man if cant_man is not None else 0.0
            m_pct = merma_man if merma_man is not None else 0.0
            p_uni = precio_man if precio_man is not None else 0.0

            st.session_state['ingredientes'].append({
                'descripcion': desc_man,
                'cantidad_bruta': c_bruta,
                'merma': m_pct,
                'precio_unidad': p_uni
            })
            st.rerun()

with tab_texto:
    texto_ingredientes = st.text_area(
        "Pega una línea por ingrediente",
        placeholder="3 kg Solomillo 15% merma 12.50 price\n0,5 l Aceite de oliva 0% merma 6,80 €",
        height=180,
    )
    if st.button("Procesar texto plano", type="primary"):
        nuevos, errores = parsear_ingredientes_desde_texto(texto_ingredientes)
        if nuevos:
            st.session_state['ingredientes'].extend(nuevos)
            st.session_state['parse_feedback'] = [('success', f"Se añadieron {len(nuevos)} ingrediente(s).")]
            st.session_state['parse_feedback'].extend(('warning', error) for error in errores)
            st.rerun()
        else:
            st.warning("No se detectaron ingredientes válidos en el texto.")
        for error in errores:
            st.warning(error)

with tab_ocr:
    imagen_ingredientes = st.file_uploader(
        "Sube una imagen JPG o PNG con ingredientes",
        type=["jpg", "jpeg", "png"],
    )
    if imagen_ingredientes is not None:
        st.image(imagen_ingredientes, caption="Imagen cargada", use_container_width=True)

    if st.button("Leer imagen y añadir ingredientes", type="primary"):
        texto_ocr, error_ocr = extraer_texto_ocr(imagen_ingredientes)
        if error_ocr:
            st.warning(error_ocr)
        if texto_ocr:
            st.session_state['parse_feedback'] = []
            with st.expander("Texto detectado por OCR", expanded=False):
                st.text(texto_ocr)

            nuevos, errores = parsear_ingredientes_desde_texto(texto_ocr)
            if nuevos:
                st.session_state['ingredientes'].extend(nuevos)
                st.session_state['parse_feedback'] = [('success', f"Se añadieron {len(nuevos)} ingrediente(s) desde la imagen.")]
                st.session_state['parse_feedback'].extend(('warning', error) for error in errores)
                st.rerun()
            else:
                st.warning("No se detectaron ingredientes válidos en el texto de la imagen.")
            for error in errores:
                st.warning(error)

st.divider()

# Área de Resultados e Ingredientes
if st.session_state['ingredientes']:
    st.subheader("🛒 Lista de Ingredientes Agregados")
    st.dataframe(st.session_state['ingredientes'], use_container_width=True)
    
    if st.button("Limpiar todos los ingredientes"):
        st.session_state['ingredientes'] = []
        st.rerun()

    st.divider()

    # Bloque matemático de vista previa en web
    st.subheader(f"📊 Vista Previa del Escandallo: {nombre_plato}")
    subtotal_ing = sum(ing['cantidad_bruta'] * ing['precio_unidad'] for ing in st.session_state['ingredientes'])
    
    ci_val = costes_indirectos_pct if costes_indirectos_pct is not None else 0.0
    mb_val = margen_beneficio_pct if margen_beneficio_pct is not None else 0.0
    iva_val = iva_pct if iva_pct is not None else 0.0

    costes_ind = subtotal_ing * (ci_val / 100)
    coste_total = subtotal_ing + costes_ind
    
    factor_margen = (1 - (mb_val / 100))
    pvp_neto = coste_total / factor_margen if factor_margen > 0 else 0.0
    monto_iva = pvp_neto * (iva_val / 100)
    pvp_final = pvp_neto + monto_iva

    # Tarjetas informativas
    v1, v2, v3, v4 = st.columns(4)
    v1.metric("Materia Prima", f"{subtotal_ing:.2f} €")
    v2.metric("Costes Ind.", f"{costes_ind:.2f} €")
    v3.metric("COSTE TOTAL", f"{coste_total:.2f} €")
    v4.metric("PVP Sugerido", f"{pvp_final:.2f} €")

    st.divider()
    
    excel_virtual = generar_excel(nombre_plato, st.session_state['ingredientes'], ci_val, mb_val, iva_val)
    st.download_button(
        label=f"📥 DESCARGAR FICHA EXCEL",
        data=excel_virtual,
        file_name=f"Ficha_{nombre_plato.replace(' ', '_')}.xlsx",
        mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        type="primary"
    )
else:
    st.info("💡 Comienza agregando un ingrediente en el formulario superior para calcular el escandallo.")
