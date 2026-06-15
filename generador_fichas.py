import streamlit as st
import pandas as pd
import openpyxl
from openpyxl.styles import Font, Alignment, PatternFill
from openpyxl.utils import get_column_letter
import io
import base64
import json
import re
import unicodedata
from difflib import SequenceMatcher
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

if 'receta_nombre' not in st.session_state:
    st.session_state['receta_nombre'] = st.session_state.get('nombre_plato', "Mi Receta")

if 'receta_raciones_base' not in st.session_state:
    st.session_state['receta_raciones_base'] = float(st.session_state['raciones_base'])

if 'receta_raciones_deseadas' not in st.session_state:
    st.session_state['receta_raciones_deseadas'] = float(st.session_state['raciones_deseadas'])

if 'input_nombre_plato' not in st.session_state:
    st.session_state['input_nombre_plato'] = st.session_state['receta_nombre']

if 'input_raciones_base' not in st.session_state:
    st.session_state['input_raciones_base'] = float(st.session_state['receta_raciones_base'])

if 'input_raciones_deseadas' not in st.session_state:
    st.session_state['input_raciones_deseadas'] = float(st.session_state['receta_raciones_deseadas'])

if 'sincronizar_inputs_raciones' not in st.session_state:
    st.session_state['sincronizar_inputs_raciones'] = False

if 'sincronizar_campos_receta' not in st.session_state:
    st.session_state['sincronizar_campos_receta'] = False

if 'raciones_base_aplicadas' not in st.session_state:
    st.session_state['raciones_base_aplicadas'] = float(st.session_state['raciones_base'])

if 'raciones_deseadas_aplicadas' not in st.session_state:
    st.session_state['raciones_deseadas_aplicadas'] = float(st.session_state['raciones_deseadas'])

# Trigger para invalidar caché de Supabase al editar el catálogo
if 'db_trigger' not in st.session_state:
    st.session_state['db_trigger'] = 0

if 'nombre_plato' not in st.session_state:
    st.session_state['nombre_plato'] = st.session_state['receta_nombre']

if 'receta_categoria' not in st.session_state:
    st.session_state['receta_categoria'] = ""

if 'input_receta_categoria' not in st.session_state:
    st.session_state['input_receta_categoria'] = st.session_state['receta_categoria']

if 'receta_tipo_plato' not in st.session_state:
    st.session_state['receta_tipo_plato'] = ""

if 'input_receta_tipo_plato' not in st.session_state:
    st.session_state['input_receta_tipo_plato'] = st.session_state['receta_tipo_plato']

if 'receta_observaciones' not in st.session_state:
    st.session_state['receta_observaciones'] = ""

if 'input_receta_observaciones' not in st.session_state:
    st.session_state['input_receta_observaciones'] = st.session_state['receta_observaciones']

if 'receta_id_cargada' not in st.session_state:
    st.session_state['receta_id_cargada'] = None

if 'codigo_receta_cargada' not in st.session_state:
    st.session_state['codigo_receta_cargada'] = ""

if 'costes_indirectos_pct' not in st.session_state:
    st.session_state['costes_indirectos_pct'] = 10.0

if 'margen_beneficio_pct' not in st.session_state:
    st.session_state['margen_beneficio_pct'] = 30.0

if 'iva_pct' not in st.session_state:
    st.session_state['iva_pct'] = 10.0

if 'menu_actual' not in st.session_state:
    st.session_state['menu_actual'] = []
if 'menu_id' not in st.session_state:
    st.session_state['menu_id'] = None
if 'sincronizar_campos_menu' not in st.session_state:
    st.session_state['sincronizar_campos_menu'] = False
if 'menu_comensales_raciones_sync' not in st.session_state:
    st.session_state['menu_comensales_raciones_sync'] = None

# =============================================================================
# 📥 FUNCIÓN CACHÉ PARA CARGAR INVENTARIO DESDE SUPABASE
# =============================================================================
@st.cache_data(ttl=600)
def cargar_inventario_supabase(trigger):
    """
    Trae el listado de ingredientes de Supabase de forma segura.
    Se invalida automáticamente al cambiar el 'trigger'.
    """
    cols_deseadas = [
        "codigo", "familia", "descripcion", "unidad_medida", "merma", "precio_unidad",
        "proveedor_precio", "formato_compra", "cantidad_formato_compra",
        "unidad_formato_compra", "precio_formato_compra", "fecha_precio",
        "url_precio", "observaciones_precio"
    ]
    if not supabase_disponible or supabase is None:
        return pd.DataFrame(columns=cols_deseadas)
    try:
        respuesta = (
            supabase
            .table("inventario")
            .select(",".join(cols_deseadas))
            .execute()
        )
        df = pd.DataFrame(respuesta.data)

        if df.empty:
            return pd.DataFrame(columns=cols_deseadas)

        df = df.loc[:, ~df.columns.duplicated()].copy()
        for col in cols_deseadas:
            if col not in df.columns:
                df[col] = 0.0 if col in ["merma", "precio_unidad", "cantidad_formato_compra", "precio_formato_compra"] else ""

        df = df[cols_deseadas].copy()
        df["codigo"] = df["codigo"].fillna("").astype(str).str.strip().str.upper()
        df["familia"] = df["familia"].fillna("").astype(str).str.strip()
        df["descripcion"] = df["descripcion"].fillna("").astype(str).str.strip()
        df["unidad_medida"] = df["unidad_medida"].fillna("kg").astype(str).str.strip().replace("", "kg")
        df["merma"] = pd.to_numeric(df["merma"], errors="coerce").fillna(0.0)
        df["precio_unidad"] = pd.to_numeric(df["precio_unidad"], errors="coerce").fillna(0.0)
        df["cantidad_formato_compra"] = pd.to_numeric(df["cantidad_formato_compra"], errors="coerce")
        df["precio_formato_compra"] = pd.to_numeric(df["precio_formato_compra"], errors="coerce")
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
                "unidad_medida": row.get("unidad_medida", "kg"),
                "merma": float(row.get("merma", 0.0)) if pd.notna(row.get("merma")) else 0.0,
                "precio_unidad": float(row.get("precio_unidad", 0.0)) if pd.notna(row.get("precio_unidad")) else 0.0,
                "proveedor_precio": row.get("proveedor_precio", ""),
                "formato_compra": row.get("formato_compra", ""),
                "cantidad_formato_compra": row.get("cantidad_formato_compra", None),
                "unidad_formato_compra": row.get("unidad_formato_compra", ""),
                "precio_formato_compra": row.get("precio_formato_compra", None),
                "fecha_precio": row.get("fecha_precio", ""),
                "url_precio": row.get("url_precio", ""),
                "observaciones_precio": row.get("observaciones_precio", "")
            }


def normalizar_texto_busqueda(texto):
    texto = "" if texto is None else str(texto)
    texto = unicodedata.normalize("NFKD", texto)
    texto = "".join(ch for ch in texto if not unicodedata.combining(ch))
    texto = re.sub(r"[^A-Za-z0-9 ]+", " ", texto.upper())
    return re.sub(r"\s+", " ", texto).strip()


PALABRAS_NO_ALIMENTARIAS = {
    "PAPEL", "ENVOLVER", "ENVOLTORIO", "CAJA", "BOLSA", "BANDEJA", "SERVILLETA",
    "VASO", "PLATO", "CUBIERTO", "GUANTE", "FILM", "ALUMINIO", "ETIQUETA",
    "PACKAGING", "ENVASE", "CUCHARA", "TENEDOR", "CUCHILLO", "MOLDE", "BLONDA", "TAPA"
}


def parece_material_no_alimentario(descripcion):
    palabras = set(normalizar_texto_busqueda(descripcion).split())
    return bool(palabras & PALABRAS_NO_ALIMENTARIAS)


def descripcion_generica_ingrediente(descripcion):
    texto = normalizar_texto_busqueda(descripcion)
    palabras_descartables = {
        "FRESCO", "FRESCA", "CONGELADO", "CONGELADA", "ECO", "ECOLOGICO", "ECOLOGICA",
        "BIO", "MARCA", "BOLSA", "LATA", "CAJA", "BANDEJA", "PAQUETE", "GARRAFA",
        "BOTELLA", "SACO", "MONODOSIS", "APROX", "SIN", "CON", "NATURAL", "PACK", "UNIDAD",
        "UD", "UDS", "GR", "G", "KG", "ML", "CL", "L"
    }
    palabras = [p for p in texto.split() if not p.isdigit() and p not in palabras_descartables]
    return " ".join(palabras[:4]) or texto


def sugerir_ingredientes_similares(descripcion, inventario, limite=8, umbral=0.30):
    objetivo = descripcion_generica_ingrediente(descripcion)
    if not objetivo or inventario.empty or parece_material_no_alimentario(objetivo):
        return []

    sugerencias = []
    for _, row in inventario.iterrows():
        desc_bd = str(row.get("descripcion", ""))
        if parece_material_no_alimentario(desc_bd) and not parece_material_no_alimentario(objetivo):
            continue
        desc_norm = normalizar_texto_busqueda(desc_bd)
        if not desc_norm:
            continue
        score = SequenceMatcher(None, objetivo, desc_norm).ratio()
        palabras_objetivo = set(objetivo.split())
        palabras_bd = set(desc_norm.split())
        if palabras_objetivo and palabras_bd:
            score = max(score, len(palabras_objetivo & palabras_bd) / len(palabras_objetivo | palabras_bd))
            palabra_principal = objetivo.split()[0] if objetivo.split() else ""
            if palabra_principal and palabra_principal in palabras_bd:
                score += 0.35
        if score >= umbral:
            sugerencias.append({
                "codigo": str(row.get("codigo", "")).strip().upper(),
                "familia": str(row.get("familia", "")).strip(),
                "descripcion": desc_bd,
                "unidad_medida": str(row.get("unidad_medida", "kg")).strip() or "kg",
                "merma": float(row.get("merma", 0.0)) if pd.notna(row.get("merma")) else 0.0,
                "precio_unidad": float(row.get("precio_unidad", 0.0)) if pd.notna(row.get("precio_unidad")) else 0.0,
                "proveedor_precio": str(row.get("proveedor_precio", "") or "").strip(),
                "formato_compra": str(row.get("formato_compra", "") or "").strip(),
                "cantidad_formato_compra": row.get("cantidad_formato_compra", None),
                "unidad_formato_compra": str(row.get("unidad_formato_compra", "") or "").strip(),
                "score": score
            })

    return sorted(sugerencias, key=lambda item: item["score"], reverse=True)[:limite]


def codigo_ingrediente_valido(codigo):
    codigo = "" if codigo is None else str(codigo).strip().upper()
    return codigo and codigo not in ["S/C", "SC", "SIN CODIGO", "SIN CÓDIGO"]


def inferir_unidad_medida(descripcion):
    texto = normalizar_texto_busqueda(descripcion)
    if any(p in texto.split() for p in ["AGUA", "CALDO", "VINO", "ZUMO", "LECHE", "NATA", "ACEITE", "VINAGRE"]):
        return "l"
    if any(p in texto.split() for p in ["HUEVO", "HUEVOS"]):
        return "ud"
    if "SOBRE" in texto or "SOBRES" in texto:
        return "sobre"
    return "kg"


def generar_codigo_ingrediente_nuevo(descripcion, existentes):
    base = normalizar_texto_busqueda(descripcion)
    prefijo = "".join(palabra[:3] for palabra in base.split()[:2])[:6] or "ING"
    prefijo = re.sub(r"[^A-Z0-9]", "", prefijo) or "ING"
    candidato = f"ING-{prefijo}"
    contador = 1
    while candidato in existentes:
        contador += 1
        candidato = f"ING-{prefijo}-{contador:02d}"
    existentes.add(candidato)
    return candidato


def preparar_fila_inventario_desde_ingrediente(ingrediente, codigo=None):
    codigo_final = codigo if codigo is not None else ingrediente.get("codigo", "")
    merma = pd.to_numeric(ingrediente.get("merma", 0.0), errors="coerce")
    precio = pd.to_numeric(ingrediente.get("precio_unidad", 0.0), errors="coerce")
    return {
        "codigo": str(codigo_final).strip().upper(),
        "familia": ingrediente.get("familia", "SIN CLASIFICAR"),
        "descripcion": str(ingrediente.get("descripcion", "")).strip() or "Ingrediente Nuevo",
        "unidad_medida": str(ingrediente.get("unidad_medida", "")).strip() or inferir_unidad_medida(ingrediente.get("descripcion", "")),
        "merma": 0.0 if pd.isna(merma) else float(merma),
        "precio_unidad": 0.0 if pd.isna(precio) else float(precio)
    }


RECETAS_COLUMNAS = [
    "id", "user_id", "codigo_receta", "nombre", "categoria", "tipo_plato",
    "raciones_base", "unidad_servicio", "descripcion", "elaboracion",
    "observaciones", "costes_indirectos_pct", "margen_beneficio_pct",
    "iva_pct", "coste_total", "precio_venta_sin_iva",
    "precio_venta_con_iva", "activa", "created_at", "updated_at"
]

RECETA_INGREDIENTES_COLUMNAS = [
    "id", "receta_id", "codigo_ingrediente", "descripcion_ingrediente",
    "cantidad_bruta", "unidad_medida", "merma", "cantidad_neta",
    "precio_unidad", "coste_total", "orden", "es_temporal",
    "created_at", "updated_at"
]

