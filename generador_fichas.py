import streamlit as st
import openpyxl
from openpyxl.styles import Font, Alignment, PatternFill
from openpyxl.utils import get_column_letter
import io
import re

# Configuración de la página obligatoria al inicio
st.set_page_config(page_title="Gestor de Fichas Técnicas", page_icon="👨‍🍳", layout="wide")

if 'ingredientes' not in st.session_state:
    st.session_state['ingredientes'] = []

def parsear_linea_inteligente(linea):
    """
    Analiza una línea de texto plano o una línea reconstruida de OCR
    de forma agnóstica para extraer Nombre, Cantidad Bruta, Merma y Precio.
    """
    # Limpieza de ruido de tablas y encabezados
    linea_clean = linea.strip()
    palabras_ruido = ["nombre", "plato", "categoria", "valoracion", "salsa", "guarnicion", 
                      "articulos", "codigo", "descripcion", "cantidad", "bruto", "neto", 
                      "kilos", "unidad", "precio", "coste", "servicio", "peso"]
    
    if any(ruido in linea_clean.lower() for ruido in palabras_ruido) or len(linea_clean) < 3:
        return None

    # Encontrar todos los números (incluyendo decimales con comas o puntos)
    numeros_str = re.findall(r'\d+[\.,]\d+|\d+', linea_clean)
    numeros = []
    for n in numeros_str:
        try:
            numeros.append(float(n.replace(',', '.')))
        except:
            pass

    # Si no hay números, no podemos escandallar la fila
    if not numeros:
        return None

    # Extraer el nombre del ingrediente (todo el texto antes del primer número)
    primer_num_idx = linea_clean.find(numeros_str[0])
    nombre = linea_clean[:primer_num_idx].strip()
    
    # Limpiar caracteres sueltos o símbolos del nombre
    nombre = re.sub(r'^[^\w]+|[^\w]+$', '', nombre).strip()
    # Quitar unidades sueltas del final del nombre
    nombre = re.sub(r'\b(kg|l|g|gr|ml|ud|uds)\b$', '', nombre, flags=re.IGNORECASE).strip()

    if not nombre or len(nombre) < 2:
        return None

    # Heurística numérica basada en la cantidad de valores encontrados
    cantidad_bruta = 0.0
    merma = 0.0
    precio_unidad = 0.0

    if len(numeros) >= 3:
        # Formato: Bruto, Neto, Precio (Ignoramos el 4º si es el coste total de la fila)
        bruto = numeros[0]
        neto = numeros[1]
        precio_unidad = numeros[2]
        
        # Corrección si el OCR se comió el "0," (ej: "350" -> 0.350)
        if bruto > 50 and bruto % 1 != 0: # Si es un entero grande sospechoso de gramos
            pass 
        elif bruto >= 100 and bruto.is_integer():
            bruto = bruto / 1000
            neto = neto / 1000 if neto >= 100 else neto

        cantidad_bruta = bruto
        if bruto > 0 and bruto >= neto:
            merma = ((bruto - neto) / bruto) * 100
        else:
            merma = 0.0
            
    elif len(numeros) == 2:
        # Formato: Cantidad y Precio
        cantidad_bruta = numeros[0]
        precio_unidad = numeros[1]
        merma = 0.0
    else:
        # Solo precio
        precio_unidad = numeros[0]

    return {
        'descripcion': nombre,
        'cantidad_bruta': cantidad_bruta,
        'merma': merma,
        'precio_unidad': precio_unidad
    }

def generar_excel(nombre_plato, ingredientes, costes_indirectos_pct, margen_beneficio_pct, iva_pct):
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Ficha Técnica"

    ws.merge_cells('A1:F1')
    titulo_cell = ws['A1']
    titulo_cell.value = f"FICHA TÉCNICA: {nombre_plato.upper()}"
    titulo_cell.font = Font(bold=True, size=14, color="FFFFFF")
    titulo_cell.fill = PatternFill(start_color="1F497D", end_color="1F497D", fill_type="solid")
    titulo_cell.alignment = Alignment(horizontal='center', vertical='center')
    ws.row_dimensions[1].height = 40

    ws.append([])

    headers = ['Ingrediente', 'Cantidad Bruta (kg/l)', '% Merma', 'Peso Neto Real (kg/l)', 'Precio Unidad (€)', 'Coste Total (€)']
    ws.append(headers)
    
    for col_num, header in enumerate(headers, 1):
        cell = ws.cell(row=3, column=col_num)
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = PatternFill(start_color="2F75B5", end_color="2F75B5", fill_type="solid")
        cell.alignment = Alignment(horizontal='center', vertical='center')
    ws.row_dimensions[3].height = 25

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
    
    ws.cell(row=res, column=5, value="Subtotal Ingredientes:").font = Font(bold=True)
    ws.cell(row=res, column=6, value=f"=SUM(F4:F{last_row})").number_format = '#,##0.00 €'

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

# --- INTERFAZ DE USUARIO ---
st.title("👨‍🍳 Asistente Financiero de Catering")
st.markdown("Generador automático de escandallos adaptativo.")

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

