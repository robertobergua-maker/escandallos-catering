import streamlit as st
import pandas as pd
import openpyxl
from openpyxl.styles import Font, Alignment, PatternFill
from openpyxl.utils import get_column_letter
import io
import base64
import json
from openai import OpenAI
from supabase import create_client, Client

# Configuración de página obligatoria al inicio de Streamlit
st.set_page_config(page_title="Gestor de Fichas Técnicas Cloud", page_icon="👨‍🍳", layout="wide")

# =============================================================================
# 🔑 INICIALIZACIÓN DE CONEXIONES CLOUD (SUPABASE Y OPENAI)
# =============================================================================
supabase_url = st.secrets.get("SUPABASE_URL", None)
supabase_key = st.secrets.get("SUPABASE_KEY", None)
api_key = st.secrets.get("OPENAI_API_KEY", None)

supabase_disponible = supabase_url is not None and supabase_key is not None

# Variable de cliente global para Supabase
supabase: Client = None
if supabase_disponible:
    try:
        supabase = create_client(supabase_url, supabase_key)
    except Exception as e:
        st.error(f"⚠️ Error al conectar con el cliente de Supabase: {e}")
        supabase_disponible = False

# Inicializar estado de sesión para el escandallo activo
if 'ingredientes' not in st.session_state:
    st.session_state['ingredientes'] = []

if 'raciones_base' not in st.session_state:
    st.session_state['raciones_base'] = 1.0

if 'raciones_deseadas' not in st.session_state:
    st.session_state['raciones_deseadas'] = 1.0

if 'factor_raciones' not in st.session_state:
    st.session_state['factor_raciones'] = 1.0

if 'ingredientes_base_raciones' not in st.session_state:
    st.session_state['ingredientes_base_raciones'] = st.session_state.get('ingredientes_originales_raciones', None)

if 'input_raciones_base' not in st.session_state:
    st.session_state['input_raciones_base'] = float(st.session_state['raciones_base'])

if 'input_raciones_deseadas' not in st.session_state:
    st.session_state['input_raciones_deseadas'] = float(st.session_state['raciones_deseadas'])

if 'sincronizar_inputs_raciones' not in st.session_state:
    st.session_state['sincronizar_inputs_raciones'] = False

# Trigger para invalidar caché de Supabase al editar el catálogo
if 'db_trigger' not in st.session_state:
    st.session_state['db_trigger'] = 0

# =============================================================================
# 📥 FUNCIÓN CACHÉ PARA CARGAR INVENTARIO DESDE SUPABASE
# =============================================================================
@st.cache_data(ttl=600)
def cargar_inventario_supabase(trigger):
    """
    Trae el listado de ingredientes de Supabase de forma segura.
    Se invalida automáticamente al cambiar el 'trigger'.
    """
    cols_deseadas = ["codigo", "familia", "descripcion", "merma", "precio_unidad"]
    if not supabase_disponible or supabase is None:
        return pd.DataFrame(columns=cols_deseadas)
    try:
        respuesta = (
            supabase
            .table("inventario")
            .select("codigo,familia,descripcion,merma,precio_unidad")
            .execute()
        )
        df = pd.DataFrame(respuesta.data)

        if df.empty:
            return pd.DataFrame(columns=cols_deseadas)

        df = df.loc[:, ~df.columns.duplicated()].copy()
        for col in cols_deseadas:
            if col not in df.columns:
                df[col] = 0.0 if col in ["merma", "precio_unidad"] else ""

        df = df[cols_deseadas].copy()
        df["codigo"] = df["codigo"].fillna("").astype(str).str.strip().str.upper()
        df["familia"] = df["familia"].fillna("").astype(str).str.strip()
        df["descripcion"] = df["descripcion"].fillna("").astype(str).str.strip()
        df["merma"] = pd.to_numeric(df["merma"], errors="coerce").fillna(0.0)
        df["precio_unidad"] = pd.to_numeric(df["precio_unidad"], errors="coerce").fillna(0.0)
        df = df.sort_values(by="descripcion")
        return df
    except Exception as e:
        st.error(f"Error al leer de Supabase: {e}")
        return pd.DataFrame(columns=cols_deseadas)

# Cargar inventario actual para autocompletado y contexto IA
inventario_df = cargar_inventario_supabase(st.session_state['db_trigger'])