MENUS_COLUMNAS = [
    "id", "user_id", "nombre", "tipo_menu", "descripcion",
    "numero_comensales", "coste_total", "precio_total",
    "created_at", "updated_at"
]

MENU_RECETAS_COLUMNAS = [
    "id", "menu_id", "receta_id", "raciones", "orden", "seccion", "created_at"
]


def numero_seguro(valor, defecto=0.0):
    numero = pd.to_numeric(valor, errors="coerce")
    return float(defecto) if pd.isna(numero) else float(numero)


def generar_codigo_receta():
    """
    Genera el siguiente codigo REC-0001, REC-0002... leyendo public.recetas.
    Si Supabase no esta disponible, devuelve un codigo inicial seguro.
    """
    if not supabase_disponible or supabase is None:
        return "REC-0001"

    try:
        respuesta = (
            supabase
            .table("recetas")
            .select("codigo_receta")
            .execute()
        )
        codigos_existentes = {
            str(fila.get("codigo_receta", "")).strip().upper()
            for fila in (respuesta.data or [])
            if fila.get("codigo_receta")
        }
        ultimo_numero = 0
        for codigo in codigos_existentes:
            coincidencia = re.fullmatch(r"REC-(\d+)", codigo)
            if coincidencia:
                ultimo_numero = max(ultimo_numero, int(coincidencia.group(1)))

        siguiente = ultimo_numero + 1
        candidato = f"REC-{siguiente:04d}"
        while candidato in codigos_existentes:
            siguiente += 1
            candidato = f"REC-{siguiente:04d}"
        return candidato
    except Exception:
        return "REC-0001"


def generar_nombre_copia_receta(nombre_original):
    """
    Genera un nombre de copia evitando duplicados sencillos.
    """
    nombre_base = str(nombre_original or "Receta").strip() or "Receta"
    if not supabase_disponible or supabase is None:
        return f"{nombre_base} copia"

    try:
        recetas_df = cargar_recetas_supabase()
        nombres_existentes = {
            str(nombre).strip().lower()
            for nombre in recetas_df.get("nombre", [])
            if str(nombre).strip()
        }
        candidato = f"{nombre_base} copia"
        if candidato.lower() not in nombres_existentes:
            return candidato

        contador = 2
        while True:
            candidato = f"{nombre_base} copia {contador}"
            if candidato.lower() not in nombres_existentes:
                return candidato
            contador += 1
    except Exception:
        return f"{nombre_base} copia"


def generar_nombre_copia_menu(nombre_original):
    """
    Genera un nombre de copia de menu evitando duplicados sencillos.
    """
    nombre_base = str(nombre_original or "Menú").strip() or "Menú"
    if not supabase_disponible or supabase is None:
        return f"{nombre_base} copia"

    try:
        menus_df = cargar_menus_supabase()
        nombres_existentes = {
            str(nombre).strip().lower()
            for nombre in menus_df.get("nombre", [])
            if str(nombre).strip()
        }
        candidato = f"{nombre_base} copia"
        if candidato.lower() not in nombres_existentes:
            return candidato

        contador = 2
        while True:
            candidato = f"{nombre_base} copia {contador}"
            if candidato.lower() not in nombres_existentes:
                return candidato
            contador += 1
    except Exception:
        return f"{nombre_base} copia"


def calcular_datos_ingrediente_receta(ing, orden=0):
    """
    Convierte un ingrediente de la app al formato de public.receta_ingredientes.
    """
    codigo = str(ing.get("codigo", "")).strip().upper()
    cantidad_bruta = numero_seguro(ing.get("cantidad_bruta", 0.0))
    merma = numero_seguro(ing.get("merma", 0.0))
    precio_unidad = numero_seguro(ing.get("precio_unidad", 0.0))
    cantidad_neta = cantidad_bruta * (1 - merma / 100)
    coste_total = cantidad_bruta * precio_unidad
    es_temporal = not codigo_ingrediente_valido(codigo)

    return {
        "codigo_ingrediente": None if es_temporal else codigo,
        "descripcion_ingrediente": str(
            ing.get("descripcion_ingrediente", ing.get("descripcion", ""))
        ).strip(),
        "cantidad_bruta": cantidad_bruta,
        "unidad_medida": str(ing.get("unidad_medida", "kg")).strip() or "kg",
        "merma": merma,
        "cantidad_neta": cantidad_neta,
        "precio_unidad": precio_unidad,
        "coste_total": coste_total,
        "orden": int(numero_seguro(orden, 0)),
        "es_temporal": es_temporal
    }


@st.cache_data(ttl=600)
def cargar_recetas_supabase():
    """
    Lee public.recetas y devuelve un DataFrame seguro.
    """
    if not supabase_disponible or supabase is None:
        return pd.DataFrame(columns=RECETAS_COLUMNAS)

    try:
        respuesta = (
            supabase
            .table("recetas")
            .select(",".join(RECETAS_COLUMNAS))
            .order("created_at", desc=True)
            .execute()
        )
        df = pd.DataFrame(respuesta.data or [])
        if df.empty:
            return pd.DataFrame(columns=RECETAS_COLUMNAS)

        for col in RECETAS_COLUMNAS:
            if col not in df.columns:
                df[col] = None
        return df[RECETAS_COLUMNAS].copy()
    except Exception:
        return pd.DataFrame(columns=RECETAS_COLUMNAS)


def limpiar_cache_recetas_guardadas():
    """
    Invalida el listado cacheado de recetas guardadas si la funcion esta cacheada.
    """
    try:
        cargar_recetas_supabase.clear()
        return True
    except Exception:
        return False


def cargar_receta_detalle_supabase(receta_id):
    """
    Lee cabecera de public.recetas e ingredientes de public.receta_ingredientes.
    Devuelve una tupla: (cabecera_dict, ingredientes_df).
    """
    ingredientes_vacios = pd.DataFrame(columns=RECETA_INGREDIENTES_COLUMNAS)
    if not receta_id or not supabase_disponible or supabase is None:
        return {}, ingredientes_vacios

    try:
        respuesta_receta = (
            supabase
            .table("recetas")
            .select(",".join(RECETAS_COLUMNAS))
            .eq("id", receta_id)
            .limit(1)
            .execute()
        )
        cabecera = (respuesta_receta.data or [{}])[0] if respuesta_receta.data else {}

        respuesta_ingredientes = (
            supabase
            .table("receta_ingredientes")
            .select(",".join(RECETA_INGREDIENTES_COLUMNAS))
            .eq("receta_id", receta_id)
            .order("orden")
            .execute()
        )
        ingredientes_df = pd.DataFrame(respuesta_ingredientes.data or [])
        if ingredientes_df.empty:
            return cabecera, ingredientes_vacios

        for col in RECETA_INGREDIENTES_COLUMNAS:
            if col not in ingredientes_df.columns:
                ingredientes_df[col] = None
        return cabecera, ingredientes_df[RECETA_INGREDIENTES_COLUMNAS].copy()
    except Exception:
        return {}, ingredientes_vacios


def guardar_receta_nueva_supabase(datos_receta, ingredientes):
    """
    Guarda una receta nueva y sus lineas de escandallo en Supabase.
    """
    if not supabase_disponible or supabase is None:
        return False, "Supabase no está conectado correctamente.", None

    try:
        respuesta_receta = (
            supabase
            .table("recetas")
            .insert(datos_receta)
            .execute()
        )
        receta_guardada = (respuesta_receta.data or [{}])[0]
        receta_id = receta_guardada.get("id")
        if not receta_id:
            return False, "No se pudo obtener el identificador de la receta guardada.", None

        lineas = []
        for orden, ing in enumerate(ingredientes, start=1):
            linea = calcular_datos_ingrediente_receta(ing, orden=orden)
            linea["receta_id"] = receta_id
            lineas.append(linea)

        if lineas:
            (
                supabase
                .table("receta_ingredientes")
                .insert(lineas)
                .execute()
            )

        limpiar_cache_recetas_guardadas()

        return True, "Receta guardada correctamente.", receta_guardada
    except Exception as e:
        return False, f"Error al guardar la receta en Supabase: {e}", None


def actualizar_receta_supabase(receta_id, datos_receta, ingredientes):
    """
    Actualiza una receta existente y reemplaza solo sus lineas de escandallo.
    """
    if not receta_id:
        return False, "No hay una receta cargada para actualizar."
    if not supabase_disponible or supabase is None:
        return False, "Supabase no está conectado correctamente."

    try:
        (
            supabase
            .table("recetas")
            .update(datos_receta)
            .eq("id", receta_id)
            .execute()
        )

        (
            supabase
            .table("receta_ingredientes")
            .delete()
            .eq("receta_id", receta_id)
            .execute()
        )

        lineas = []
        for orden, ing in enumerate(ingredientes, start=1):
            linea = calcular_datos_ingrediente_receta(ing, orden=orden)
            linea["receta_id"] = receta_id
            lineas.append(linea)

        if lineas:
            (
                supabase
                .table("receta_ingredientes")
                .insert(lineas)
                .execute()
            )

        limpiar_cache_recetas_guardadas()

        return True, "Receta actualizada correctamente."
    except Exception as e:
        return False, f"Error al actualizar la receta en Supabase: {e}"


def duplicar_receta_supabase(datos_receta, ingredientes):
    """
    Duplica una receta cargada como una receta nueva con codigo y nombre nuevos.
    """
    if not supabase_disponible or supabase is None:
        return False, "Supabase no está conectado correctamente.", None
    if not ingredientes:
        return False, "No hay ingredientes para duplicar.", None

    datos_copia = dict(datos_receta)
    datos_copia["user_id"] = None
    datos_copia["codigo_receta"] = generar_codigo_receta()
    datos_copia["nombre"] = generar_nombre_copia_receta(datos_receta.get("nombre", "Receta"))

    return guardar_receta_nueva_supabase(datos_copia, ingredientes)


def eliminar_receta_supabase(receta_id):
    """
    Elimina una sola receta por id. Los ingredientes asociados dependen del cascade de Supabase.
    """
    if not receta_id:
        return False, "No hay una receta seleccionada para eliminar."
    if not supabase_disponible or supabase is None:
        return False, "Supabase no está conectado correctamente."

    try:
        respuesta_uso_menu = (
            supabase
            .table("menu_recetas")
            .select("id")
            .eq("receta_id", receta_id)
            .limit(1)
            .execute()
        )
        if respuesta_uso_menu.data:
            return (
                False,
                "No se puede eliminar porque esta receta está usada en uno o varios menús. "
                "Primero elimínala del menú o duplica/modifica el menú."
            )

        (
            supabase
            .table("recetas")
            .delete()
            .eq("id", receta_id)
            .execute()
        )
        limpiar_cache_recetas_guardadas()
        return True, "Receta eliminada correctamente."
    except Exception as e:
        mensaje_error = str(e)
        mensaje_error_lower = mensaje_error.lower()
        if (
            "foreign key" in mensaje_error_lower
            or "violates foreign key" in mensaje_error_lower
            or "23503" in mensaje_error_lower
            or "menu_recetas" in mensaje_error_lower
        ):
            return (
                False,
                "No se puede eliminar porque esta receta está usada en uno o varios menús. "
                "Primero elimínala del menú o duplica/modifica el menú."
            )
        return False, f"Error al eliminar la receta en Supabase: {e}"


@st.cache_data(ttl=600)
def cargar_menus_supabase():
    """
    Lee public.menus y devuelve un DataFrame seguro.
    """
    if not supabase_disponible or supabase is None:
        return pd.DataFrame(columns=MENUS_COLUMNAS)

    try:
        respuesta = (
            supabase
            .table("menus")
            .select(",".join(MENUS_COLUMNAS))
            .order("created_at", desc=True)
            .execute()
        )
        df = pd.DataFrame(respuesta.data or [])
        if df.empty:
            return pd.DataFrame(columns=MENUS_COLUMNAS)

        for col in MENUS_COLUMNAS:
            if col not in df.columns:
                df[col] = None
        return df[MENUS_COLUMNAS].copy()
    except Exception:
        return pd.DataFrame(columns=MENUS_COLUMNAS)


def cargar_menu_detalle_supabase(menu_id):
    """
    Lee cabecera de public.menus y lineas de public.menu_recetas.
    Enriquece las lineas con nombre, codigo y costes de public.recetas cuando existen.
    """
    lineas_vacias = pd.DataFrame(columns=MENU_RECETAS_COLUMNAS)
    if not menu_id or not supabase_disponible or supabase is None:
        return {}, lineas_vacias

    try:
        respuesta_menu = (
            supabase
            .table("menus")
            .select(",".join(MENUS_COLUMNAS))
            .eq("id", menu_id)
            .limit(1)
            .execute()
        )
        cabecera = (respuesta_menu.data or [{}])[0] if respuesta_menu.data else {}

        respuesta_lineas = (
            supabase
            .table("menu_recetas")
            .select(",".join(MENU_RECETAS_COLUMNAS))
            .eq("menu_id", menu_id)
            .order("orden")
            .execute()
        )
        lineas_df = pd.DataFrame(respuesta_lineas.data or [])
        if lineas_df.empty:
            return cabecera, lineas_vacias

        for col in MENU_RECETAS_COLUMNAS:
            if col not in lineas_df.columns:
                lineas_df[col] = None

        receta_ids = [
            str(receta_id)
            for receta_id in lineas_df["receta_id"].dropna().unique().tolist()
            if str(receta_id).strip()
        ]
        recetas_por_id = {}
        if receta_ids:
            respuesta_recetas = (
                supabase
                .table("recetas")
                .select("id,codigo_receta,nombre,raciones_base,coste_total,precio_venta_sin_iva,precio_venta_con_iva")
                .in_("id", receta_ids)
                .execute()
            )
            recetas_por_id = {
                str(receta.get("id")): receta
                for receta in (respuesta_recetas.data or [])
                if receta.get("id")
            }

        lineas_df["codigo_receta"] = lineas_df["receta_id"].apply(
            lambda receta_id: recetas_por_id.get(str(receta_id), {}).get("codigo_receta")
        )
        lineas_df["nombre_receta"] = lineas_df["receta_id"].apply(
            lambda receta_id: recetas_por_id.get(str(receta_id), {}).get("nombre")
        )
        lineas_df["coste_receta"] = lineas_df["receta_id"].apply(
            lambda receta_id: recetas_por_id.get(str(receta_id), {}).get("coste_total")
        )
        lineas_df["raciones_base"] = lineas_df["receta_id"].apply(
            lambda receta_id: recetas_por_id.get(str(receta_id), {}).get("raciones_base")
        )
        lineas_df["precio_receta_sin_iva"] = lineas_df["receta_id"].apply(
            lambda receta_id: recetas_por_id.get(str(receta_id), {}).get("precio_venta_sin_iva")
        )
        lineas_df["precio_receta_con_iva"] = lineas_df["receta_id"].apply(
            lambda receta_id: recetas_por_id.get(str(receta_id), {}).get("precio_venta_con_iva")
        )
        return cabecera, lineas_df.copy()
    except Exception:
        return {}, lineas_vacias


