# Modulo de facturacion

Este documento resume la base preparada en `sql/015_facturacion_base.sql`.

## Objetivo

El SQL prepara las tablas iniciales para un modulo de facturacion interna de Samirarte. No ejecuta ninguna adaptacion legal completa y no debe activarse como sistema fiscal definitivo sin revisar los requisitos legales aplicables.

## Tablas creadas

### `clientes`

Guarda los datos basicos de clientes:

- nombre;
- tipo de cliente;
- NIF/CIF;
- email y telefono;
- direccion postal;
- pais;
- observaciones;
- `user_id` para asociar el cliente al usuario conectado en una fase posterior.

### `facturas`

Guarda la cabecera de cada documento:

- cliente relacionado;
- numero de factura;
- tipo de documento;
- estado;
- fechas de emision y vencimiento;
- concepto;
- base imponible, IVA, retencion y total;
- metodo de pago;
- estado de cobro;
- notas.

### `factura_lineas`

Guarda las lineas economicas de cada documento:

- descripcion;
- cantidad;
- unidad;
- precio unitario;
- descuento;
- base, IVA y total de linea;
- orden;
- origen futuro de la linea.

## Relacion cliente, factura y lineas

La relacion principal es:

1. Un cliente puede tener muchas facturas mediante `facturas.cliente_id`.
2. Una factura puede tener muchas lineas mediante `factura_lineas.factura_id`.
3. Las lineas se eliminan automaticamente si se elimina la factura por la relacion `on delete cascade`.

## Relacion futura con menus y eventos

`factura_lineas` incluye `origen_tipo` y `origen_id` para enlazar mas adelante lineas generadas desde:

- menus;
- eventos;
- recetas;
- conceptos manuales.

La app todavia no usa estos campos. Quedan preparados para una fase posterior.

## Estados recomendados

Para `facturas.estado`:

- `borrador`;
- `emitida`;
- `cobrada`;
- `anulada`.

Para `facturas.estado_cobro`, se recomienda empezar con:

- `pendiente`;
- `parcial`;
- `cobrado`.

## Tipos de documento

Para `facturas.tipo_documento`:

- `presupuesto`;
- `factura`;
- `factura_rectificativa`.

## Indices

El SQL anade indices para:

- clientes por `user_id`;
- clientes por `nombre`;
- facturas por `user_id`;
- facturas por `cliente_id`;
- facturas por `numero_factura`;
- lineas por `factura_id`.

## Advertencia legal

Este modulo no certifica cumplimiento VERI*FACTU, no sustituye revision fiscal y no debe activarse como sistema fiscal definitivo sin revisar los requisitos legales. La adaptacion legal completa se hara en una fase posterior.

## RLS

Este SQL no activa RLS para facturacion. La seguridad por usuario de clientes, facturas y lineas se preparara en otro paso.
