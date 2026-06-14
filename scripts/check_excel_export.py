import ast
import io
from pathlib import Path

import openpyxl
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter


def cargar_funciones_excel():
    source = Path("generador_fichas.py").read_text(encoding="utf-8")
    module = ast.parse(source)
    func_nodes = [
        node for node in module.body
        if isinstance(node, ast.FunctionDef) and node.name in {"ajustar_ingredientes_por_raciones", "generar_excel"}
    ]
    compiled = compile(ast.Module(body=func_nodes, type_ignores=[]), "generador_fichas.py", "exec")
    namespace = {
        "openpyxl": openpyxl,
        "Font": Font,
        "Alignment": Alignment,
        "PatternFill": PatternFill,
        "get_column_letter": get_column_letter,
        "io": io,
        "pd": __import__("pandas"),
    }
    exec(compiled, namespace)
    return namespace["ajustar_ingredientes_por_raciones"], namespace["generar_excel"]


def comprobar_ajuste_raciones(ajustar_ingredientes_por_raciones):
    ingredientes = [
        {"codigo": "ACE-01", "descripcion": "Aceite", "cantidad_bruta": 2.0, "merma": 5.0, "precio_unidad": 1.69},
        {"codigo": "HAR-01", "descripcion": "Harina", "cantidad_bruta": 4.0, "merma": 10.0, "precio_unidad": 1.1128},
    ]

    duplicados = ajustar_ingredientes_por_raciones(ingredientes, 20 / 10)
    reducidos = ajustar_ingredientes_por_raciones(ingredientes, 5 / 10)

    assert duplicados[0]["cantidad_bruta"] == 4.0
    assert duplicados[1]["cantidad_bruta"] == 8.0
    assert reducidos[0]["cantidad_bruta"] == 1.0
    assert reducidos[1]["cantidad_bruta"] == 2.0
    assert duplicados[0]["precio_unidad"] == ingredientes[0]["precio_unidad"]
    assert duplicados[1]["merma"] == ingredientes[1]["merma"]
    assert duplicados[0]["codigo"] == ingredientes[0]["codigo"]
    assert duplicados[1]["descripcion"] == ingredientes[1]["descripcion"]


def main():
    ajustar_ingredientes_por_raciones, generar_excel = cargar_funciones_excel()
    comprobar_ajuste_raciones(ajustar_ingredientes_por_raciones)
    ingredientes = [
        {"codigo": "ACE-01", "descripcion": "Aceite", "cantidad_bruta": 2.0, "merma": 0.0, "precio_unidad": 1.69},
        {"codigo": "HAR-01", "descripcion": "Harina", "cantidad_bruta": 3.0, "merma": 5.0, "precio_unidad": 1.1128},
        {"codigo": "HUE-01", "descripcion": "Huevos", "cantidad_bruta": 12.0, "merma": 0.0, "precio_unidad": 0.25},
    ]
    workbook_bytes = generar_excel("Prueba", ingredientes, 10.0, 30.0, 10.0, 10.0, 25.0, 2.5)
    wb = openpyxl.load_workbook(workbook_bytes, data_only=False)
    ws = wb["Ficha Técnica"]

    expected = {
        "B2": 10.0,
        "E2": 25.0,
        "B3": 2.5,
        "E6": "=C6*(1-D6)",
        "G6": "=C6*F6",
        "E7": "=C7*(1-D7)",
        "G7": "=C7*F7",
        "G10": "=SUM(G6:G8)",
        "G11": "=G10*(10.0/100)",
        "G12": "=G10+G11",
        "G15": "=G12/(1-(30.0/100))",
        "G16": "=G15*(10.0/100)",
        "G17": "=G15+G16",
    }
    for cell, formula in expected.items():
        value = ws[cell].value
        if value != formula:
            raise AssertionError(f"{cell}: esperado {formula!r}, recibido {value!r}")

    if not wb.calculation.fullCalcOnLoad:
        raise AssertionError("El libro no fuerza recalculo al abrir.")

    print("Excel export formulas OK")


if __name__ == "__main__":
    main()