def calcular_totales_menu(lineas_menu):
    """
    Calcula coste total y, si hay datos de precio, precio total del menu.
    """
    if lineas_menu is None:
        return {"coste_total": 0.0, "precio_total": None}

    if isinstance(lineas_menu, pd.DataFrame):
        lineas = lineas_menu.to_dict(orient="records")
    else:
        lineas = list(lineas_menu)

    coste_total = 0.0
    precio_total = 0.0
    hay_precio = False

    for linea in lineas:
        raciones = numero_seguro(linea.get("raciones", 1.0), 1.0)
        raciones_base = numero_seguro(linea.get("raciones_base", 0.0), 0.0)
        factor = raciones / raciones_base if raciones_base > 0 else 1.0
        coste_receta = linea.get("coste_receta", linea.get("coste_total", None))
        precio_receta = linea.get(
            "precio_receta_con_iva",
            linea.get(
                "precio_receta",
                linea.get("precio_venta_con_iva", linea.get("precio_total", None))
            )
        )

        coste_total += numero_seguro(coste_receta, 0.0) * factor
        if precio_receta is not None and not pd.isna(precio_receta):
            precio_total += numero_seguro(precio_receta, 0.0) * factor
            hay_precio = True

    return {
        "coste_total": coste_total,
        "precio_total": precio_total if hay_precio else None
    }


SECCIONES_MENU = ["", "Aperitivo", "Entrante", "Principal", "Postre", "Bebida", "Otro"]


def recalcular_linea_menu(linea):
    """
    Recalcula factor, coste y precio de una linea de menu sin modificar recetas.
    """
    linea_recalculada = dict(linea)
    raciones = numero_seguro(linea_recalculada.get("raciones", 1.0), 1.0)
    raciones_base = numero_seguro(linea_recalculada.get("raciones_base", 0.0), 0.0)
    factor = raciones / raciones_base if raciones_base > 0 else 1.0
    coste_receta = numero_seguro(linea_recalculada.get("coste_receta", 0.0), 0.0)
    precio_receta = linea_recalculada.get("precio_receta", None)
    hay_precio = precio_receta is not None and not pd.isna(precio_receta)

    linea_recalculada["raciones"] = float(raciones)
    linea_recalculada["raciones_base"] = float(raciones_base)
    linea_recalculada["coste_receta"] = float(coste_receta)
    linea_recalculada["coste_total_linea"] = float(coste_receta * factor)
    linea_recalculada["precio_total_linea"] = (
        float(numero_seguro(precio_receta, 0.0) * factor)
        if hay_precio else None
    )
    return linea_recalculada


def normalizar_lineas_menu(lineas_menu):
    """
    Ordena y recalcula todas las lineas del menu actual.
    """
    lineas = []
    for orden, linea in enumerate(lineas_menu or [], start=1):
        linea_normalizada = dict(linea)
        linea_normalizada["orden"] = int(numero_seguro(linea_normalizada.get("orden", orden), orden))
        linea_normalizada["seccion"] = str(linea_normalizada.get("seccion", "") or "").strip()
        lineas.append(recalcular_linea_menu(linea_normalizada))

    lineas = sorted(lineas, key=lambda item: int(numero_seguro(item.get("orden", 0), 0)))
    for orden, linea in enumerate(lineas, start=1):
        linea["orden"] = orden
    return lineas


def crear_linea_menu_desde_receta(receta_id, receta, raciones, orden, seccion=""):
    """
    Construye una linea de menu desde una receta guardada.
    """
    raciones_base = numero_seguro(receta.get("raciones_base", 0.0), 0.0)
    coste_receta = numero_seguro(receta.get("coste_total", 0.0), 0.0)
    precio_receta = receta.get("precio_venta_con_iva", None)
    if precio_receta is None or pd.isna(precio_receta):
        precio_receta = receta.get("precio_venta_sin_iva", None)

    hay_precio = precio_receta is not None and not pd.isna(precio_receta)
    linea = {
        "receta_id": str(receta_id),
        "codigo_receta": str(receta.get("codigo_receta", "") or ""),
        "nombre_receta": str(receta.get("nombre", "") or "Receta sin nombre"),
        "raciones": float(raciones),
        "raciones_base": float(raciones_base),
        "coste_receta": float(coste_receta),
        "precio_receta": float(numero_seguro(precio_receta, 0.0)) if hay_precio else None,
        "orden": int(orden),
        "seccion": str(seccion or "").strip()
    }
    return recalcular_linea_menu(linea)


def preparar_lineas_menu_para_supabase(lineas_menu):
    """
    Convierte lineas de menu al formato de public.menu_recetas.
    """
    if lineas_menu is None:
        return []

    if isinstance(lineas_menu, pd.DataFrame):
        lineas = lineas_menu.to_dict(orient="records")
    else:
        lineas = list(lineas_menu)

    lineas_preparadas = []
    for orden, linea in enumerate(lineas, start=1):
        receta_id = linea.get("receta_id", linea.get("id_receta", linea.get("id", None)))
        if not receta_id:
            continue
        lineas_preparadas.append({
            "receta_id": receta_id,
            "raciones": numero_seguro(linea.get("raciones", 1.0), 1.0),
            "orden": int(numero_seguro(linea.get("orden", orden), orden)),
            "seccion": str(linea.get("seccion", "") or "").strip() or None
        })
    return lineas_preparadas


def guardar_menu_supabase(datos_menu, lineas_menu):
    """
    Crea un menu nuevo y sus recetas asociadas. No modifica recetas.
    """
    if not supabase_disponible or supabase is None:
        return False, "Supabase no está conectado correctamente.", None

    lineas_menu = normalizar_lineas_menu(lineas_menu)
    lineas_preparadas = preparar_lineas_menu_para_supabase(lineas_menu)
    if not lineas_preparadas:
        return False, "Añade al menos una receta al menú antes de guardar.", None

    try:
        datos_guardar = dict(datos_menu)
        datos_guardar["user_id"] = None
        totales = calcular_totales_menu(lineas_menu)
        if datos_guardar.get("coste_total") is None:
            datos_guardar["coste_total"] = totales["coste_total"]
        datos_guardar["coste_total"] = numero_seguro(datos_guardar.get("coste_total", 0.0))
        if datos_guardar.get("precio_total") is None:
            datos_guardar.pop("precio_total", None)
        if "precio_total" not in datos_guardar and totales["precio_total"] is not None:
            datos_guardar["precio_total"] = totales["precio_total"]

        respuesta_menu = (
            supabase
            .table("menus")
            .insert(datos_guardar)
            .execute()
        )
        menu_guardado = (respuesta_menu.data or [{}])[0]
        menu_id = menu_guardado.get("id")
        if not menu_id:
            return False, "No se pudo obtener el identificador del menú guardado.", None

        for linea in lineas_preparadas:
            linea["menu_id"] = menu_id

        (
            supabase
            .table("menu_recetas")
            .insert(lineas_preparadas)
            .execute()
        )

        try:
            cargar_menus_supabase.clear()
        except Exception:
            pass

        return True, "Menú guardado correctamente.", menu_guardado
    except Exception as e:
        return False, f"Error al guardar el menú en Supabase: {e}", None


def actualizar_menu_supabase(menu_id, datos_menu, lineas_menu):
    """
    Actualiza un menu y reemplaza solo sus lineas en public.menu_recetas.
    """
    if not menu_id:
        return False, "No hay un menú seleccionado para actualizar."
    if not supabase_disponible or supabase is None:
        return False, "Supabase no está conectado correctamente."

    lineas_menu = normalizar_lineas_menu(lineas_menu)
    lineas_preparadas = preparar_lineas_menu_para_supabase(lineas_menu)
    if not lineas_preparadas:
        return False, "Añade al menos una receta al menú antes de actualizar."

    try:
        datos_actualizar = dict(datos_menu)
        totales = calcular_totales_menu(lineas_menu)
        if datos_actualizar.get("coste_total") is None:
            datos_actualizar["coste_total"] = totales["coste_total"]
        datos_actualizar["coste_total"] = numero_seguro(datos_actualizar.get("coste_total", 0.0))
        if datos_actualizar.get("precio_total") is None:
            datos_actualizar.pop("precio_total", None)
        if "precio_total" not in datos_actualizar and totales["precio_total"] is not None:
            datos_actualizar["precio_total"] = totales["precio_total"]

        (
            supabase
            .table("menus")
            .update(datos_actualizar)
            .eq("id", menu_id)
            .execute()
        )

        (
            supabase
            .table("menu_recetas")
            .delete()
            .eq("menu_id", menu_id)
            .execute()
        )

        for linea in lineas_preparadas:
            linea["menu_id"] = menu_id

        (
            supabase
            .table("menu_recetas")
            .insert(lineas_preparadas)
            .execute()
        )

        try:
            cargar_menus_supabase.clear()
        except Exception:
            pass

        return True, "Menú actualizado correctamente."
    except Exception as e:
        return False, f"Error al actualizar el menú en Supabase: {e}"


