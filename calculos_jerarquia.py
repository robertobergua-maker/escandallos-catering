"""Calculos puros para la jerarquia receta -> menu -> documento."""

from math import isfinite


def _numero(valor, nombre):
    try:
        numero = float(valor)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{nombre} debe ser un numero valido.") from exc
    if not isfinite(numero):
        raise ValueError(f"{nombre} debe ser un numero finito.")
    return numero


def _no_negativo(valor, nombre):
    numero = _numero(valor, nombre)
    if numero < 0:
        raise ValueError(f"{nombre} no puede ser negativo.")
    return numero


def _positivo(valor, nombre):
    numero = _numero(valor, nombre)
    if numero <= 0:
        raise ValueError(f"{nombre} debe ser mayor que 0.")
    return numero


def calcular_coste_receta(ingredientes):
    """Suma el coste de los ingredientes de una receta."""
    lineas = list(ingredientes or [])
    if not lineas:
        raise ValueError("La receta debe contener al menos un ingrediente.")

    coste_total = 0.0
    for indice, ingrediente in enumerate(lineas, start=1):
        cantidad = _positivo(
            ingrediente.get(
                "cantidad_usada",
                ingrediente.get("cantidad_bruta", ingrediente.get("cantidad", 0)),
            ),
            f"Cantidad del ingrediente {indice}",
        )
        precio_unidad = _no_negativo(
            ingrediente.get("precio_unidad", ingrediente.get("precio", 0)),
            f"Precio del ingrediente {indice}",
        )
        coste_total += cantidad * precio_unidad
    return coste_total


def calcular_coste_por_racion(coste_total_receta, raciones_base_receta):
    """Devuelve el coste unitario de una receta."""
    coste_total = _no_negativo(coste_total_receta, "Coste total de receta")
    raciones_base = _positivo(raciones_base_receta, "Raciones base de receta")
    return coste_total / raciones_base


def calcular_coste_menu(lineas_receta):
    """Suma coste por racion por las raciones propias de cada receta."""
    lineas = list(lineas_receta or [])
    if not lineas:
        raise ValueError("El menu debe contener al menos una receta.")

    total = 0.0
    for indice, linea in enumerate(lineas, start=1):
        raciones = _positivo(
            linea.get(
                "raciones_receta_en_menu",
                linea.get("raciones", 0),
            ),
            f"Raciones de la receta {indice} en el menu",
        )
        coste_por_racion = linea.get("coste_por_racion_receta")
        if coste_por_racion is None:
            coste_por_racion = calcular_coste_por_racion(
                linea.get("coste_total_receta", linea.get("coste_receta", 0)),
                linea.get("raciones_base_receta", linea.get("raciones_base", 0)),
            )
        coste_por_racion = _no_negativo(
            coste_por_racion,
            f"Coste por racion de la receta {indice}",
        )
        total += coste_por_racion * raciones
    return total


def calcular_coste_presupuesto(lineas_menu):
    """Suma el coste congelado de cada menu por su cantidad."""
    lineas = list(lineas_menu or [])
    if not lineas:
        raise ValueError("El presupuesto debe contener al menos un menu.")

    total = 0.0
    for indice, linea in enumerate(lineas, start=1):
        cantidad = _positivo(
            linea.get("cantidad_menu", linea.get("cantidad", 0)),
            f"Cantidad del menu {indice}",
        )
        coste_menu = _no_negativo(
            linea.get("coste_total_menu", linea.get("coste_menu", 0)),
            f"Coste del menu {indice}",
        )
        total += coste_menu * cantidad
    return total


def calcular_coste_factura(lineas_menu):
    """Calcula una factura desde importes de menu ya congelados."""
    lineas = list(lineas_menu or [])
    if not lineas:
        raise ValueError("La factura debe contener al menos un menu.")

    total = 0.0
    for indice, linea in enumerate(lineas, start=1):
        cantidad = _positivo(
            linea.get("cantidad_menu", linea.get("cantidad", 0)),
            f"Cantidad del menu {indice}",
        )
        coste_linea = linea.get("coste_linea_menu_factura")
        if coste_linea is None:
            coste_menu = _no_negativo(
                linea.get("coste_total_menu", linea.get("coste_menu", 0)),
                f"Coste del menu {indice}",
            )
            coste_linea = coste_menu * cantidad
        total += _no_negativo(coste_linea, f"Coste de linea de factura {indice}")
    return total