tab1, tab2, tab3 = st.tabs(["✍️ Manual", "📝 Copia y Pega (Texto/Excel)", "📸 Imagen OCR"])

# TAB 1: MANUAL
with tab1:
    with st.form("form_ingrediente", clear_on_submit=True):
        c_m1, c_m2, c_m3, c_m4 = st.columns(4)
        desc_man = c_m1.text_input("Ingrediente", placeholder="Ej: Solomillo")
        cant_man = c_m2.number_input("Cant. Bruta (kg/l)", min_value=0.0, step=0.001, format="%.3f", value=None, placeholder="0.000")
        merma_man = c_m3.number_input("% Merma", min_value=0.0, max_value=100.0, step=1.0, value=None, placeholder="0%")
        precio_man = c_m4.number_input("Precio Unidad (€)", min_value=0.0, step=0.01, format="%.2f", value=None, placeholder="0.00 €")
        
        if st.form_submit_button("Añadir Individualmente") and desc_man:
            st.session_state['ingredientes'].append({
                'descripcion': desc_man,
                'cantidad_bruta': cant_man if cant_man is not None else 0.0,
                'merma': merma_man if merma_man is not None else 0.0,
                'precio_unidad': precio_man if precio_man is not None else 0.0
            })
            st.rerun()

# TAB 2: COPIA Y PEGA DESDE EXCEL
with tab2:
    st.markdown("💡 **Truco profesional:** Abre tu Excel, selecciona las filas de tus ingredientes, dale a **Copiar** y pégalas aquí dentro. El sistema mantendrá las líneas unidas de forma perfecta.")
    texto_pegado = st.text_area("Pega aquí las filas de tu receta o tabla:", height=150, placeholder="cuarto de pollo asado\t0,350\t0,300\tkg\t6,000 €")
    
    if st.button("Procesar Bloque de Texto", type="secondary"):
        if texto_pegado:
            lineas = texto_pegado.split('\n')
            contador = 0
            for l in lineas:
                resultado = parsear_linea_inteligente(l)
                if resultado:
                    st.session_state['ingredientes'].append(resultado)
                    contador += 1
            if contador > 0:
                st.success(f"¡Se añadieron {contador} ingredientes con éxito!")
                st.rerun()
            else:
                st.warning("No pudimos identificar ingredientes válidos en ese formato. Revisa el texto.")

# TAB 3: IMAGEN OCR CON RECONSTRUCCIÓN DE FILAS
with tab3:
    archivo_imagen = st.file_uploader("Sube una foto de tu receta o tabla (JPG/PNG)", type=['jpg', 'jpeg', 'png'])
    if archivo_imagen:
        import easyocr
        from PIL import Image
        import numpy as np
        
        with st.spinner("La Inteligencia Artificial está ordenando las filas de la tabla..."):
            img = Image.open(archivo_imagen)
            reader = easyocr.Reader(['es'])
            # Obtener coordenadas de cada bloque de texto
            resultados_ocr = reader.readtext(np.array(img))
            
            # AGRUPACIÓN POR COORDENADAS VERTICALES (Y)
            # Agrupamos los bloques de texto que están en la misma franja de altura (tolerancia de 15 píxeles)
            lineas_reconstruidas = {}
            for (bbox, text, prob) in resultados_ocr:
                y_centro = (bbox[0][1] + bbox[2][1]) / 2
                # Buscar si ya existe una línea en esa altura aproximada
                encontrada = False
                for y_base in lineas_reconstruidas.keys():
                    if abs(y_centro - y_base) < 15:
                        lineas_reconstruidas[y_base].append((bbox[0][0], text))
                        encontrada = True
                        break
                if not encontrada:
                    lineas_reconstruidas[y_centro] = [(bbox[0][0], text)]
            
            # Ordenar horizontalmente cada línea y procesar
            contador_ocr = 0
            for y_base in sorted(lineas_reconstruidas.keys()):
                # Ordenar de izquierda a derecha por la coordenada X
                bloques_ordenados = sorted(lineas_reconstruidas[y_base], key=lambda x: x[0])
                texto_linea = " ".join([b[1] for b in bloques_ordenados])
                
                res_ocr = parsear_linea_inteligente(texto_linea)
                if res_ocr:
                    st.session_state['ingredientes'].append(res_ocr)
                    contador_ocr += 1
            
            if contador_ocr > 0:
                st.success(f"¡Se cargaron {contador_ocr} ingredientes desde la imagen de forma alineada!")
                st.rerun()
            else:
                st.error("No logramos alinear las columnas de esta foto de forma segura. Prueba el Copia y Pega de la pestaña de texto.")

st.divider()

# MUESTRA DE RESULTADOS UNIFICADA
if st.session_state['ingredientes']:
    st.subheader("🛒 Lista de Ingredientes Agregados")
    st.dataframe(st.session_state['ingredientes'], use_container_width=True)
    
    if st.button("Limpiar todos los ingredientes"):
        st.session_state['ingredientes'] = []
        st.rerun()

    st.divider()

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
    st.info("💡 Comienza agregando ingredientes usando cualquiera de las 3 pestañas superiores.")