# Convertir inventario a diccionario seguro para búsquedas rápidas en milisegundos sin KeyError
inventario_dict = {}
if not inventario_df.empty:
    for _, row in inventario_df.iterrows():
        codigo_raw = row.get("codigo", None)
        if codigo_raw is not None and pd.notna(codigo_raw):
            codigo_str = str(codigo_raw).strip().upper()
            inventario_dict[codigo_str] = {
                "familia": row.get("familia", "VARIOS"),
                "descripcion": row.get("descripcion", ""),
                "merma": float(row.get("merma", 0.0)) if pd.notna(row.get("merma")) else 0.0,
                "precio_unidad": float(row.get("precio_unidad", 0.0)) if pd.notna(row.get("precio_unidad")) else 0.0
            }

# =============================================================================
# 🧠 PROCESAMIENTO INTELIGENTE CON OPENAI GPT-4o
# =============================================================================
def procesar_con_openai(texto_plano=None, bytes_imagen=None, mime_type=None):
    """
    Envía la información a GPT-4o pasándole el inventario actual de Supabase como contexto.
    """
    if not api_key:
        st.error("❌ Error: No se ha encontrado la clave 'OPENAI_API_KEY' en los Secrets de Streamlit.")
        return []

    try:
        client = OpenAI(api_key=api_key)
        
        # Mandar un subconjunto ligero del catálogo real a la IA para optimizar la ventana de contexto
        catalogo_reducido = []
        for codigo, data in list(inventario_dict.items()):
            catalogo_reducido.append({
                "c": codigo,
                "d": data["descripcion"],
                "m": data["merma"],
                "p": data["precio_unidad"]
            })

        bd_contexto = json.dumps(catalogo_reducido, ensure_ascii=False)

        prompt_sistema = f'''Eres un experto en contabilidad hostelera de alta cocina. Tu trabajo consiste en procesar textos o imágenes de recetas, albaranes, facturas o capturas, y extraer los ingredientes para un escandallo técnico estructurado.

Dispones del catálogo completo de ingredientes reales de nuestra cocina en formato JSON de referencia:
{bd_contexto}

INSTRUCCIONES CRÍTICAS:
1. Compara semánticamente cada ingrediente detectado con el catálogo de referencia. Si encuentras una coincidencia clara (por ejemplo, "pollo" con "CUARTO POLLO ASADO" o "aceite oliva" con "ACEITE OLIVA"), asigna exactamente su "codigo" (parámetro "c") y usa su "descripcion", "merma" y "precio_unidad" correspondientes del catálogo.
2. Si el ingrediente analizado NO existe en el catálogo, invéntale un código único y nuevo corto que comience por "ING-" seguido de 4 números lógicos, asigna su descripción extraída y sus precios o mermas correspondientes.
3. Si el texto o la imagen presenta mermas implícitas (por ejemplo, Peso Bruto: 0.350, Peso Neto: 0.300), calcula la merma porcentual de forma precisa: ((bruto - neto)/bruto)*100.
4. Si detectas raciones de receta en expresiones como "6 porciones", "6 raciones", "para 6 personas", "serves 6" o "6 servings", devuelve ese número como "raciones_base".
5. Ignora títulos de columnas de cabecera de Excel, importes totales o subtotales de facturas.

REQUISITO EXCLUSIVO DE RESPUESTA: Devuelve ÚNICAMENTE JSON puro sin bloques de código markdown de tipo ```json y sin explicaciones adicionales.
Si detectas raciones base, devuelve un objeto:
{{
  "raciones_base": 6,
  "ingredientes": [
    {{"codigo": "ING-0019", "descripcion": "PECHUGA POLLO ENTERA FRESCA", "cantidad_bruta": 0.35, "merma": 14.29, "precio_unidad": 5.15}}
  ]
}}
Si no detectas raciones base, puedes devolver el array antiguo:
[
  {{"codigo": "ING-0019", "descripcion": "PECHUGA POLLO ENTERA FRESCA", "cantidad_bruta": 0.35, "merma": 14.29, "precio_unidad": 5.15}}
]'''

        contenido_usuario = []
        if texto_plano:
            contenido_usuario.append({
                "type": "text",
                "text": f"Analiza esta lista de ingredientes y estructúrala cruzando sus nombres con nuestra base de datos:\n\n{texto_plano}"
            })
        elif bytes_imagen:
            base64_image = base64.b64encode(bytes_imagen).decode('utf-8')
            contenido_usuario.append({
                "type": "text",
                "text": "Analiza esta imagen (puede ser un tique, albarán o factura) y extrae los ingredientes vinculando los códigos correctos del catálogo."
            })
            contenido_usuario.append({
                "type": "image_url",
                "image_url": {
                    "url": f"data:{mime_type};base64,{base64_image}"
                }
            })

        respuesta = client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": prompt_sistema},
                {"role": "user", "content": contenido_usuario}
            ],
            temperature=0.1
        )

        json_texto = respuesta.choices[0].message.content.strip()
        if json_texto.startswith("```"):
            json_texto = json_texto.split("\n", 1)[1].rsplit("\n", 1)[0].strip()
            if json_texto.startswith("json"):
                json_texto = json_texto[4:].strip()

        return json.loads(json_texto)

    except Exception as e:
        st.error(f"⚠️ Error al conectar con la Inteligencia Artificial de OpenAI: {str(e)}")
        return []


