import streamlit as st
import openpyxl
from openpyxl.styles import Font, Alignment, PatternFill
from openpyxl.utils import get_column_letter
import io
import base64
import json
from openai import OpenAI

# Configuración obligatoria de la página al inicio
st.set_page_config(page_title="Gestor de Fichas Técnicas IA", page_icon="👨‍🍳", layout="wide")

# Inicializar el estado de la aplicación
if 'ingredientes' not in st.session_state:
    st.session_state['ingredientes'] = []

# Obtener la API Key de forma segura desde los Secrets de Streamlit
api_key = st.secrets.get("OPENAI_API_KEY", None)

def procesar_con_openai(texto_plano=None, bytes_imagen=None, mime_type=None):
    """
    Envía el texto plano o la imagen a GPT-4o para extraer ingredientes 
    en un formato JSON estructurado y limpio.
    """
    if not api_key:
        st.error("❌ Error de configuración: No se ha encontrado la clave 'OPENAI_API_KEY' en los Secrets de Streamlit.")
        return []

    try:
        client = OpenAI(api_key=api_key)
        
        # Instrucción del sistema (System Prompt) para asegurar la estructura exacta
        prompt_sistema = (
            "Eres un experto contable y chef de catering. Tu trabajo es analizar textos o imágenes de recetas, "
            "albaranes o facturas y extraer los ingredientes para un escandallo técnico.\n\n"
            "Debes ignorar por completo títulos de tablas, encabezados (como Bruto, Neto, Precio, Código), subtotales, IVA o totales de facturas.\n\n"
            "Calcula o extrae los siguientes campos obligatorios para cada ingrediente real:\n"
            "- 'descripcion': Nombre claro del ingrediente (ej: 'Cuarto de pollo asado').\n"
            "- 'cantidad_bruta': Peso o cantidad inicial en kg o litros (número decimal flotante).\n"
            "- 'merma': Porcentaje de merma estimado o calculado (número de 0 a 100). Si dispones de peso bruto y peso neto, "
            "calcúlalo como: ((bruto - neto) / bruto) * 100. Redondea a 2 decimales. Si no hay merma o no se puede calcular, devuelve 0.0.\n"
            "- 'precio_unidad': El coste por unidad de medida kg/litro (número decimal flotante). Ignora el coste total de la fila.\n\n"
            "REQUISITO CRÍTICO: Devuelve ÚNICAMENTE un array JSON puro, sin bloques de código markdown (no uses ```json), "
            "con esta estructura exacta:\n"
            "[{\"descripcion\": \"Nombre\", \"cantidad_bruta\": 0.35, \"merma\": 14.29, \"precio_unidad\": 6.00}]"
        )

        contenido_usuario = []

        if texto_plano:
            contenido_usuario.append({
                "type": "text",
                "text": f"Analiza este bloque de texto tabulado o desordenado y extrae los ingredientes:\n\n{texto_plano}"
            })
        
        elif bytes_imagen:
            base64_image = base64.b64encode(bytes_imagen).decode('utf-8')
            contenido_usuario.append({
                "type": "text",
                "text": "Analiza esta imagen (puede ser una factura, albarán o tabla de Excel) y extrae los ingredientes ordenando filas y columnas semánticamente."
            })
            contenido_usuario.append({
                "type": "image_url",
                "image_url": {
                    "url": f"data:{mime_type};base64,{base64_image}"
                }
            })

        # Llamada al modelo GPT-4o (multimodal, procesa texto e imágenes)
        respuesta = client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": prompt_sistema},
                {"role": "user", "content": contenido_usuario}
            ],
            temperature=0.1
        )

        # Limpiar y parsear la respuesta JSON
        json_texto = respuesta.choices[0].message.content.strip()
        # En caso de que el modelo use bloques de código a pesar de la orden:
        if json_texto.startswith("```"):
            json_texto = json_texto.split("\n", 1)[1].rsplit("\n", 1)[0].strip()
            if json_texto.startswith("json"):
                json_texto = json_texto[4:].strip()

        lista_ingredientes = json.loads(json_texto)
        return lista_ingredientes

    except Exception as e:
        st.error(f"⚠️ Error al conectar con la Inteligencia Artificial: {str(e)}")
        return []

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
st.title("👨‍🍳 Asistente Inteligente de Catering (GPT-4o)")
st.markdown("Carga tus recetas mediante texto o imágenes. La IA de OpenAI estructurará los datos automáticamente.")

if not api_key:
    st.info("💡 Consejo para el administrador: Configura tu 'OPENAI_API_KEY' en los Secrets de la plataforma Streamlit Cloud para activar los módulos inteligentes.")

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

tab1, tab2, tab3 = st.tabs(["✍️ Entrada Manual", "📝 Copia y Pega Inteligente", "📸 Escáner de Imagen (IA Vision)"])