def preparar_ingredientes_receta_para_sesion(ingredientes_df):
    """
    Adapta public.receta_ingredientes al formato interno de st.session_state.
    """
    if ingredientes_df is None or ingredientes_df.empty:
        return []

    ingredientes = []
    for _, fila in ingredientes_df.iterrows():
        codigo = str(fila.get("codigo_ingrediente", "") or "").strip().upper()
        ingredientes.append({
            "codigo": codigo if codigo else "S/C",
            "descripcion": str(fila.get("descripcion_ingrediente", "") or "").strip(),
            "cantidad_bruta": numero_seguro(fila.get("cantidad_bruta", 0.0)),
            "unidad_medida": str(fila.get("unidad_medida", "kg") or "kg").strip() or "kg",
            "merma": numero_seguro(fila.get("merma", 0.0)),
            "precio_unidad": numero_seguro(fila.get("precio_unidad", 0.0))
        })
    return ingredientes


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
                "u": data.get("unidad_medida", "kg"),
                "m": data["merma"],
                "p": data["precio_unidad"]
            })

        bd_contexto = json.dumps(catalogo_reducido, ensure_ascii=False)

        prompt_sistema = f'''Eres un experto en contabilidad hostelera de alta cocina. Tu trabajo consiste en procesar textos o imágenes de recetas, albaranes, facturas o capturas, y extraer los ingredientes para un escandallo técnico estructurado.

Dispones del catálogo completo de ingredientes reales de nuestra cocina en formato JSON de referencia:
{bd_contexto}

INSTRUCCIONES CRÍTICAS:
1. Compara semánticamente cada ingrediente detectado con el catálogo de referencia. Si encuentras una coincidencia clara (por ejemplo, "pollo" con "CUARTO POLLO ASADO" o "aceite oliva" con "ACEITE OLIVA"), asigna exactamente su "codigo" (parámetro "c") y usa su "descripcion", "merma" y "precio_unidad" correspondientes del catálogo.
2. Trabaja con ingredientes genéricos de cocina: AGUA, TOMATE, PEPINO, PIMIENTO, CEBOLLA, AJO, ACEITE OLIVA, VINAGRE, SAL, PAN, HARINA, etc. Evita marcas, formatos comerciales y productos demasiado específicos salvo que el catálogo tenga una coincidencia clara.
3. Si el ingrediente analizado NO existe en el catálogo, invéntale un código único y nuevo corto que comience por "ING-" seguido de 4 números lógicos, asigna una descripción genérica del ingrediente y sus precios o mermas correspondientes.
4. Devuelve ingredientes comestibles, no envases ni utensilios. Descarta explícitamente PAPEL, ENVOLVER, ENVOLTORIO, BANDEJA, CAJA, ETIQUETA, PACKAGING, SERVILLETA, PLATO, VASO, CUCHARA, TENEDOR, CUCHILLO y MOLDE.
5. Si no conoces el precio, usa precio_unidad 0 y deja que la app lo vincule a BBDD.
6. Si el texto o la imagen presenta mermas implícitas (por ejemplo, Peso Bruto: 0.350, Peso Neto: 0.300), calcula la merma porcentual de forma precisa: ((bruto - neto)/bruto)*100.
7. Si detectas el nombre del plato o receta en el texto o imagen, devuélvelo como "nombre_receta" con el nombre limpio y legible.
8. Si detectas raciones de receta en expresiones como "6 porciones", "6 raciones", "para 6 personas", "serves 6" o "6 servings", devuelve ese número como "raciones_base".
9. Ignora títulos de columnas de cabecera de Excel, importes totales o subtotales de facturas.

REQUISITO EXCLUSIVO DE RESPUESTA: Devuelve ÚNICAMENTE JSON puro sin bloques de código markdown de tipo ```json y sin explicaciones adicionales.
Si detectas nombre de receta o raciones base, devuelve un objeto:
{{
  "nombre_receta": "Azpacho andaluz",
  "raciones_base": 6,
  "ingredientes": [
    {{"codigo": "ING-0019", "descripcion": "POLLO", "unidad_medida": "kg", "cantidad_bruta": 0.35, "merma": 14.29, "precio_unidad": 5.15}}
  ]
}}
Si no detectas raciones base, puedes devolver el array antiguo:
[
  {{"codigo": "ING-0019", "descripcion": "POLLO", "unidad_medida": "kg", "cantidad_bruta": 0.35, "merma": 14.29, "precio_unidad": 5.15}}
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
    Acepta el formato antiguo (lista) y el nuevo objeto con nombre_receta y raciones_base.
    """
    nombre_receta = ""
    if isinstance(respuesta_ia, list):
        ingredientes = respuesta_ia
        raciones_base = None
    elif isinstance(respuesta_ia, dict):
        ingredientes = respuesta_ia.get("ingredientes", [])
        nombre_receta = str(respuesta_ia.get("nombre_receta", "") or "").strip()
        raciones_base = pd.to_numeric(respuesta_ia.get("raciones_base"), errors="coerce")
        raciones_base = None if pd.isna(raciones_base) or float(raciones_base) <= 0 else float(raciones_base)
    else:
        return "", None, []

    ingredientes_limpios = []
    for ing in ingredientes if isinstance(ingredientes, list) else []:
        if not isinstance(ing, dict):
            continue
        descripcion = ing.get("descripcion", "")
        if parece_material_no_alimentario(descripcion):
            continue
        ing_limpio = dict(ing)
        ing_limpio["descripcion"] = descripcion_generica_ingrediente(descripcion) or str(descripcion).strip()
        if not ing_limpio.get("unidad_medida"):
            ing_limpio["unidad_medida"] = inferir_unidad_medida(ing_limpio["descripcion"])
        ingredientes_limpios.append(ing_limpio)

    return nombre_receta, raciones_base, ingredientes_limpios


def incorporar_ingredientes_ia(respuesta_ia):
    nombre_receta_detectado, raciones_base_detectadas, nuevos = normalizar_respuesta_ingredientes_ia(respuesta_ia)
    if not nuevos:
        return False

    if nombre_receta_detectado:
        st.session_state['receta_nombre'] = nombre_receta_detectado
        st.session_state['sincronizar_campos_receta'] = True

    st.session_state['ingredientes'].extend(nuevos)
    st.session_state['ingredientes_base_raciones'] = [dict(ing) for ing in st.session_state['ingredientes']]
    st.session_state['factor_raciones'] = 1.0

    if raciones_base_detectadas is not None:
        st.session_state['raciones_base'] = raciones_base_detectadas
        st.session_state['raciones_deseadas'] = raciones_base_detectadas
        st.session_state['receta_raciones_base'] = raciones_base_detectadas
        st.session_state['receta_raciones_deseadas'] = raciones_base_detectadas
        st.session_state['sincronizar_inputs_raciones'] = True

    return True


def marcar_receta_modificada_manualmente():
    st.session_state['ingredientes_base_raciones'] = None
    st.session_state['factor_raciones'] = 1.0


def sincronizar_inputs_raciones():
    if st.session_state.get('sincronizar_campos_receta', False):
        st.session_state['input_nombre_plato'] = st.session_state.get('receta_nombre', "Mi Receta")
        st.session_state['input_receta_categoria'] = st.session_state.get('receta_categoria', "")
        st.session_state['input_receta_tipo_plato'] = st.session_state.get('receta_tipo_plato', "")
        st.session_state['input_receta_observaciones'] = st.session_state.get('receta_observaciones', "")
        st.session_state['sincronizar_campos_receta'] = False

    if st.session_state.get('sincronizar_inputs_raciones', False):
        raciones_base = float(st.session_state.get('receta_raciones_base', st.session_state['raciones_base']))
        raciones_deseadas = float(st.session_state.get('receta_raciones_deseadas', st.session_state['raciones_deseadas']))
        st.session_state['input_raciones_base'] = raciones_base
        st.session_state['input_raciones_deseadas'] = raciones_deseadas
        st.session_state['raciones_base'] = raciones_base
        st.session_state['raciones_deseadas'] = raciones_deseadas
        st.session_state['raciones_base_aplicadas'] = raciones_base
        st.session_state['raciones_deseadas_aplicadas'] = raciones_deseadas
        st.session_state['sincronizar_inputs_raciones'] = False


def sincronizar_widgets_menu():
    if st.session_state.get('sincronizar_campos_menu', False):
        if 'menu_nombre_pendiente' in st.session_state:
            st.session_state['menu_nombre'] = st.session_state.pop('menu_nombre_pendiente')
        if 'menu_tipo_pendiente' in st.session_state:
            st.session_state['menu_tipo'] = st.session_state.pop('menu_tipo_pendiente')
        if 'menu_numero_comensales_pendiente' in st.session_state:
            st.session_state['menu_numero_comensales'] = st.session_state.pop('menu_numero_comensales_pendiente')
        st.session_state['sincronizar_campos_menu'] = False

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


def raciones_han_cambiado(raciones_base, raciones_deseadas, raciones_base_aplicadas, raciones_deseadas_aplicadas):
    return (
        float(raciones_base) != float(raciones_base_aplicadas)
        or float(raciones_deseadas) != float(raciones_deseadas_aplicadas)
    )


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
    ws.merge_cells('A1:H1')
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
    headers = ['Código', 'Ingrediente', 'Cantidad Bruta', 'Unidad', '% Merma', 'Cantidad Neta', 'Precio Unidad (€)', 'Coste Total (€)']
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
        ws.cell(row=row, column=col_idx['Cantidad Bruta'], value=float(ing.get('cantidad_bruta', 0.0))).number_format = '#,##0.000'
        ws.cell(row=row, column=col_idx['Unidad'], value=ing.get('unidad_medida', 'kg'))
        ws.cell(row=row, column=col_idx['% Merma'], value=float(ing.get('merma', 0.0))/100).number_format = '0.00%'
        ws.cell(
            row=row,
            column=col_idx['Cantidad Neta'],
            value=f"={col_letras['Cantidad Bruta']}{row}*(1-{col_letras['% Merma']}{row})",
        ).number_format = '#,##0.000'
        ws.cell(row=row, column=col_idx['Precio Unidad (€)'], value=float(ing.get('precio_unidad', 0.0))).number_format = '#,##0.00 €'
        ws.cell(
            row=row,
            column=col_idx['Coste Total (€)'],
            value=f"={col_letras['Cantidad Bruta']}{row}*{col_letras['Precio Unidad (€)']}{row}",
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

    ws.cell(row=res+8, column=6, value="PRECIO POR RACIÓN:").font = Font(bold=True)
    precio_racion = ws.cell(row=res+8, column=total_col, value=f"=IF($E$2>0,{total_col_letter}{res+7}/$E$2,0)")
    precio_racion.number_format = '#,##0.00 €'
    precio_racion.font = Font(bold=True)
    precio_racion.fill = PatternFill(start_color="FFF2CC", end_color="FFF2CC", fill_type="solid")

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
st.markdown(
    """
    <style>
    .block-container {
        padding-top: 1.25rem;
        padding-bottom: 1.5rem;
    }
    div[data-testid="stMetric"] {
        background: #f8fafc;
        border: 1px solid #e5e7eb;
        border-radius: 8px;
        padding: 0.55rem 0.7rem;
    }
    div[data-testid="stMetric"] label {
        white-space: normal;
    }
    div[data-testid="stTabs"] [data-baseweb="tab-list"] {
        gap: 0.35rem;
    }
    </style>
    """,
    unsafe_allow_html=True
)

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

    ingredientes_vinculados = [
        (idx, ing, str(ing.get("codigo", "")).strip().upper())
        for idx, ing in enumerate(st.session_state['ingredientes'])
        if str(ing.get("codigo", "")).strip().upper() in inventario_dict
    ]
    if ingredientes_vinculados:
        st.markdown("#### 🧾 Ficha editable del ingrediente seleccionado")
        opciones_ficha = [f"{idx}|{codigo}" for idx, _, codigo in ingredientes_vinculados]
        etiquetas_ficha = {
            f"{idx}|{codigo}": f"{idx + 1}. {codigo} · {inventario_dict[codigo].get('descripcion', '')}"
            for idx, _, codigo in ingredientes_vinculados
        }
        seleccion_ficha = st.selectbox(
            "Ingrediente vinculado a BBDD",
            opciones_ficha,
            format_func=lambda opcion: etiquetas_ficha.get(opcion, opcion),
            key="selector_ficha_ingrediente_activo"
        )
        idx_ficha = int(seleccion_ficha.split("|", 1)[0])
        codigo_ficha = seleccion_ficha.split("|", 1)[1]
        ficha_bd = inventario_dict[codigo_ficha]

        with st.form(f"ficha_inventario_seleccionada_{codigo_ficha}_{idx_ficha}"):
            st.caption(f"Código: {codigo_ficha}")
            descripcion_ficha = st.text_input("Descripción", value=str(ficha_bd.get("descripcion", "")))
            familia_ficha = st.text_input("Familia", value=str(ficha_bd.get("familia", "SIN CLASIFICAR")))
            unidades_validas = ["kg", "l", "ud", "sobre", "botella", "lata", "paquete", "caja", "bandeja", "hoja"]
            unidad_actual = str(ficha_bd.get("unidad_medida", "kg")).strip() or "kg"
            unidad_ficha = st.selectbox(
                "Unidad base",
                unidades_validas,
                index=unidades_validas.index(unidad_actual) if unidad_actual in unidades_validas else 0
            )
            merma_ficha = st.number_input(
                "% Merma",
                min_value=0.0,
                max_value=100.0,
                step=0.01,
                value=float(ficha_bd.get("merma", 0.0))
            )
            precio_ficha = st.number_input(
                "Precio Unidad (€)",
                min_value=0.0,
                step=0.01,
                value=float(ficha_bd.get("precio_unidad", 0.0))
            )

            st.text_input("Proveedor precio", value=str(ficha_bd.get("proveedor_precio", "")), disabled=True)
            st.text_input("Formato compra", value=str(ficha_bd.get("formato_compra", "")), disabled=True)
            st.text_input("Fecha precio", value=str(ficha_bd.get("fecha_precio", "")), disabled=True)
            st.text_input("Cantidad formato", value="" if pd.isna(ficha_bd.get("cantidad_formato_compra", None)) else str(ficha_bd.get("cantidad_formato_compra", "")), disabled=True)
            st.text_input("Unidad formato", value=str(ficha_bd.get("unidad_formato_compra", "")), disabled=True)
            st.text_input("Precio formato", value="" if pd.isna(ficha_bd.get("precio_formato_compra", None)) else str(ficha_bd.get("precio_formato_compra", "")), disabled=True)
            st.text_input("URL precio", value=str(ficha_bd.get("url_precio", "")), disabled=True)
            st.text_area("Observaciones precio", value=str(ficha_bd.get("observaciones_precio", "")), disabled=True, height=80)

            if st.form_submit_button("Guardar cambios en BBDD"):
                if not supabase_disponible:
                    st.error("Supabase no está conectado correctamente.")
                else:
                    datos_ficha = {
                        "codigo": codigo_ficha,
                        "familia": familia_ficha,
                        "descripcion": descripcion_ficha,
                        "unidad_medida": unidad_ficha,
                        "merma": float(merma_ficha),
                        "precio_unidad": float(precio_ficha)
                    }
                    try:
                        supabase.table("inventario").upsert(datos_ficha).execute()
                        st.session_state['ingredientes'][idx_ficha].update({
                            "descripcion": descripcion_ficha,
                            "unidad_medida": unidad_ficha,
                            "merma": float(merma_ficha),
                            "precio_unidad": float(precio_ficha)
                        })
                        st.session_state['db_trigger'] += 1
                        marcar_receta_modificada_manualmente()
                        st.success(f"Ficha {codigo_ficha} actualizada.")
                        st.rerun()
                    except Exception as e:
                        st.error(f"Error al guardar la ficha en Supabase: {e}")



st.divider()

main_tab_receta, main_tab_guardadas, main_tab_menus, main_tab_costes, main_tab_base = st.tabs([
    "Receta activa",
    "Recetas guardadas",
    "Menús",
    "Costes y exportacion",
    "Base de ingredientes"
])

with main_tab_receta:
    st.subheader("Receta activa")
    sincronizar_inputs_raciones()

    # Inputs generales del plato
    nombre_plato = st.text_input("Nombre del Plato", key="input_nombre_plato")
    st.session_state['receta_nombre'] = nombre_plato
    st.session_state['nombre_plato'] = nombre_plato
    st.caption("Ajusta raciones y alimenta la receta desde entrada manual, texto o imagen.")

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
    st.session_state['receta_raciones_base'] = float(raciones_base)
    st.session_state['receta_raciones_deseadas'] = float(raciones_deseadas)

    factor_raciones_preview = raciones_deseadas / raciones_base if raciones_base > 0 and raciones_deseadas > 0 else 0.0
    with col_r3:
        st.markdown(f"**Factor de ajuste:** {factor_raciones_preview:.4f}")
        st.caption("Se aplica automáticamente a la receta activa.")
    with col_r4:
        st.write("")
        st.write("")
        if st.button("Restablecer cantidades base"):
            if st.session_state['ingredientes_base_raciones'] is not None:
                st.session_state['ingredientes'] = [dict(ing) for ing in st.session_state['ingredientes_base_raciones']]
                st.session_state['ingredientes_base_raciones'] = None
                st.session_state['factor_raciones'] = 1.0
                st.session_state['raciones_base_aplicadas'] = float(raciones_base)
                st.session_state['raciones_deseadas_aplicadas'] = float(raciones_base)
                st.session_state['raciones_deseadas'] = float(raciones_base)
                st.session_state['receta_raciones_base'] = float(raciones_base)
                st.session_state['receta_raciones_deseadas'] = float(raciones_base)
                st.session_state['sincronizar_inputs_raciones'] = True
                st.success("Cantidades base restablecidas.")
                st.rerun()
            else:
                st.info("No hay cantidades base guardadas para restablecer.")

    if raciones_base <= 0 or raciones_deseadas <= 0:
        st.error("Las raciones base y deseadas deben ser mayores que 0.")
    elif st.session_state['ingredientes']:
        if raciones_han_cambiado(
            raciones_base,
            raciones_deseadas,
            st.session_state['raciones_base_aplicadas'],
            st.session_state['raciones_deseadas_aplicadas']
        ):
            if st.session_state['ingredientes_base_raciones'] is None:
                st.session_state['ingredientes_base_raciones'] = [dict(ing) for ing in st.session_state['ingredientes']]

            factor_raciones, ingredientes_ajustados = calcular_ajuste_raciones(
                st.session_state['ingredientes_base_raciones'],
                raciones_base,
                raciones_deseadas
            )
            st.session_state['ingredientes'] = ingredientes_ajustados
            st.session_state['factor_raciones'] = float(factor_raciones)
            st.session_state['raciones_base_aplicadas'] = float(raciones_base)
            st.session_state['raciones_deseadas_aplicadas'] = float(raciones_deseadas)
            st.rerun()
        else:
            st.session_state['factor_raciones'] = float(factor_raciones_preview)
    else:
        st.session_state['factor_raciones'] = float(factor_raciones_preview)


    st.divider()
    st.subheader("Anadir ingredientes")
    entrada_manual_tab, texto_tab, imagen_tab = st.tabs(["Entrada manual", "Texto con IA", "Imagen con IA"])

    with entrada_manual_tab:
        st.markdown("💡 **Tip:** Selecciona un código existente de tu base de datos y se auto-rellenarán la descripción, el precio y su merma.")

        opciones_codigo = [""] + list(inventario_dict.keys())

        with st.form("form_ingrediente", clear_on_submit=True):
            manual_col1, manual_col2 = st.columns(2)

            with manual_col1:
                cod_select = st.selectbox(
                    "Buscar por Código",
                    opciones_codigo,
                    format_func=lambda x: f"{x} - {inventario_dict[x]['descripcion']}" if x else "Seleccione un código..."
                )
                desc_man = st.text_input("Ingrediente (Nuevo)", placeholder="Ej: Cebolla tierna")
                unidad_man = st.selectbox("Unidad", ["kg", "l", "ud", "sobre", "botella", "lata", "paquete", "caja", "bandeja", "hoja"])

            with manual_col2:
                cant_man = st.number_input("Cant. Bruta (kg/l)", min_value=0.0, step=0.001, format="%.3f", value=None, placeholder="0.000")
                merma_man = st.number_input("% Merma", min_value=0.0, max_value=100.0, step=0.01, value=None, placeholder="0.00%")
                precio_man = st.number_input("Precio Unidad (€)", min_value=0.0, step=0.01, format="%.2f", value=None, placeholder="0.00 €")

            if st.form_submit_button("Añadir al Escandallo"):
                # Si el usuario seleccionó un código del desplegable
                if cod_select:
                    info_bd = inventario_dict[cod_select]
                    st.session_state['ingredientes'].append({
                        'codigo': cod_select,
                        'descripcion': info_bd['descripcion'],
                        'unidad_medida': info_bd.get('unidad_medida', 'kg'),
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
                        'unidad_medida': unidad_man,
                        'cantidad_bruta': cant_man if cant_man is not None else 0.0,
                        'merma': merma_man if merma_man is not None else 0.0,
                        'precio_unidad': precio_man if precio_man is not None else 0.0
                    })
                marcar_receta_modificada_manualmente()
                st.rerun()


    with texto_tab:
        st.markdown("📋 **Pega cualquier bloque de texto:** Textos de correo de proveedores, chats de WhatsApp o filas de PDF.")
        texto_pegado = st.text_area("Pega tu texto aquí para analizar con IA:", height=150, placeholder="3 kg de pollo asado ING-0027...")

        if st.button("Analizar texto con IA", type="primary"):
            if texto_pegado:
                with st.spinner("La IA está leyendo y cruzando los datos con tu Supabase..."):
                    nuevos = procesar_con_openai(texto_plano=texto_pegado)
                    if incorporar_ingredientes_ia(nuevos):
                        st.rerun()


    with imagen_tab:
        st.markdown("📸 **Arrastra o pega tu imagen:** Haz una captura de pantalla de tu factura u hoja física de albarán, y pulsa **Ctrl+V** directamente sobre este panel para subirla.")
        archivo_imagen = st.file_uploader("Sube, arrastra o pega (Ctrl+V) una foto de tu receta o factura (JPG/PNG)", type=['jpg', 'jpeg', 'png'])

        if archivo_imagen:
            if st.button("Escanear imagen con IA Vision", type="primary"):
                bytes_img = archivo_imagen.read()
                with st.spinner("Leyendo factura y asociando códigos de Supabase..."):
                    nuevos = procesar_con_openai(bytes_imagen=bytes_img, mime_type=archivo_imagen.type)
                    if incorporar_ingredientes_ia(nuevos):
                        st.rerun()


    st.divider()
    st.subheader("Ingredientes de la receta activa")
    if st.session_state['ingredientes']:
        st.subheader("🛒 Lista de Ingredientes de la Receta Activa")

        # Preparamos DataFrame de representación visual
        df_display = pd.DataFrame(st.session_state['ingredientes'])

        # Garantizar que existan las columnas estructurales
        for col in ["codigo", "descripcion", "unidad_medida", "cantidad_bruta", "merma", "precio_unidad"]:
            if col not in df_display.columns:
                df_display[col] = 0.0 if col in ["cantidad_bruta", "merma", "precio_unidad"] else "S/C"
        df_display["unidad_medida"] = df_display["unidad_medida"].replace("S/C", "kg").fillna("kg")
        df_display["cantidad_bruta"] = pd.to_numeric(df_display["cantidad_bruta"], errors="coerce").fillna(0.0)
        df_display["merma"] = pd.to_numeric(df_display["merma"], errors="coerce").fillna(0.0)
        df_display["precio_unidad"] = pd.to_numeric(df_display["precio_unidad"], errors="coerce").fillna(0.0)
        df_display["cantidad_neta"] = df_display["cantidad_bruta"] * (1 - (df_display["merma"] / 100))
        df_display["coste_total"] = df_display["cantidad_bruta"] * df_display["precio_unidad"]

        df_display = df_display[["codigo", "descripcion", "cantidad_bruta", "unidad_medida", "merma", "cantidad_neta", "precio_unidad", "coste_total"]]

        # Lanzamos el editor interactivo de la receta activa
        ingredientes_editados = st.data_editor(
            df_display,
            num_rows="dynamic",
            use_container_width=True,
            height=360,
            column_config={
                "codigo": st.column_config.TextColumn("Código", help="Código único del inventario", width="small"),
                "descripcion": st.column_config.TextColumn("Ingrediente", help="Descripción del producto", width="large"),
                "cantidad_bruta": st.column_config.NumberColumn("Cantidad Bruta", format="%.3f", min_value=0.0),
                "unidad_medida": st.column_config.SelectboxColumn("Unidad", options=["kg", "l", "ud", "sobre", "botella", "lata", "paquete", "caja", "bandeja", "hoja"], width="small"),
                "merma": st.column_config.NumberColumn("% Merma", format="%.2f %%", min_value=0.0, max_value=100.0),
                "cantidad_neta": st.column_config.NumberColumn("Cantidad Neta", format="%.3f", min_value=0.0),
                "precio_unidad": st.column_config.NumberColumn("Precio Unidad (€)", format="%.2f €", min_value=0.0),
                "coste_total": st.column_config.NumberColumn("Coste Total (€)", format="%.2f €", min_value=0.0)
            },
            disabled=["cantidad_neta", "coste_total"],
            key="editor_receta_activa"
        )

        # Casteo numérico robusto para que la suma de costes no falle nunca con floats
        for col in ["cantidad_bruta", "merma", "precio_unidad"]:
            ingredientes_editados[col] = pd.to_numeric(ingredientes_editados[col]).fillna(0.0)
        ingredientes_editados["cantidad_neta"] = ingredientes_editados["cantidad_bruta"] * (1 - (ingredientes_editados["merma"] / 100))
        ingredientes_editados["coste_total"] = ingredientes_editados["cantidad_bruta"] * ingredientes_editados["precio_unidad"]

        ingredientes_lista = ingredientes_editados.drop(columns=["cantidad_neta", "coste_total"], errors="ignore").to_dict(orient='records')

        # Sincronizar el estado al vuelo
        if ingredientes_lista != st.session_state['ingredientes']:
            st.session_state['ingredientes'] = ingredientes_lista
            marcar_receta_modificada_manualmente()
            st.rerun()

        ingredientes_no_encontrados = []
        for idx, ing in enumerate(st.session_state['ingredientes']):
            codigo_actual = str(ing.get("codigo", "")).strip().upper()
            if not codigo_ingrediente_valido(codigo_actual) or codigo_actual not in inventario_dict:
                sugerencias = sugerir_ingredientes_similares(ing.get("descripcion", ""), inventario_df)
                ingredientes_no_encontrados.append((idx, ing, sugerencias))

        acciones_db_col1, acciones_db_col2, acciones_db_col3 = st.columns([1, 1, 1])
        with acciones_db_col1:
            if st.button("Actualizar BBDD con códigos existentes", use_container_width=True):
                if not supabase_disponible:
                    st.error("Supabase no está conectado correctamente.")
                else:
                    filas_validas = [
                        preparar_fila_inventario_desde_ingrediente(ing)
                        for ing in st.session_state['ingredientes']
                        if codigo_ingrediente_valido(ing.get("codigo")) and str(ing.get("codigo", "")).strip().upper() in inventario_dict
                    ]
                    if filas_validas:
                        try:
                            for fila in filas_validas:
                                supabase.table("inventario").upsert(fila).execute()
                            st.session_state['db_trigger'] += 1
                            st.success(f"{len(filas_validas)} ingredientes actualizados en Supabase.")
                            st.rerun()
                        except Exception as e:
                            st.error(f"Error al actualizar Supabase: {e}")
                    else:
                        st.info("No hay ingredientes con código existente para actualizar.")

        with acciones_db_col2:
            if st.button("Crear nuevos en BBDD", use_container_width=True):
                if not supabase_disponible:
                    st.error("Supabase no está conectado correctamente.")
                else:
                    existentes = set(inventario_dict.keys())
                    ingredientes_actualizados = [dict(ing) for ing in st.session_state['ingredientes']]
                    filas_nuevas = []
                    for idx, ing in enumerate(ingredientes_actualizados):
                        codigo_actual = str(ing.get("codigo", "")).strip().upper()
                        if not codigo_ingrediente_valido(codigo_actual) or codigo_actual not in inventario_dict:
                            nuevo_codigo = codigo_actual if codigo_ingrediente_valido(codigo_actual) else generar_codigo_ingrediente_nuevo(ing.get("descripcion", ""), existentes)
                            existentes.add(nuevo_codigo)
                            ing["codigo"] = nuevo_codigo
                            filas_nuevas.append(preparar_fila_inventario_desde_ingrediente(ing, codigo=nuevo_codigo))
                    if filas_nuevas:
                        try:
                            for fila in filas_nuevas:
                                supabase.table("inventario").upsert(fila).execute()
                            st.session_state['ingredientes'] = ingredientes_actualizados
                            st.session_state['db_trigger'] += 1
                            marcar_receta_modificada_manualmente()
                            st.success(f"{len(filas_nuevas)} ingredientes nuevos creados en Supabase.")
                            st.rerun()
                        except Exception as e:
                            st.error(f"Error al crear ingredientes en Supabase: {e}")
                    else:
                        st.info("No hay ingredientes nuevos pendientes de crear.")

        with acciones_db_col3:
            if st.button("Limpiar toda la receta", use_container_width=True):
                st.session_state['ingredientes'] = []
                st.session_state['ingredientes_base_raciones'] = None
                st.session_state['factor_raciones'] = 1.0
                st.session_state['receta_id_cargada'] = None
                st.session_state['codigo_receta_cargada'] = ""
                st.rerun()

        if ingredientes_no_encontrados:
            with st.expander("🔎 Ingredientes no encontrados en BBDD y sugerencias", expanded=True):
                for idx, ing, sugerencias in ingredientes_no_encontrados:
                    ingrediente_original = str(ing.get("descripcion", "") or "Sin descripción").strip()
                    cantidad_original = numero_seguro(ing.get("cantidad_bruta", 0.0), 0.0)
                    unidad_original = str(ing.get("unidad_medida", "") or "kg").strip()
                    codigo_original = str(ing.get("codigo", "S/C") or "S/C").strip().upper()

                    if idx > 0:
                        st.divider()

                    st.markdown("#### Ingrediente no encontrado")
                    st.write(f"**Ingrediente detectado:** {ingrediente_original}")
                    st.write(f"**Cantidad:** {cantidad_original:.3f}")
                    st.write(f"**Unidad:** {unidad_original}")
                    st.write("**Motivo:** no existe coincidencia exacta en inventario")
                    st.caption(f"Fila {idx + 1} · Código actual: `{codigo_original}`")

                    st.markdown("#### Sugerencias de inventario")
                    if sugerencias:
                        opciones = [s["codigo"] for s in sugerencias]
                        etiquetas = {
                            s["codigo"]: (
                                f"{s['codigo']} · {s['descripcion']} · {s.get('familia', '')} · "
                                f"{s.get('unidad_medida', 'kg')} · merma {s.get('merma', 0):.2f}% · "
                                f"{s.get('precio_unidad', 0):.2f} € · "
                                f"{s.get('proveedor_precio', '') or 'sin proveedor'} · "
                                f"{s.get('formato_compra', '') or 'sin formato'} · "
                                f"{s['score']:.0%}"
                            )
                            for s in sugerencias
                        }
                        seleccion = st.selectbox(
                            "Elegir sugerencia parecida",
                            opciones,
                            format_func=lambda codigo: etiquetas.get(codigo, codigo),
                            key=f"sugerencia_codigo_{idx}"
                        )
                        sugerencia_seleccionada = next((s for s in sugerencias if s["codigo"] == seleccion), None)
                        if sugerencia_seleccionada:
                            detalle_col1, detalle_col2 = st.columns(2)
                            with detalle_col1:
                                st.write(f"**Código:** {sugerencia_seleccionada['codigo']}")
                                st.write(f"**Descripción:** {sugerencia_seleccionada['descripcion']}")
                                st.write(f"**Familia:** {sugerencia_seleccionada.get('familia', '') or 'Sin familia'}")
                                st.write(f"**Unidad:** {sugerencia_seleccionada.get('unidad_medida', 'kg')}")
                            with detalle_col2:
                                st.write(f"**Merma:** {sugerencia_seleccionada.get('merma', 0):.2f}%")
                                st.write(f"**Precio unidad:** {sugerencia_seleccionada.get('precio_unidad', 0):.2f} €")
                                st.write(f"**Proveedor:** {sugerencia_seleccionada.get('proveedor_precio', '') or 'Sin proveedor'}")
                                formato = sugerencia_seleccionada.get("formato_compra", "") or "Sin formato"
                                cantidad_formato = sugerencia_seleccionada.get("cantidad_formato_compra", None)
                                unidad_formato = sugerencia_seleccionada.get("unidad_formato_compra", "") or ""
                                if cantidad_formato is not None and pd.notna(cantidad_formato):
                                    formato = f"{formato} · {cantidad_formato} {unidad_formato}".strip()
                                st.write(f"**Formato:** {formato}")

                        if st.button("Usar ingrediente sugerido", key=f"usar_sugerencia_{idx}", use_container_width=True):
                            sugerencia = next((s for s in sugerencias if s["codigo"] == seleccion), None)
                            if sugerencia:
                                ingrediente_actualizado = dict(st.session_state['ingredientes'][idx])
                                unidad_sugerida = sugerencia.get("unidad_medida", "kg")
                                unidad_actual = str(ingrediente_actualizado.get("unidad_medida", "") or "").strip()
                                ingrediente_actualizado.update({
                                    "codigo": sugerencia["codigo"],
                                    "familia": sugerencia.get("familia", "SIN CLASIFICAR"),
                                    "descripcion": sugerencia["descripcion"],
                                    "unidad_medida": unidad_sugerida or unidad_actual or "kg",
                                    "merma": sugerencia["merma"],
                                    "precio_unidad": sugerencia["precio_unidad"]
                                })
                                st.session_state['ingredientes'][idx] = ingrediente_actualizado
                                marcar_receta_modificada_manualmente()
                                st.rerun()
                    else:
                        st.info("No se han encontrado sugerencias fiables en inventario.")
                        st.caption("Puedes crearlo como nuevo en base de datos con el botón superior, o mantenerlo solo en la receta activa.")


    else:
        st.info("Empieza agregando ingredientes usando entrada manual, texto o imagen.")

with main_tab_costes:
    st.subheader("Costes y exportacion")
    c1, c2, c3 = st.columns(3)
    with c1:
        costes_indirectos_pct = st.number_input("Costes Indirectos (%)", min_value=0.0, key="costes_indirectos_pct")
    with c2:
        margen_beneficio_pct = st.number_input("Margen Beneficio (%)", min_value=0.0, max_value=99.9, key="margen_beneficio_pct")
    with c3:
        iva_pct = st.number_input("IVA Evento (%)", min_value=0.0, max_value=100.0, step=1.0, key="iva_pct")

    if st.session_state['ingredientes']:
        st.subheader(f"📊 Costes: {nombre_plato}")
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
        raciones_deseadas_metricas = pd.to_numeric(st.session_state.get('raciones_deseadas', 0.0), errors='coerce')
        raciones_deseadas_metricas = 0.0 if pd.isna(raciones_deseadas_metricas) else float(raciones_deseadas_metricas)
        pvp_por_racion = pvp_final / raciones_deseadas_metricas if raciones_deseadas_metricas > 0 else 0.0

        r1, r2 = st.columns(2)
        r1.metric("Materia Prima", f"{subtotal_ing:.2f} €")
        r2.metric("Costes Ind.", f"{costes_ind:.2f} €")
        r3, r4 = st.columns(2)
        r3.metric("Coste Total", f"{coste_total:.2f} €")
        r4.metric("PVP Total", f"{pvp_final:.2f} €")
        st.metric("PVP por ración", f"{pvp_por_racion:.2f} €")

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
            type="primary",
            use_container_width=True
        )
    else:
        st.info("Anade ingredientes para ver costes y exportar la ficha.")

with main_tab_guardadas:
    st.subheader("Cargar receta guardada")
    mensaje_receta_cargada = st.session_state.pop("mensaje_receta_cargada", None)
    if mensaje_receta_cargada:
        st.success(mensaje_receta_cargada)

    opciones_recetas = []
    recetas_por_id = {}
    receta_id_seleccionada = None
    if st.session_state.pop("limpiar_selector_receta_guardada", False):
        st.session_state.pop("selector_receta_guardada", None)

    if not supabase_disponible:
        st.warning("Supabase no está disponible. No se pueden cargar recetas guardadas ahora.")
    else:
        recetas_guardadas_df = cargar_recetas_supabase()
        if recetas_guardadas_df.empty:
            st.info("Todavía no hay recetas guardadas en Supabase.")
        else:
            recetas_guardadas_df = recetas_guardadas_df.copy()
            recetas_guardadas_df["etiqueta_selector"] = recetas_guardadas_df.apply(
                lambda row: f"{row.get('codigo_receta', '')} · {row.get('nombre', '')}".strip(" ·"),
                axis=1
            )
            opciones_recetas = recetas_guardadas_df["id"].dropna().astype(str).tolist()
            recetas_por_id = {
                str(row.get("id")): row.to_dict()
                for _, row in recetas_guardadas_df.iterrows()
                if row.get("id")
            }

            if not opciones_recetas:
                st.info("Hay recetas guardadas, pero no se pudo leer su identificador.")
            else:
                receta_pendiente_selector = st.session_state.pop("selector_receta_guardada_pendiente", None)
                if receta_pendiente_selector and str(receta_pendiente_selector) in opciones_recetas:
                    st.session_state["selector_receta_guardada"] = str(receta_pendiente_selector)

                cargar_col1, cargar_col2 = st.columns([3, 1])
                with cargar_col1:
                    receta_id_seleccionada = st.selectbox(
                        "Recetas guardadas",
                        opciones_recetas,
                        format_func=lambda receta_id: recetas_por_id.get(str(receta_id), {}).get("etiqueta_selector", str(receta_id)),
                        key="selector_receta_guardada"
                    )
                with cargar_col2:
                    st.write("")
                    st.write("")
                    cargar_receta_btn = st.button("Cargar receta", use_container_width=True)

                if cargar_receta_btn:
                    cabecera, ingredientes_df = cargar_receta_detalle_supabase(receta_id_seleccionada)
                    ingredientes_cargados = preparar_ingredientes_receta_para_sesion(ingredientes_df)
                    if not cabecera:
                        st.error("No se pudo cargar la cabecera de la receta seleccionada.")
                    elif not ingredientes_cargados:
                        st.warning("La receta seleccionada no tiene ingredientes guardados.")
                    else:
                        raciones_cargadas = numero_seguro(cabecera.get("raciones_base", 1.0), 1.0)
                        st.session_state["ingredientes"] = ingredientes_cargados
                        st.session_state["ingredientes_base_raciones"] = [dict(ing) for ing in ingredientes_cargados]
                        st.session_state["factor_raciones"] = 1.0
                        st.session_state["raciones_base"] = raciones_cargadas
                        st.session_state["raciones_deseadas"] = raciones_cargadas
                        st.session_state["receta_raciones_base"] = raciones_cargadas
                        st.session_state["receta_raciones_deseadas"] = raciones_cargadas
                        st.session_state["raciones_base_aplicadas"] = raciones_cargadas
                        st.session_state["raciones_deseadas_aplicadas"] = raciones_cargadas
                        st.session_state["sincronizar_inputs_raciones"] = True
                        st.session_state["receta_nombre"] = str(cabecera.get("nombre", "") or "Mi Receta")
                        st.session_state["receta_categoria"] = str(cabecera.get("categoria", "") or "")
                        st.session_state["receta_tipo_plato"] = str(cabecera.get("tipo_plato", "") or "")
                        st.session_state["receta_observaciones"] = str(
                            cabecera.get("observaciones") or cabecera.get("descripcion") or ""
                        )
                        st.session_state["sincronizar_campos_receta"] = True
                        codigo_cargado = str(cabecera.get("codigo_receta", "") or "").strip()
                        nombre_cargado = str(cabecera.get("nombre", "") or "receta").strip()
                        st.session_state["receta_id_cargada"] = str(cabecera.get("id", receta_id_seleccionada))
                        st.session_state["codigo_receta_cargada"] = codigo_cargado
                        st.session_state["mensaje_receta_cargada"] = f"Receta cargada: {nombre_cargado} ({codigo_cargado})."
                        st.rerun()


    if st.session_state['ingredientes']:
        subtotal_ing_guardado = sum(float(ing.get('cantidad_bruta', 0.0)) * float(ing.get('precio_unidad', 0.0)) for ing in st.session_state['ingredientes'])
        ci_val = float(st.session_state.get('costes_indirectos_pct', 0.0))
        mb_val = float(st.session_state.get('margen_beneficio_pct', 0.0))
        iva_val = float(st.session_state.get('iva_pct', 0.0))
        costes_ind_guardado = subtotal_ing_guardado * (ci_val / 100)
        coste_total = subtotal_ing_guardado + costes_ind_guardado
        factor_margen_guardado = (1 - (mb_val / 100))
        pvp_neto = coste_total / factor_margen_guardado if factor_margen_guardado > 0 else 0.0
        pvp_final = pvp_neto + (pvp_neto * (iva_val / 100))
    else:
        ci_val = float(st.session_state.get('costes_indirectos_pct', 0.0))
        mb_val = float(st.session_state.get('margen_beneficio_pct', 0.0))
        iva_val = float(st.session_state.get('iva_pct', 0.0))
        coste_total = 0.0
        pvp_neto = 0.0
        pvp_final = 0.0
    st.divider()
    st.subheader("Guardar receta")
    if not supabase_disponible:
        st.warning("Supabase no está disponible. No se puede guardar la receta ahora.")
    if st.session_state.get("receta_id_cargada"):
        st.caption(f"Receta cargada para actualizar: {st.session_state.get('codigo_receta_cargada', 'sin código')}")

    with st.form("form_guardar_receta_nueva"):
        nombre_receta_guardar = st.text_input("Nombre de receta", value=st.session_state.get("receta_nombre", nombre_plato))
        categoria_receta = st.text_input("Categoría", key="input_receta_categoria")
        tipo_plato_receta = st.text_input("Tipo de plato", key="input_receta_tipo_plato")
        raciones_base_receta = st.number_input(
            "Raciones base",
            min_value=0.0,
            step=1.0,
            value=float(st.session_state.get('receta_raciones_base', st.session_state.get('raciones_base', 1.0)))
        )
        observaciones_receta = st.text_area("Descripción / observaciones", key="input_receta_observaciones", height=90)

        guardar_col, actualizar_col, duplicar_col = st.columns(3)
        with guardar_col:
            guardar_nueva = st.form_submit_button("Guardar como nueva receta", type="primary", use_container_width=True)
        with actualizar_col:
            actualizar_existente = st.form_submit_button("Actualizar receta seleccionada", use_container_width=True)
        with duplicar_col:
            duplicar_existente = st.form_submit_button("Duplicar receta seleccionada", use_container_width=True)

        if guardar_nueva or actualizar_existente or duplicar_existente:
            st.session_state["receta_nombre"] = str(nombre_receta_guardar or "").strip() or st.session_state.get("receta_nombre", "Mi Receta")
            st.session_state["receta_categoria"] = categoria_receta
            st.session_state["receta_tipo_plato"] = tipo_plato_receta
            st.session_state["receta_observaciones"] = observaciones_receta
            st.session_state["receta_raciones_base"] = float(raciones_base_receta)
            nombre_limpio = nombre_receta_guardar.strip()
            receta_id_cargada = st.session_state.get("receta_id_cargada")
            codigo_receta_cargada = st.session_state.get("codigo_receta_cargada", "")
            if not supabase_disponible or supabase is None:
                st.error("Supabase no está conectado correctamente.")
            elif not nombre_limpio:
                st.error("Indica un nombre de receta antes de guardar.")
            elif not st.session_state.get("ingredientes"):
                st.error("Añade al menos un ingrediente antes de guardar la receta.")
            elif actualizar_existente and not receta_id_cargada:
                st.warning("Carga una receta guardada antes de actualizarla.")
            elif duplicar_existente and not receta_id_cargada:
                st.warning("Carga una receta guardada antes de duplicarla.")
            else:
                codigo_receta = codigo_receta_cargada if actualizar_existente else generar_codigo_receta()
                datos_receta = {
                    "user_id": None,
                    "codigo_receta": codigo_receta,
                    "nombre": nombre_limpio,
                    "categoria": categoria_receta.strip(),
                    "tipo_plato": tipo_plato_receta.strip(),
                    "raciones_base": float(raciones_base_receta),
                    "unidad_servicio": "racion",
                    "descripcion": observaciones_receta.strip(),
                    "observaciones": observaciones_receta.strip(),
                    "costes_indirectos_pct": float(ci_val),
                    "margen_beneficio_pct": float(mb_val),
                    "iva_pct": float(iva_val),
                    "coste_total": float(coste_total),
                    "precio_venta_sin_iva": float(pvp_neto),
                    "precio_venta_con_iva": float(pvp_final),
                    "activa": True
                }
                if actualizar_existente:
                    ok, mensaje = actualizar_receta_supabase(
                        receta_id_cargada,
                        datos_receta,
                        st.session_state["ingredientes"]
                    )
                    if ok:
                        st.session_state["codigo_receta_cargada"] = codigo_receta
                        limpiar_cache_recetas_guardadas()
                        st.session_state["selector_receta_guardada_pendiente"] = receta_id_cargada
                        st.session_state["mensaje_receta_cargada"] = (
                            f"Receta actualizada correctamente con código {codigo_receta}. "
                            "Listado de recetas actualizado."
                        )
                        st.rerun()
                    else:
                        st.error(mensaje)
                elif duplicar_existente:
                    ok, mensaje, receta_guardada = duplicar_receta_supabase(
                        datos_receta,
                        st.session_state["ingredientes"]
                    )
                    if ok:
                        nuevo_codigo = receta_guardada.get("codigo_receta", "")
                        nuevo_nombre = receta_guardada.get("nombre", nombre_limpio)
                        st.session_state["receta_id_cargada"] = receta_guardada.get("id")
                        st.session_state["codigo_receta_cargada"] = nuevo_codigo
                        st.session_state["receta_nombre"] = nuevo_nombre
                        st.session_state["sincronizar_campos_receta"] = True
                        limpiar_cache_recetas_guardadas()
                        st.session_state["selector_receta_guardada_pendiente"] = receta_guardada.get("id")
                        st.session_state["mensaje_receta_cargada"] = (
                            f"Receta duplicada correctamente con código {nuevo_codigo}. "
                            "Listado de recetas actualizado."
                        )
                        st.rerun()
                    else:
                        st.error(mensaje)
                else:
                    ok, mensaje, receta_guardada = guardar_receta_nueva_supabase(
                        datos_receta,
                        st.session_state["ingredientes"]
                    )
                    if ok:
                        codigo_mostrado = receta_guardada.get("codigo_receta", codigo_receta)
                        st.session_state["receta_id_cargada"] = receta_guardada.get("id")
                        st.session_state["codigo_receta_cargada"] = codigo_mostrado
                        limpiar_cache_recetas_guardadas()
                        st.session_state["selector_receta_guardada_pendiente"] = receta_guardada.get("id")
                        st.session_state["mensaje_receta_cargada"] = (
                            f"Receta guardada correctamente con código {codigo_mostrado}. "
                            "Listado de recetas actualizado."
                        )
                        st.rerun()
                    else:
                        st.error(mensaje)

    st.divider()
    st.subheader("Eliminar receta")
    receta_id_para_eliminar = (
        str(receta_id_seleccionada)
        if receta_id_seleccionada
        else str(st.session_state.get("receta_id_cargada") or "")
    )
    receta_para_eliminar = recetas_por_id.get(receta_id_para_eliminar, {})

    if not supabase_disponible:
        st.warning("Supabase no está disponible. No se puede eliminar la receta ahora.")
    elif not receta_id_para_eliminar:
        st.info("Selecciona o carga una receta antes de intentar eliminarla.")
    else:
        codigo_eliminar = str(
            receta_para_eliminar.get("codigo_receta")
            or st.session_state.get("codigo_receta_cargada")
            or "sin código"
        )
        nombre_eliminar = str(
            receta_para_eliminar.get("nombre")
            or st.session_state.get("receta_nombre")
            or "receta seleccionada"
        )
        st.warning(
            "Esta acción no se puede deshacer. Se borrará la cabecera de la receta y "
            "sus ingredientes asociados. No se borrarán ingredientes del inventario."
        )
        st.write(f"**Receta seleccionada:** {codigo_eliminar} · {nombre_eliminar}")
        confirmacion_eliminar = st.text_input(
            "Escribe ELIMINAR para confirmar",
            key=f"confirmar_eliminar_receta_{receta_id_para_eliminar}"
        )
        if st.button("Eliminar receta seleccionada", type="secondary", use_container_width=True):
            if confirmacion_eliminar != "ELIMINAR":
                st.error("Para eliminar la receta debes escribir exactamente ELIMINAR.")
            else:
                ok, mensaje = eliminar_receta_supabase(receta_id_para_eliminar)
                if ok:
                    if str(st.session_state.get("receta_id_cargada") or "") == receta_id_para_eliminar:
                        st.session_state["receta_id_cargada"] = None
                        st.session_state["codigo_receta_cargada"] = ""
                    limpiar_cache_recetas_guardadas()
                    st.session_state["limpiar_selector_receta_guardada"] = True
                    st.session_state["mensaje_receta_cargada"] = "Receta eliminada correctamente. Listado de recetas actualizado."
                    st.rerun()
                else:
                    st.error(mensaje)

with main_tab_menus:
    st.subheader("Menús")
    st.caption("Construye un menú básico combinando recetas guardadas.")
    sincronizar_widgets_menu()

    mensaje_menu_cargado = st.session_state.pop("mensaje_menu_cargado", None)
    if mensaje_menu_cargado:
        st.success(mensaje_menu_cargado)
    mensaje_menu_aviso = st.session_state.pop("mensaje_menu_aviso", None)
    if mensaje_menu_aviso:
        st.warning(mensaje_menu_aviso)

    st.markdown("#### Cargar menú guardado")
    if not supabase_disponible:
        st.warning("Supabase no está disponible. No se pueden cargar menús guardados ahora.")
    else:
        menus_guardados_df = cargar_menus_supabase()
        if menus_guardados_df.empty:
            st.info("Todavía no hay menús guardados en Supabase.")
        else:
            menus_guardados_df = menus_guardados_df.copy()
            menus_guardados_df["etiqueta_selector"] = menus_guardados_df.apply(
                lambda row: f"{row.get('nombre', '')} · {row.get('tipo_menu', '')}".strip(" ·"),
                axis=1
            )
            opciones_menus = menus_guardados_df["id"].dropna().astype(str).tolist()
            menus_por_id = {
                str(row.get("id")): row.to_dict()
                for _, row in menus_guardados_df.iterrows()
                if row.get("id")
            }

            if opciones_menus:
                cargar_menu_col1, cargar_menu_col2 = st.columns([3, 1])
                with cargar_menu_col1:
                    menu_id_seleccionado = st.selectbox(
                        "Menús guardados",
                        opciones_menus,
                        format_func=lambda menu_id: menus_por_id.get(str(menu_id), {}).get("etiqueta_selector", str(menu_id)),
                        key="selector_menu_guardado"
                    )
                with cargar_menu_col2:
                    st.write("")
                    st.write("")
                    cargar_menu_btn = st.button("Cargar menú", use_container_width=True)

                if cargar_menu_btn:
                    cabecera_menu, lineas_menu_df = cargar_menu_detalle_supabase(menu_id_seleccionado)
                    if not cabecera_menu:
                        st.error("No se pudo cargar la cabecera del menú seleccionado.")
                    elif lineas_menu_df.empty:
                        st.warning("El menú seleccionado no tiene recetas guardadas.")
                    else:
                        lineas_reconstruidas = []
                        for orden, linea in enumerate(lineas_menu_df.to_dict(orient="records"), start=1):
                            precio_receta = linea.get("precio_receta_con_iva", None)
                            if precio_receta is None or pd.isna(precio_receta):
                                precio_receta = linea.get("precio_receta_sin_iva", None)

                            hay_precio_receta = precio_receta is not None and not pd.isna(precio_receta)
                            lineas_reconstruidas.append(recalcular_linea_menu({
                                "receta_id": str(linea.get("receta_id", "") or ""),
                                "codigo_receta": str(linea.get("codigo_receta", "") or ""),
                                "nombre_receta": str(linea.get("nombre_receta", "") or "Receta sin nombre"),
                                "raciones": float(numero_seguro(linea.get("raciones", 1.0), 1.0)),
                                "raciones_base": float(numero_seguro(linea.get("raciones_base", 0.0), 0.0)),
                                "coste_receta": float(numero_seguro(linea.get("coste_receta", 0.0), 0.0)),
                                "precio_receta": float(numero_seguro(precio_receta, 0.0)) if hay_precio_receta else None,
                                "orden": int(numero_seguro(linea.get("orden", orden), orden)),
                                "seccion": str(linea.get("seccion", "") or "")
                            }))

                        st.session_state["menu_actual"] = normalizar_lineas_menu(lineas_reconstruidas)
                        st.session_state["menu_id"] = str(cabecera_menu.get("id", menu_id_seleccionado))
                        st.session_state["menu_nombre"] = str(cabecera_menu.get("nombre", "") or "")
                        st.session_state["menu_tipo"] = str(cabecera_menu.get("tipo_menu", "") or "Otro")
                        st.session_state["menu_numero_comensales"] = int(numero_seguro(cabecera_menu.get("numero_comensales", 1), 1))
                        st.session_state["mensaje_menu_cargado"] = f"Menú cargado: {st.session_state['menu_nombre']}."
                        st.rerun()

    st.divider()

    menu_col1, menu_col2 = st.columns([2, 1])
    with menu_col1:
        nombre_menu = st.text_input("Nombre del menú", key="menu_nombre")
    with menu_col2:
        opciones_tipo_menu = ["Cóctel", "Buffet", "Menú sentado", "Catering", "Otro"]
        tipo_menu_actual = st.session_state.get("menu_tipo", "")
        if tipo_menu_actual and tipo_menu_actual not in opciones_tipo_menu:
            opciones_tipo_menu.append(tipo_menu_actual)
        tipo_menu = st.selectbox(
            "Tipo de menú",
            opciones_tipo_menu,
            key="menu_tipo"
        )

    if st.session_state.get("menu_id"):
        st.caption(f"Menú cargado para actualizar: {st.session_state['menu_id']}")

    numero_comensales = st.number_input(
        "Número de comensales",
        min_value=1,
        step=1,
        value=int(st.session_state.get("menu_numero_comensales", 1) or 1),
        key="menu_numero_comensales"
    )
    raciones_nueva_linea_default = float(numero_comensales) if numero_comensales and numero_comensales > 0 else 1.0
    if st.session_state.get("menu_comensales_raciones_sync") != int(numero_comensales):
        st.session_state["menu_raciones_receta"] = raciones_nueva_linea_default
        st.session_state["menu_comensales_raciones_sync"] = int(numero_comensales)

    st.divider()
    st.markdown("#### Añadir recetas")

    recetas_menu_df = pd.DataFrame()
    recetas_menu_por_id = {}
    opciones_recetas_menu = []

    if not supabase_disponible:
        st.warning("Supabase no está disponible. No se pueden cargar recetas guardadas ahora.")
    else:
        recetas_menu_df = cargar_recetas_supabase()
        if recetas_menu_df.empty:
            st.info("Todavía no hay recetas guardadas para crear un menú.")
        else:
            recetas_menu_df = recetas_menu_df.copy()
            recetas_menu_df["etiqueta_selector"] = recetas_menu_df.apply(
                lambda row: f"{row.get('codigo_receta', '')} · {row.get('nombre', '')}".strip(" ·"),
                axis=1
            )
            opciones_recetas_menu = recetas_menu_df["id"].dropna().astype(str).tolist()
            recetas_menu_por_id = {
                str(row.get("id")): row.to_dict()
                for _, row in recetas_menu_df.iterrows()
                if row.get("id")
            }

    if opciones_recetas_menu:
        add_col1, add_col2, add_col3, add_col4 = st.columns([3, 1, 1, 1])
        with add_col1:
            receta_menu_id = st.selectbox(
                "Recetas guardadas",
                opciones_recetas_menu,
                format_func=lambda receta_id: recetas_menu_por_id.get(str(receta_id), {}).get("etiqueta_selector", str(receta_id)),
                key="selector_receta_menu"
            )
        with add_col2:
            raciones_linea_menu = st.number_input(
                "Raciones de esta receta",
                min_value=0.0,
                step=1.0,
                key="menu_raciones_receta"
            )
        with add_col3:
            seccion_linea_menu = st.selectbox(
                "Sección",
                SECCIONES_MENU,
                format_func=lambda valor: valor or "Sin sección",
                key="menu_seccion_receta"
            )
        with add_col4:
            st.write("")
            st.write("")
            anadir_receta_menu = st.button("Añadir receta al menú", use_container_width=True)

        if anadir_receta_menu:
            receta_seleccionada = recetas_menu_por_id.get(str(receta_menu_id), {})
            if any(str(linea.get("receta_id")) == str(receta_menu_id) for linea in st.session_state["menu_actual"]):
                st.session_state["mensaje_menu_aviso"] = (
                    "Esta receta ya está en el menú. Puedes mantenerla duplicada si representa otro pase "
                    "o quitar una de las líneas."
                )
            linea_menu = crear_linea_menu_desde_receta(
                receta_menu_id,
                receta_seleccionada,
                raciones_linea_menu,
                len(st.session_state["menu_actual"]) + 1,
                seccion_linea_menu
            )
            st.session_state["menu_actual"].append(linea_menu)
            st.session_state["menu_actual"] = normalizar_lineas_menu(st.session_state["menu_actual"])
            st.success(f"Receta añadida al menú: {linea_menu['nombre_receta']}.")
            st.rerun()

    st.divider()
    st.markdown("#### Menú actual")

    lineas_menu_actual = normalizar_lineas_menu(st.session_state.get("menu_actual", []))
    if lineas_menu_actual != st.session_state.get("menu_actual", []):
        st.session_state["menu_actual"] = lineas_menu_actual

    if lineas_menu_actual:
        if any(numero_seguro(linea.get("raciones_base", 0.0), 0.0) <= 0 for linea in lineas_menu_actual):
            st.warning("Hay recetas sin raciones base. Para esas líneas se usa factor 1 al calcular costes.")

        menu_editor_df = pd.DataFrame([
            {
                "orden": linea.get("orden", idx + 1),
                "codigo_receta": linea.get("codigo_receta", ""),
                "nombre_receta": linea.get("nombre_receta", ""),
                "raciones": linea.get("raciones", 1.0),
                "raciones_base": linea.get("raciones_base", 0.0),
                "coste_receta": linea.get("coste_receta", 0.0),
                "coste_total_linea": linea.get("coste_total_linea", 0.0),
                "precio_total_linea": linea.get("precio_total_linea", None),
                "seccion": linea.get("seccion", "")
            }
            for idx, linea in enumerate(lineas_menu_actual)
        ])
        menu_editado_df = st.data_editor(
            menu_editor_df,
            num_rows="fixed",
            use_container_width=True,
            hide_index=True,
            column_config={
                "orden": st.column_config.NumberColumn("Orden", min_value=1, step=1, width="small"),
                "codigo_receta": st.column_config.TextColumn("Código receta", width="small"),
                "nombre_receta": st.column_config.TextColumn("Receta", width="medium"),
                "raciones": st.column_config.NumberColumn("Raciones", min_value=0.0, step=1.0, format="%.2f"),
                "raciones_base": st.column_config.NumberColumn("Raciones base", format="%.2f"),
                "coste_receta": st.column_config.NumberColumn("Coste receta", format="%.2f €"),
                "coste_total_linea": st.column_config.NumberColumn("Coste línea", format="%.2f €"),
                "precio_total_linea": st.column_config.NumberColumn("Precio línea", format="%.2f €"),
                "seccion": st.column_config.SelectboxColumn(
                    "Sección",
                    options=SECCIONES_MENU,
                    help="Se guarda en menu_recetas.seccion si la columna existe."
                )
            },
            disabled=["codigo_receta", "nombre_receta", "raciones_base", "coste_receta", "coste_total_linea", "precio_total_linea"],
            key="editor_lineas_menu"
        )

        lineas_editadas = []
        for idx, fila in menu_editado_df.iterrows():
            linea_actualizada = dict(lineas_menu_actual[idx])
            linea_actualizada["orden"] = int(numero_seguro(fila.get("orden", idx + 1), idx + 1))
            linea_actualizada["raciones"] = numero_seguro(fila.get("raciones", 1.0), 1.0)
            linea_actualizada["seccion"] = str(fila.get("seccion", "") or "").strip()
            lineas_editadas.append(recalcular_linea_menu(linea_actualizada))
        lineas_editadas = normalizar_lineas_menu(lineas_editadas)
        if lineas_editadas != st.session_state.get("menu_actual", []):
            st.session_state["menu_actual"] = lineas_editadas
            lineas_menu_actual = lineas_editadas

        st.markdown("#### Acciones por plato")
        for idx, linea in enumerate(lineas_menu_actual):
            fila_col1, fila_col2, fila_col3, fila_col4 = st.columns([4, 1, 1, 1])
            with fila_col1:
                st.write(f"{linea.get('orden', idx + 1)}. {linea.get('codigo_receta', '')} · {linea.get('nombre_receta', '')}")
            with fila_col2:
                if st.button("Subir", key=f"subir_menu_{idx}", disabled=idx == 0, use_container_width=True):
                    lineas_reordenadas = list(lineas_menu_actual)
                    lineas_reordenadas[idx - 1], lineas_reordenadas[idx] = lineas_reordenadas[idx], lineas_reordenadas[idx - 1]
                    for orden, item in enumerate(lineas_reordenadas, start=1):
                        item["orden"] = orden
                    st.session_state["menu_actual"] = normalizar_lineas_menu(lineas_reordenadas)
                    st.rerun()
            with fila_col3:
                if st.button("Bajar", key=f"bajar_menu_{idx}", disabled=idx == len(lineas_menu_actual) - 1, use_container_width=True):
                    lineas_reordenadas = list(lineas_menu_actual)
                    lineas_reordenadas[idx + 1], lineas_reordenadas[idx] = lineas_reordenadas[idx], lineas_reordenadas[idx + 1]
                    for orden, item in enumerate(lineas_reordenadas, start=1):
                        item["orden"] = orden
                    st.session_state["menu_actual"] = normalizar_lineas_menu(lineas_reordenadas)
                    st.rerun()
            with fila_col4:
                if st.button("Quitar del menú", key=f"quitar_menu_{idx}", use_container_width=True):
                    lineas_reordenadas = list(lineas_menu_actual)
                    lineas_reordenadas.pop(idx)
                    for orden, item in enumerate(lineas_reordenadas, start=1):
                        item["orden"] = orden
                    st.session_state["menu_actual"] = normalizar_lineas_menu(lineas_reordenadas)
                    st.rerun()
    else:
        st.info("Añade recetas guardadas para construir el menú actual.")

    total_coste_menu = sum(numero_seguro(linea.get("coste_total_linea", 0.0), 0.0) for linea in lineas_menu_actual)
    lineas_con_precio = [
        linea for linea in lineas_menu_actual
        if linea.get("precio_total_linea") is not None and not pd.isna(linea.get("precio_total_linea"))
    ]
    hay_precio_menu = bool(lineas_con_precio)
    total_precio_menu = sum(numero_seguro(linea.get("precio_total_linea", 0.0), 0.0) for linea in lineas_con_precio)
    coste_por_comensal = total_coste_menu / numero_comensales if numero_comensales > 0 else 0.0
    precio_por_comensal = total_precio_menu / numero_comensales if hay_precio_menu and numero_comensales > 0 else None

    resumen_col1, resumen_col2, resumen_col3 = st.columns(3)
    with resumen_col1:
        st.metric("Recetas / platos", f"{len(lineas_menu_actual)}")
        st.metric("Comensales", f"{int(numero_comensales)}")
    with resumen_col2:
        st.metric("Coste total del menú", f"{total_coste_menu:.2f} €")
        st.metric("Coste por comensal", f"{coste_por_comensal:.2f} €")
    with resumen_col3:
        if hay_precio_menu:
            st.metric("Precio total del menú", f"{total_precio_menu:.2f} €")
            st.metric("Precio por comensal", f"{precio_por_comensal:.2f} €")
        else:
            st.metric("Precio total del menú", "Sin datos")
            st.metric("Precio por comensal", "Sin datos")

    accion_menu_col1, accion_menu_col2, accion_menu_col3, accion_menu_col4 = st.columns(4)
    with accion_menu_col1:
        if st.button("Guardar menú", type="primary", use_container_width=True):
            nombre_menu_limpio = str(nombre_menu or "").strip()
            if not supabase_disponible or supabase is None:
                st.error("Supabase no está conectado correctamente.")
            elif not nombre_menu_limpio:
                st.error("Indica un nombre de menú antes de guardar.")
            elif not lineas_menu_actual:
                st.error("Añade al menos una receta antes de guardar el menú.")
            else:
                datos_menu = {
                    "user_id": None,
                    "nombre": nombre_menu_limpio,
                    "tipo_menu": tipo_menu,
                    "descripcion": "",
                    "numero_comensales": int(numero_comensales),
                    "coste_total": float(total_coste_menu),
                    "precio_total": float(total_precio_menu) if hay_precio_menu else None
                }
                ok, mensaje, menu_guardado = guardar_menu_supabase(datos_menu, lineas_menu_actual)
                if ok:
                    st.session_state["menu_id"] = menu_guardado.get("id")
                    st.success(f"Menú guardado correctamente: {menu_guardado.get('nombre', nombre_menu_limpio)}.")
                else:
                    st.error(mensaje)
    with accion_menu_col2:
        if st.button("Actualizar menú seleccionado", use_container_width=True):
            menu_id_actual = st.session_state.get("menu_id")
            nombre_menu_limpio = str(nombre_menu or "").strip()
            if not supabase_disponible or supabase is None:
                st.error("Supabase no está conectado correctamente.")
            elif not menu_id_actual:
                st.warning("Carga un menú guardado antes de actualizarlo.")
            elif not nombre_menu_limpio:
                st.error("Indica un nombre de menú antes de actualizar.")
            elif not lineas_menu_actual:
                st.warning("Añade al menos una receta antes de actualizar el menú.")
            else:
                datos_menu = {
                    "nombre": nombre_menu_limpio,
                    "tipo_menu": tipo_menu,
                    "descripcion": "",
                    "numero_comensales": int(numero_comensales),
                    "coste_total": float(total_coste_menu),
                    "precio_total": float(total_precio_menu) if hay_precio_menu else None
                }
                ok, mensaje = actualizar_menu_supabase(menu_id_actual, datos_menu, lineas_menu_actual)
                if ok:
                    st.success("Menú actualizado correctamente.")
                else:
                    st.error(mensaje)
    with accion_menu_col3:
        if st.button("Duplicar menú seleccionado", use_container_width=True):
            menu_id_actual = st.session_state.get("menu_id")
            nombre_menu_limpio = str(nombre_menu or "").strip()
            if not supabase_disponible or supabase is None:
                st.error("Supabase no está conectado correctamente.")
            elif not menu_id_actual:
                st.warning("Carga un menú guardado antes de duplicarlo.")
            elif not nombre_menu_limpio:
                st.error("Indica un nombre de menú antes de duplicarlo.")
            elif not lineas_menu_actual:
                st.warning("Añade al menos una receta antes de duplicar el menú.")
            else:
                nuevo_nombre_menu = generar_nombre_copia_menu(nombre_menu_limpio)
                datos_menu = {
                    "user_id": None,
                    "nombre": nuevo_nombre_menu,
                    "tipo_menu": tipo_menu,
                    "descripcion": "",
                    "numero_comensales": int(numero_comensales),
                    "coste_total": float(total_coste_menu),
                    "precio_total": float(total_precio_menu) if hay_precio_menu else None
                }
                ok, mensaje, menu_guardado = guardar_menu_supabase(datos_menu, lineas_menu_actual)
                if ok:
                    st.session_state["menu_id"] = menu_guardado.get("id")
                    st.session_state["menu_nombre_pendiente"] = menu_guardado.get("nombre", nuevo_nombre_menu)
                    st.session_state["menu_tipo_pendiente"] = tipo_menu
                    st.session_state["menu_numero_comensales_pendiente"] = int(numero_comensales)
                    st.session_state["sincronizar_campos_menu"] = True
                    st.session_state["mensaje_menu_cargado"] = f"Menú duplicado correctamente: {st.session_state['menu_nombre_pendiente']}."
                    st.rerun()
                else:
                    st.error(mensaje)
    with accion_menu_col4:
        if st.button("Limpiar menú actual", use_container_width=True):
            st.session_state["menu_actual"] = []
            st.session_state["menu_id"] = None
            st.success("Menú actual limpiado.")
            st.rerun()


with main_tab_base:
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
                "unidad_medida": st.column_config.TextColumn("Unidad Base", help="kg, l, ud, sobre..."),
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
                                "unidad_medida": edits.get("unidad_medida", fila_original.get("unidad_medida", "kg")),
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
                                    "unidad_medida": nueva_fila.get("unidad_medida", "kg"),
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