def normalizar_respuesta_ingredientes_ia(respuesta_ia):
    """
    Acepta el formato antiguo (lista) y el nuevo objeto con raciones_base.
    """
    if isinstance(respuesta_ia, list):
        return None, respuesta_ia
    if isinstance(respuesta_ia, dict):
        ingredientes = respuesta_ia.get("ingredientes", [])
        raciones_base = pd.to_numeric(respuesta_ia.get("raciones_base"), errors="coerce")
        raciones_base = None if pd.isna(raciones_base) or float(raciones_base) <= 0 else float(raciones_base)
        return raciones_base, ingredientes if isinstance(ingredientes, list) else []
    return None, []


def incorporar_ingredientes_ia(respuesta_ia):
    raciones_base_detectadas, nuevos = normalizar_respuesta_ingredientes_ia(respuesta_ia)
    if not nuevos:
        return False

    st.session_state['ingredientes'].extend(nuevos)
    st.session_state['ingredientes_base_raciones'] = [dict(ing) for ing in st.session_state['ingredientes']]
    st.session_state['factor_raciones'] = 1.0

    if raciones_base_detectadas is not None:
        st.session_state['raciones_base'] = raciones_base_detectadas
        st.session_state['raciones_deseadas'] = raciones_base_detectadas
        st.session_state['sincronizar_inputs_raciones'] = True

    return True


def marcar_receta_modificada_manualmente():
    st.session_state['ingredientes_base_raciones'] = None
    st.session_state['factor_raciones'] = 1.0


def sincronizar_inputs_raciones():
    if st.session_state.get('sincronizar_inputs_raciones', False):
        st.session_state['input_raciones_base'] = float(st.session_state['raciones_base'])
        st.session_state['input_raciones_deseadas'] = float(st.session_state['raciones_deseadas'])
        st.session_state['sincronizar_inputs_raciones'] = False

# =============================================================================
# 📊 GENERADOR DE EXCEL CON FÓRMULAS CONSOLIDADAS
# =============================================================================
def ajustar_ingredientes_por_raciones(ingredientes, factor):
    """
    Devuelve una copia de ingredientes ajustando solo la cantidad bruta.
    """
    ingredientes_ajustados = []
    for ing in ingredientes:
        ing_ajustado = dict(ing)
        cantidad = pd.to_numeric(ing_ajustado.get('cantidad_bruta', 0.0), errors='coerce')
        cantidad = 0.0 if pd.isna(cantidad) else float(cantidad)
        ing_ajustado['cantidad_bruta'] = cantidad * factor
        ingredientes_ajustados.append(ing_ajustado)
    return ingredientes_ajustados


def calcular_ajuste_raciones(ingredientes_base, raciones_base, raciones_deseadas):
    raciones_base_num = pd.to_numeric(raciones_base, errors='coerce')
    raciones_deseadas_num = pd.to_numeric(raciones_deseadas, errors='coerce')
    if pd.isna(raciones_base_num) or pd.isna(raciones_deseadas_num) or float(raciones_base_num) <= 0 or float(raciones_deseadas_num) <= 0:
        raise ValueError("Las raciones base y deseadas deben ser mayores que 0.")
    factor = float(raciones_deseadas_num) / float(raciones_base_num)
    return factor, ajustar_ingredientes_por_raciones(ingredientes_base, factor)