# TAB 1: MANUAL
with tab1:
    with st.form("form_ingrediente", clear_on_submit=True):
        c_m1, c_m2, c_m3, c_m4 = st.columns(4)
        desc_man = c_m1.text_input("Ingrediente", placeholder="Ej: Solomillo de ternera")
        cant_man = c_m2.number_input("Cant. Bruta (kg/l)", min_value=0.0, step=0.001, format="%.3f", value=None, placeholder="0.000")
        merma_man = c_m3.number_input("% Merma", min_value=0.0, max_value=100.0, step=0.01, value=None, placeholder="0.00%")
        precio_man = c_m4.number_input("Precio Unidad (€)", min_value=0.0, step=0.01, format="%.2f", value=None, placeholder="0.00 €")
        
        if st.form_submit_button("Añadir Individualmente") and desc_man:
            st.session_state['ingredientes'].append({
                'descripcion': desc_man,
                'cantidad_bruta': cant_man if cant_man is not None else 0.0,
                'merma': merma_man if merma_man is not None else 0.0,
                'precio_unidad': precio_man if precio_man is not None else 0.0
            })
            st.rerun()

# TAB 2: COPIA Y PEGA CON IA
with tab2:
    st.markdown("📋 **Pega cualquier texto:** Un correo, un mensaje de WhatsApp desordenado, o filas sueltas de un Excel viejo. GPT-4o identificará los datos relevantes.")
    texto_pegado = st.text_area("Bloque de texto a analizar:", height=150, placeholder="He comprado 3 kilos de solomillo a 12.50€ el kilo. Además sal común 1 brik por 1.20€...")
    
    if st.button("Analizar texto con IA", type="primary"):
        if texto_pegado:
            with st.spinner("GPT-4o está leyendo y estructurando el texto..."):
                nuevos_ingredientes = procesar_con_openai(texto_plano=texto_pegado)
                if nuevos_ingredientes:
                    st.session_state['ingredientes'].extend(nuevos_ingredientes)
                    st.success(f"¡Se han añadido {len(nuevos_ingredientes)} ingredientes!")
                    st.rerun()

# TAB 3: IMAGEN CON IA VISION
with tab3:
    st.markdown("📸 **Sube una foto o captura:** Albaranes arrugados, fotos a pantallas de proveedores o capturas de PDFs. La IA Vision organizará las columnas sin importar el formato.")
    archivo_imagen = st.file_uploader("Sube una foto de tu receta o factura (JPG/PNG)", type=['jpg', 'jpeg', 'png'])
    
    if archivo_imagen:
        if st.button("Escanear imagen con IA Vision", type="primary"):
            bytes_img = archivo_imagen.read()
            with st.spinner("La IA Vision está analizando la estructura de la imagen..."):
                nuevos_ingredientes = procesar_con_openai(bytes_imagen=bytes_img, mime_type=archivo_imagen.type)
                if nuevos_ingredientes:
                    st.session_state['ingredientes'].extend(nuevos_ingredientes)
                    st.success(f"¡Se han extraído {len(nuevos_ingredientes)} ingredientes con éxito!")
                    st.rerun()

st.divider()

# MUESTRA DE RESULTADOS UNIFICADA
if st.session_state['ingredientes']:
    st.subheader("🛒 Lista de Ingredientes Agregados")

    ingredientes_editados = st.data_editor(
        st.session_state['ingredientes'],
        use_container_width=True,
        num_rows="dynamic",
        column_order=("descripcion", "cantidad_bruta", "merma", "precio_unidad"),
        column_config={
            "descripcion": st.column_config.TextColumn(
                "Ingrediente",
            ),
            "cantidad_bruta": st.column_config.NumberColumn(
                "Cantidad Bruta (kg/l)",
                format="%.3f",
                min_value=0.0,
                step=0.001,
            ),
            "merma": st.column_config.NumberColumn(
                "% Merma",
                format="%.2f %%",
                min_value=0.0,
                max_value=100.0,
                step=0.01,
            ),
            "precio_unidad": st.column_config.NumberColumn(
                "Precio Unidad (€)",
                format="%.2f €",
                min_value=0.0,
                step=0.01,
            ),
        },
        key="editor_ingredientes",
    )

    if hasattr(ingredientes_editados, "to_dict"):
        ingredientes_editados = ingredientes_editados.to_dict("records")

    st.session_state['ingredientes'] = [
        {
            'descripcion': str(ing.get('descripcion', '')).strip(),
            'cantidad_bruta': normalizar_numero(ing.get('cantidad_bruta')),
            'merma': normalizar_numero(ing.get('merma')),
            'precio_unidad': normalizar_numero(ing.get('precio_unidad')),
        }
        for ing in ingredientes_editados
        if str(ing.get('descripcion', '')).strip()
    ]
    
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
