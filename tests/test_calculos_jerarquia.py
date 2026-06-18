import unittest

from calculos_jerarquia import (
    calcular_coste_factura,
    calcular_coste_menu,
    calcular_coste_por_racion,
    calcular_coste_presupuesto,
    calcular_coste_receta,
)


class CalculosJerarquiaTest(unittest.TestCase):
    def test_ejemplo_menu_y_presupuesto(self):
        lineas_menu = [
            {
                "coste_por_racion_receta": 1.50,
                "raciones_receta_en_menu": 80,
            },
            {
                "coste_por_racion_receta": 0.90,
                "raciones_receta_en_menu": 60,
            },
        ]
        self.assertAlmostEqual(calcular_coste_menu(lineas_menu), 174.0)

        lineas_presupuesto = [{
            "coste_total_menu": calcular_coste_menu(lineas_menu),
            "cantidad_menu": 2,
        }]
        self.assertAlmostEqual(
            calcular_coste_presupuesto(lineas_presupuesto),
            348.0,
        )
        self.assertAlmostEqual(
            calcular_coste_factura(lineas_presupuesto),
            348.0,
        )

    def test_receta_y_coste_por_racion(self):
        ingredientes = [
            {"cantidad_usada": 2, "precio_unidad": 3.25},
            {"cantidad_bruta": 0.5, "precio_unidad": 4},
        ]
        coste = calcular_coste_receta(ingredientes)
        self.assertAlmostEqual(coste, 8.5)
        self.assertAlmostEqual(calcular_coste_por_racion(coste, 5), 1.7)

    def test_rechaza_cantidades_no_positivas(self):
        with self.assertRaises(ValueError):
            calcular_coste_receta([
                {"cantidad_usada": 0, "precio_unidad": 1},
            ])
        with self.assertRaises(ValueError):
            calcular_coste_por_racion(10, 0)
        with self.assertRaises(ValueError):
            calcular_coste_menu([
                {
                    "coste_por_racion_receta": 1,
                    "raciones_receta_en_menu": 0,
                }
            ])
        with self.assertRaises(ValueError):
            calcular_coste_presupuesto([
                {"coste_total_menu": 10, "cantidad_menu": 0},
            ])

    def test_rechaza_importes_negativos(self):
        with self.assertRaises(ValueError):
            calcular_coste_receta([
                {"cantidad_usada": 1, "precio_unidad": -1},
            ])
        with self.assertRaises(ValueError):
            calcular_coste_factura([
                {"cantidad_menu": 1, "coste_total_menu": -10},
            ])


if __name__ == "__main__":
    unittest.main()