def generar_excel(
    nombre_plato,
    ingredientes,
    costes_indirectos_pct,
    margen_beneficio_pct,
    iva_pct,
    raciones_base=1.0,
    raciones_deseadas=1.0,
    factor_raciones=1.0
):
    wb = openpyxl.Workbook()
    wb.calculation.fullCalcOnLoad = True
    wb.calculation.forceFullCalc = True
    wb.calculation.calcMode = "auto"
    ws = wb.active
    ws.title = "Ficha Técnica"

    # Título Principal Estilizado en Azul Marino
    ws.merge_cells('A1:G1')
    titulo_cell = ws['A1']
    titulo_cell.value = f"FICHA TÉCNICA: {nombre_plato.upper()}"
    titulo_cell.font = Font(bold=True, size=14, color="FFFFFF")
    titulo_cell.fill = PatternFill(start_color="1F497D", end_color="1F497D", fill_type="solid")
    titulo_cell.alignment = Alignment(horizontal='center', vertical='center')
    ws.row_dimensions[1].height = 40

    # Datos de raciones usados para escalar la receta
    ws['A2'] = "Raciones base:"
    ws['B2'] = float(raciones_base)
    ws['D2'] = "Raciones calculadas / deseadas:"
    ws['E2'] = float(raciones_deseadas)
    ws['A3'] = "Factor de ajuste:"
    ws['B3'] = float(factor_raciones)
    for cell_ref in ['A2', 'D2', 'A3']:
        ws[cell_ref].font = Font(bold=True)
    ws['B2'].number_format = '#,##0.00'
    ws['E2'].number_format = '#,##0.00'
    ws['B3'].number_format = '#,##0.0000'

    # Cabeceras alineadas con la nueva columna Código
    headers = ['Código', 'Ingrediente', 'Cantidad Bruta (kg/l)', '% Merma', 'Peso Neto Real (kg/l)', 'Precio Unidad (€)', 'Coste Total (€)']
    header_row = 5
    start_row = 6
    for col_num, header in enumerate(headers, 1):
        ws.cell(row=header_row, column=col_num, value=header)
    col_idx = {header: idx for idx, header in enumerate(headers, 1)}
    col_letras = {header: get_column_letter(idx) for header, idx in col_idx.items()}
    
    for col_num, header in enumerate(headers, 1):
        cell = ws.cell(row=header_row, column=col_num)
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = PatternFill(start_color="2F75B5", end_color="2F75B5", fill_type="solid")
        cell.alignment = Alignment(horizontal='center', vertical='center')
    ws.row_dimensions[header_row].height = 25

    # Insertar registros y configurar fórmulas dinámicas
    for i, ing in enumerate(ingredientes):
        row = start_row + i
        ws.cell(row=row, column=col_idx['Código'], value=ing.get('codigo', 'S/C'))
        ws.cell(row=row, column=col_idx['Ingrediente'], value=ing.get('descripcion', ''))
        ws.cell(row=row, column=col_idx['Cantidad Bruta (kg/l)'], value=float(ing.get('cantidad_bruta', 0.0))).number_format = '#,##0.000'
        ws.cell(row=row, column=col_idx['% Merma'], value=float(ing.get('merma', 0.0))/100).number_format = '0.00%'
        ws.cell(
            row=row,
            column=col_idx['Peso Neto Real (kg/l)'],
            value=f"={col_letras['Cantidad Bruta (kg/l)']}{row}*(1-{col_letras['% Merma']}{row})",
        ).number_format = '#,##0.000'
        ws.cell(row=row, column=col_idx['Precio Unidad (€)'], value=float(ing.get('precio_unidad', 0.0))).number_format = '#,##0.00 €'
        ws.cell(
            row=row,
            column=col_idx['Coste Total (€)'],
            value=f"={col_letras['Cantidad Bruta (kg/l)']}{row}*{col_letras['Precio Unidad (€)']}{row}",
        ).number_format = '#,##0.00 €'

    last_row = start_row + len(ingredientes) - 1 if ingredientes else start_row
    res = last_row + 2
    total_col = col_idx['Coste Total (€)']
    total_col_letter = col_letras['Coste Total (€)']
    
    # Cálculos Financieros del Escandallo
    ws.cell(row=res, column=6, value="Subtotal Ingredientes:").font = Font(bold=True)
    ws.cell(row=res, column=total_col, value=f"=SUM({total_col_letter}{start_row}:{total_col_letter}{last_row})").number_format = '#,##0.00 €'

    ci = costes_indirectos_pct if costes_indirectos_pct is not None else 10.0
    mb = margen_beneficio_pct if margen_beneficio_pct is not None else 30.0
    iva = iva_pct if iva_pct is not None else 10.0

    ws.cell(row=res+1, column=6, value=f"Costes Indirectos ({ci}%):")
    ws.cell(row=res+1, column=total_col, value=f"={total_col_letter}{res}*({ci}/100)").number_format = '#,##0.00 €'

    ws.cell(row=res+2, column=6, value="COSTE TOTAL DEL PLATO:").font = Font(bold=True)
    ws.cell(row=res+2, column=total_col, value=f"={total_col_letter}{res}+{total_col_letter}{res+1}").number_format = '#,##0.00 €'

    ws.cell(row=res+4, column=6, value=f"Margen Deseado ({mb}%):").font = Font(bold=True)
    
    ws.cell(row=res+5, column=6, value="PRECIO VENTA (SIN IVA):").font = Font(bold=True)
    pvp_sin_iva = ws.cell(row=res+5, column=total_col, value=f"={total_col_letter}{res+2}/(1-({mb}/100))")
    pvp_sin_iva.number_format = '#,##0.00 €'
    pvp_sin_iva.font = Font(bold=True)

    ws.cell(row=res+6, column=6, value=f"IVA Aplicado ({iva}%):")
    iva_calc = ws.cell(row=res+6, column=total_col, value=f"={total_col_letter}{res+5}*({iva}/100)")
    iva_calc.number_format = '#,##0.00 €'

    ws.cell(row=res+7, column=6, value="PRECIO DE VENTA TOTAL (PVP):").font = Font(bold=True, color="FFFFFF")
    ws.cell(row=res+7, column=6).fill = PatternFill(start_color="375623", end_color="375623", fill_type="solid")
    
    pvp_total = ws.cell(row=res+7, column=total_col, value=f"={total_col_letter}{res+5}+{total_col_letter}{res+6}")
    pvp_total.number_format = '#,##0.00 €'
    pvp_total.font = Font(bold=True)
    pvp_total.fill = PatternFill(start_color="E2EFDA", end_color="E2EFDA", fill_type="solid")

    # Ajuste automático del ancho de las celdas para que no salgan truncadas (###)
    for col in ws.columns:
        max_len = 0
        col_idx = col[0].column
        col_letter = get_column_letter(col_idx)
        for cell in col:
            if cell.row == 1:
                continue
            if cell.value:
                max_len = max(max_len, len(str(cell.value)))
        ws.column_dimensions[col_letter].width = max(max_len + 3, 20)

    virtual_workbook = io.BytesIO()
    wb.save(virtual_workbook)
    virtual_workbook.seek(0)
    return virtual_workbook


