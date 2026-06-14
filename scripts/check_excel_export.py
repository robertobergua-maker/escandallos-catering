import ast
import io
from pathlib import Path

import openpyxl
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter


def cargar_generar_excel():
    source = Path("generador_fichas.py").read_text(encoding="utf-8")
    module = ast.parse(source)
    func_node = next(
        node for node in module.body
        if isinstance(node, ast.FunctionDef) and node.name == "generar_excel"
    )
    compiled = compile(ast.Module(body=[func_node], type_ignores=[]), "generador_fichas.py", "exec")
    namespace = {
        "openpyxl": openpyxl,
        "Font": Font,
        "Alignment": Alignment,
        "PatternFill": PatternFill,
        "get_column_letter": get_column_letter,
        "io": io,
    }
    exec(compiled, namespace)
    return namespace["generar_excel"]


def main():
    generar_excel = cargar_generar_excel()
    ingredientes = [
        {"codigo": "ACE-01", "descripcion": "Aceite", "cantidad_bruta": 2.0, "merma": 0.0, "precio_unidad": 1.69},
        {"codigo": "HAR-01", "descripcion": "Harina", "cantidad_bruta": 3.0, "merma": 5.0, "precio_unidad": 1.1128},
        {"codigo": "HUE-01", "descripcion": "Huevos", "cantidad_bruta": 12.0, "merma": 0.0, "precio_unidad": 0.25},
    ]
    workbook_bytes = generar_excel("Prueba", ingredientes, 10.0, 30.0, 10.0)
    wb = openpyxl.load_workbook(workbook_bytes, data_only=False)
    ws = wb["Ficha Técnica"]

    expected = {
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