# --- INTERFAZ GRÁFICA DE STREAMLIT ---
st.title("👨‍🍳 Gestor de Escandallos Inteligente con Supabase PostgreSQL")

# Panel lateral indicador de conexiones activas
with st.sidebar:
    st.header("⚙️ Estado de Conexiones Cloud")
    if supabase_disponible:
        st.success("⚡ Supabase: Conectado")
    else:
        st.warning("⚠️ Supabase: Desconectado. Configure 'SUPABASE_URL' y 'SUPABASE_KEY' en los Secrets.")
        
    if api_key:
        st.success("🤖 OpenAI GPT-4o: Activo")
    else:
        st.warning("⚠️ OpenAI: Desconectado. Configure 'OPENAI_API_KEY' en los Secrets.")
        
    st.divider()
    st.info("💡 Consejo: Al realizar modificaciones en la pestaña del Catálogo Supabase, haz clic en el botón 'Guardar Cambios en Supabase' para persistirlos en la nube de forma permanente.")

# Inputs generales del plato
col1, col2, col3, col4 = st.columns(4)
with col1:
    nombre_plato = st.text_input("📝 Nombre del Plato", value="Mi Receta")
with col2:
    costes_indirectos_pct = st.number_input("⚡ Costes Indirectos (%)", min_value=0.0, value=10.0)
with col3:
    margen_beneficio_pct = st.number_input("💰 Margen Beneficio (%)", min_value=0.0, max_value=99.9, value=30.0)
with col4:
    iva_pct = st.number_input("📊 IVA Evento (%)", min_value=0.0, max_value=100.0, value=10.0, step=1.0)

sincronizar_inputs_raciones()

col_r1, col_r2, col_r3, col_r4 = st.columns([1, 1, 1, 1])
with col_r1:
    raciones_base = st.number_input(
        "🍽️ Raciones base",
        min_value=0.0,
        step=1.0,
        key="input_raciones_base"
    )
with col_r2:
    raciones_deseadas = st.number_input(
        "🎯 Raciones deseadas",
        min_value=0.0,
        step=1.0,
        key="input_raciones_deseadas"
    )

st.session_state['raciones_base'] = float(raciones_base)
st.session_state['raciones_deseadas'] = float(raciones_deseadas)

factor_raciones_preview = raciones_deseadas / raciones_base if raciones_base > 0 and raciones_deseadas > 0 else 0.0
with col_r3:
    st.markdown(f"**Factor de ajuste:** {factor_raciones_preview:.4f}")
    if st.button("Ajustar escandallo a raciones"):
        if raciones_base <= 0 or raciones_deseadas <= 0:
            st.error("Las raciones base y deseadas deben ser mayores que 0.")
        elif not st.session_state['ingredientes']:
            st.warning("Añade ingredientes antes de ajustar el escandallo.")
        else:
            if st.session_state['ingredientes_base_raciones'] is None:
                st.session_state['ingredientes_base_raciones'] = [dict(ing) for ing in st.session_state['ingredientes']]
            ingredientes_base_ajuste = st.session_state['ingredientes_base_raciones']
            factor_raciones, ingredientes_ajustados = calcular_ajuste_raciones(
                ingredientes_base_ajuste,
                raciones_base,
                raciones_deseadas
            )
            st.session_state['ingredientes'] = ingredientes_ajustados
            st.session_state['factor_raciones'] = float(factor_raciones)
            st.success(f"Escandallo ajustado con factor {factor_raciones:.4f}.")
            st.rerun()
with col_r4:
    st.write("")
    st.write("")
    if st.button("Restablecer cantidades base"):
        if st.session_state['ingredientes_base_raciones'] is not None:
            st.session_state['ingredientes'] = [dict(ing) for ing in st.session_state['ingredientes_base_raciones']]
            st.session_state['ingredientes_base_raciones'] = None
            st.session_state['factor_raciones'] = 1.0
            st.success("Cantidades base restablecidas.")
            st.rerun()
        else:
            st.info("No hay cantidades base guardadas para restablecer.")

st.divider()

# Definición de pestañas (Tabs) principales de la aplicación
tab1, tab2, tab3, tab4 = st.tabs([
    "✍️ Entrada Manual / Código", 
    "📝 Copia y Pega Inteligente", 
    "📸 Escáner de Imagen (IA Vision)", 
    "🎒 Catálogo Supabase"
])

# -----------------------------------------------------------------------------
# TAB 1: ENTRADA MANUAL E IDENTIFICACIÓN POR CÓDIGO EN SUPABASE
# -----------------------------------------------------------------------------
with tab1:
    st.markdown("💡 **Tip:** Selecciona un código existente de tu base de datos y se auto-rellenarán la descripción, el precio y su merma.")
    
    opciones_codigo = [""] + list(inventario_dict.keys())
    
    with st.form("form_ingrediente", clear_on_submit=True):
        c_m0, c_m1, c_m2, c_m3, c_m4 = st.columns(5)
        
        # Desplegable predictivo de ingredientes
        cod_select = c_m0.selectbox(
            "Buscar por Código", 
            opciones_codigo, 
            format_func=lambda x: f"{x} - {inventario_dict[x]['descripcion']}" if x else "Seleccione un código..."
        )
        
        desc_man = c_m1.text_input("Ingrediente (Nuevo)", placeholder="Ej: Cebolla tierna")
        cant_man = c_m2.number_input("Cant. Bruta (kg/l)", min_value=0.0, step=0.001, format="%.3f", value=None, placeholder="0.000")
        merma_man = c_m3.number_input("% Merma", min_value=0.0, max_value=100.0, step=0.01, value=None, placeholder="0.00%")
        precio_man = c_m4.number_input("Precio Unidad (€)", min_value=0.0, step=0.01, format="%.2f", value=None, placeholder="0.00 €")
        
        if st.form_submit_button("Añadir al Escandallo"):
            # Si el usuario seleccionó un código del desplegable
            if cod_select:
                info_bd = inventario_dict[cod_select]
                st.session_state['ingredientes'].append({
                    'codigo': cod_select,
                    'descripcion': info_bd['descripcion'],
                    'cantidad_bruta': cant_man if cant_man is not None else 0.0,
                    'merma': info_bd['merma'],
                    'precio_unidad': info_bd['precio_unidad']
                })
                st.success(f"Ingrediente de Supabase añadido: {info_bd['descripcion']}")
            else:
                # Si es un ingrediente sin código en el inventario
                st.session_state['ingredientes'].append({
                    'codigo': "S/C",
                    'descripcion': desc_man if desc_man else "Ingrediente nuevo",
                    'cantidad_bruta': cant_man if cant_man is not None else 0.0,
                    'merma': merma_man if merma_man is not None else 0.0,
                    'precio_unidad': precio_man if precio_man is not None else 0.0
                })
            marcar_receta_modificada_manualmente()
            st.rerun()

# -----------------------------------------------------------------------------
# TAB 2: COPIA Y PEGA INTELIGENTE CON GPT-4o
# -----------------------------------------------------------------------------
with tab2:
    st.markdown("📋 **Pega cualquier bloque de texto:** Textos de correo de proveedores, chats de WhatsApp o filas de PDF.")
    texto_pegado = st.text_area("Pega tu texto aquí para analizar con IA:", height=150, placeholder="3 kg de pollo asado ING-0027...")
    
    if st.button("Analizar texto con IA", type="primary"):
        if texto_pegado:
            with st.spinner("La IA está leyendo y cruzando los datos con tu Supabase..."):
                nuevos = procesar_con_openai(texto_plano=texto_pegado)
                if incorporar_ingredientes_ia(nuevos):
                    st.rerun()

# -----------------------------------------------------------------------------
# TAB 3: ESCÁNER DE IMAGEN IA VISION (SOPORTE CTRL+V / DRAG & DROP)
# -----------------------------------------------------------------------------
with tab3:
    st.markdown("📸 **Arrastra o pega tu imagen:** Haz una captura de pantalla de tu factura u hoja física de albarán, y pulsa **Ctrl+V** directamente sobre este panel para subirla.")
    archivo_imagen = st.file_uploader("Sube, arrastra o pega (Ctrl+V) una foto de tu receta o factura (JPG/PNG)", type=['jpg', 'jpeg', 'png'])
    
    if archivo_imagen:
        if st.button("Escanear imagen con IA Vision", type="primary"):
            bytes_img = archivo_imagen.read()
            with st.spinner("Leyendo factura y asociando códigos de Supabase..."):
                nuevos = procesar_con_openai(bytes_imagen=bytes_img, mime_type=archivo_imagen.type)
                if incorporar_ingredientes_ia(nuevos):
                    st.rerun()

# -----------------------------------------------------------------------------
# TAB 4:🎒 GESTIÓN DEL CATÁLOGO DIRECTAMENTE EN SUPABASE (CRUD COMPLETO)
# -----------------------------------------------------------------------------
with tab4:
    st.subheader("🎒 Catálogo Relacional de Ingredientes en Supabase")
    st.markdown("Busca, añade, modifica o elimina productos de tu base de datos en la nube. **Los cambios realizados aquí se sincronizarán directamente en Postgres.**")
    
    if not inventario_df.empty:
        # Buscador ágil en la base de datos para no colapsar el rendimiento de la web
        busqueda = st.text_input("🔍 Buscar ingrediente por Código, Descripción o Familia:")
        df_filtrado = inventario_df.copy()
        
        if busqueda:
            df_filtrado = df_filtrado[
                df_filtrado["codigo"].str.contains(busqueda, case=False, na=False) |
                df_filtrado["descripcion"].str.contains(busqueda, case=False, na=False) |
                df_filtrado["familia"].str.contains(busqueda, case=False, na=False)
            ]
        
        # Grid editable conectado al catálogo
        catalogo_editado = st.data_editor(
            df_filtrado,
            num_rows="dynamic",
            use_container_width=True,
            column_config={
                "codigo": st.column_config.TextColumn("Código", help="ID único de Supabase", required=True),
                "familia": st.column_config.TextColumn("Familia / Categoría", help="Ej: CARNES, PESCADOS..."),
                "descripcion": st.column_config.TextColumn("Descripción / Ingrediente", required=True),
                "merma": st.column_config.NumberColumn("% Merma Estándar", format="%.2f %%", min_value=0.0, max_value=100.0),
                "precio_unidad": st.column_config.NumberColumn("Precio Proveedor (€)", format="%.2f €", min_value=0.0)
            },
            key="db_editor_component"
        )
        
        # Guardar cambios aplicados en el editor interactivo directo a Supabase
        if st.button("💾 Guardar Cambios en Supabase", type="primary"):
            editor_state = st.session_state.get("db_editor_component")
            if editor_state and supabase_disponible:
                with st.spinner("Sincronizando catálogo con Supabase..."):
                    try:
                        # 1. Procesar modificaciones de filas existentes
                        for row_idx_str, edits in editor_state.get("edited_rows", {}).items():
                            row_idx = int(row_idx_str)
                            fila_original = df_filtrado.iloc[row_idx]
                            original_code = fila_original["codigo"]
                            
                            datos_actualizados = {
                                "codigo": original_code,
                                "familia": edits.get("familia", fila_original.get("familia", "VARIOS")),
                                "descripcion": edits.get("descripcion", fila_original.get("descripcion", "")),
                                "merma": float(edits.get("merma", fila_original.get("merma", 0.0))),
                                "precio_unidad": float(edits.get("precio_unidad", fila_original.get("precio_unidad", 0.0)))
                            }
                            supabase.table("inventario").upsert(datos_actualizados).execute()

                        # 2. Procesar inserciones de ingredientes nuevos
                        for nueva_fila in editor_state.get("added_rows", []):
                            if "codigo" in nueva_fila and nueva_fila["codigo"]:
                                datos_nuevos = {
                                    "codigo": str(nueva_fila["codigo"]).strip().upper(),
                                    "familia": nueva_fila.get("familia", "VARIOS"),
                                    "descripcion": nueva_fila.get("descripcion", "Ingrediente Nuevo"),
                                    "merma": float(nueva_fila.get("merma", 0.0)),
                                    "precio_unidad": float(nueva_fila.get("precio_unidad", 0.0))
                                }
                                supabase.table("inventario").upsert(datos_nuevos).execute()

                        # 3. Procesar eliminaciones de ingredientes
                        for row_idx in editor_state.get("deleted_rows", []):
                            fila_original = df_filtrado.iloc[row_idx]
                            original_code = fila_original["codigo"]
                            supabase.table("inventario").delete().eq("codigo", original_code).execute()

                        st.success("¡Base de datos de Supabase actualizada con éxito! 🚀")
                        st.session_state['db_trigger'] += 1  # Forzar actualización de caché
                        st.rerun()
                    except Exception as e:
                        st.error(f"Error al sincronizar datos con Supabase: {e}")
            elif not supabase_disponible:
                st.error("❌ Supabase no está conectado correctamente.")
    else:
        st.info("💡 Tu tabla 'inventario' en Supabase está vacía o cargando datos...")

st.divider()

# =============================================================================
# 🛒 LISTA DE INGREDIENTES ACTIVA EN EL ESCANDALLO (EDITABLE AL VUELO)
# =============================================================================
if st.session_state['ingredientes']:
    st.subheader("🛒 Lista de Ingredientes de la Receta Activa")
    
    # Preparamos DataFrame de representación visual
    df_display = pd.DataFrame(st.session_state['ingredientes'])
    
    # Garantizar que existan las 5 columnas estructurales
    for col in ["codigo", "descripcion", "cantidad_bruta", "merma", "precio_unidad"]:
        if col not in df_display.columns:
            df_display[col] = 0.0 if col in ["cantidad_bruta", "merma", "precio_unidad"] else "S/C"
            
    df_display = df_display[["codigo", "descripcion", "cantidad_bruta", "merma", "precio_unidad"]]

    # Lanzamos el editor interactivo de la receta activa
    ingredientes_editados = st.data_editor(
        df_display,
        num_rows="dynamic",
        use_container_width=True,
        column_config={
            "codigo": st.column_config.TextColumn("Código", help="Código único del inventario", width="small"),
            "descripcion": st.column_config.TextColumn("Ingrediente", help="Descripción del producto", width="large"),
            "cantidad_bruta": st.column_config.NumberColumn("Cantidad Bruta (kg/l)", format="%.3f", min_value=0.0),
            "merma": st.column_config.NumberColumn("% Merma", format="%.2f %%", min_value=0.0, max_value=100.0),
            "precio_unidad": st.column_config.NumberColumn("Precio Unidad (€)", format="%.2f €", min_value=0.0)
        },
        key="editor_receta_activa"
    )
    
    # Casteo numérico robusto para que la suma de costes no falle nunca con floats
    for col in ["cantidad_bruta", "merma", "precio_unidad"]:
        ingredientes_editados[col] = pd.to_numeric(ingredientes_editados[col]).fillna(0.0)
        
    ingredientes_lista = ingredientes_editados.to_dict(orient='records')
    
    # Sincronizar el estado al vuelo
    if ingredientes_lista != st.session_state['ingredientes']:
        st.session_state['ingredientes'] = ingredientes_lista
        marcar_receta_modificada_manualmente()
        st.rerun()
        
    if st.button("Limpiar toda la receta"):
        st.session_state['ingredientes'] = []
        st.session_state['ingredientes_base_raciones'] = None
        st.session_state['factor_raciones'] = 1.0
        st.rerun()

    st.divider()

    # MÉTRIQUES FINANCIERAS EN TIEMPO REAL
    st.subheader(f"📊 Métricas y Estructuración de Costes: {nombre_plato}")
    subtotal_ing = sum(float(ing.get('cantidad_bruta', 0.0)) * float(ing.get('precio_unidad', 0.0)) for ing in st.session_state['ingredientes'])
    
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
    v4.metric("PVP Sugerido (Con IVA)", f"{pvp_final:.2f} €")

    st.divider()
    
    excel_virtual = generar_excel(
        nombre_plato,
        st.session_state['ingredientes'],
        ci_val,
        mb_val,
        iva_val,
        st.session_state['raciones_base'],
        st.session_state['raciones_deseadas'],
        st.session_state['factor_raciones']
    )
    st.download_button(
        label=f"📥 DESCARGAR FICHA EXCEL",
        data=excel_virtual,
        file_name=f"Ficha_{nombre_plato.replace(' ', '_')}.xlsx",
        mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        type="primary"
    )
else:
    st.info("💡 Empieza agregando ingredientes usando cualquiera de las pestañas de entrada superiores.")
