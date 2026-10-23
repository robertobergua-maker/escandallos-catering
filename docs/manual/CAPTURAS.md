# Lista de capturas para el manual (Gerente y Chef)

Cómo hacerlas:
- Entorno de PRUEBAS (nuevo-escandallos.escandallos.samirarte.com), con el usuario demo y la organización "Restaurante Demo".
- Navegador a pantalla completa, zoom 100 %. Captura: Win + Shift + S → ventana del navegador.
- Guardar en PNG en `docs/manual/capturas/` con EXACTAMENTE el nombre indicado.
- Que no salgan datos reales (clientes, correos o precios de Samirarte).
- Si una pantalla no existe o es distinta, sáltala y apúntalo al final de este fichero.

## 0. Acceso (sin sesión)
- [ ] 00-portada.png — portada con "Entrar a la aplicación"
- [ ] 01-login.png — pantalla de acceso (Google / email y contraseña / ¿Has olvidado tu contraseña?)
- [ ] 02-canjear-invitacion.png — pantalla para canjear una invitación (usuario nuevo sin organización), si puedes verla

## 1. Común (chef y gerente) — pestaña Recetas
- [ ] 10-inicio-sidebar.png — pantalla principal con la barra lateral (logo, organización activa, sesión)
- [ ] 11-selector-organizacion.png — desplegable "Organización activa" abierto (si el usuario tiene más de una)
- [ ] 12-receta-nueva.png — receta vacía: nombre, categoría, tipo de plato, raciones base
- [x] 13-receta-ingredientes.png — tabla de ingredientes con varias filas rellenas
- [ ] 14-ficha-ingrediente.png — barra lateral "Ficha de ingrediente" con un ingrediente seleccionado
- [ ] 15-costes-pvp.png — coste por ración, PVP por ración y Food Cost con valores
- [ ] 16-alergenos-receta.png — bloque "Alérgenos detectados" con alérgenos
- [x] 17-ia-generar-receta.png — IA con texto: texto de la receta escrito, antes de pulsar "Analizar texto con IA"
- [ ] 17b-ia-texto-resultado.png — IA con texto: tabla de ingredientes rellenada por la IA tras analizar
- [ ] 17c-ia-imagen-subida.png — IA con imagen: pestaña "Imagen" con la foto de una receta subida, antes de escanear
- [ ] 17d-ia-imagen-resultado.png — IA con imagen: ingredientes rellenados tras "Escanear imagen con IA Vision"
- [ ] 18-parametros-avanzados.png — expander "Parámetros avanzados" abierto
- [ ] 19-elaboracion.png — expander "Elaboración y observaciones" abierto
- [ ] 20-recetas-guardadas.png — "Recetas guardadas" con el selector y "Cargar receta"
- [ ] 21-ajuste-raciones.png — aviso de ajuste de raciones base (Confirmar ajuste / Cancelar)
- [ ] 22-descarga-ficha.png — botón de descarga de la ficha técnica (y, si puedes, la ficha abierta en Excel)
- [ ] 23-recetas-compartidas.png — recetas compartidas con mi organización y su vista previa

## 2. Común — pestaña Menús
- [ ] 30-menu-nuevo.png — menú con recetas añadidas (Subir / Bajar / Quitar del menú)
- [ ] 31-menu-alergenos.png — alérgenos del menú
- [ ] 32-menu-guardar.png — botones Guardar / Actualizar / Duplicar / Limpiar menú
- [ ] 33-menu-cargar.png — cargar un menú guardado
- [ ] 34-menu-descarga.png — descarga del menú

## 3. Común — pestaña Clientes
- [ ] 40-clientes-lista.png — lista de clientes
- [ ] 41-cliente-nuevo.png — formulario de cliente rellenado (datos inventados)

## 4. Pestaña Facturas — como CHEF
- [ ] 50-chef-borrador.png — borrador de presupuesto con cliente y menús (sin número)
- [ ] 51-chef-sin-emitir.png — lo que ve el chef en lugar del botón "Emitir" (solo el gerente emite)

## 5. Pestaña Facturas — como GERENTE
- [ ] 60-documentos-lista.png — lista de documentos (Cargar / Duplicar documento)
- [ ] 61-presupuesto-borrador.png — presupuesto en borrador con IVA (%) y totales
- [ ] 62-emitir.png — botón "Emitir documento" y el mensaje tras emitir (PRE-AAAA-NNNN)
- [ ] 63-documento-emitido.png — documento emitido en solo lectura
- [ ] 64-pdf-presupuesto.png — el PDF descargado abierto
- [ ] 65-factura-emitida.png — factura emitida (FAC-AAAA-NNNN)
- [ ] 66-marcar-cobrado.png — "Marcar como cobrado"
- [ ] 67-rectificativa.png — "Crear rectificativa" y la rectificativa resultante
- [ ] 68-anular-presupuesto.png — "Anular presupuesto"

## 6. Página Gerente
- [ ] 70-nav-gerente.png — selector de página App / Gerente en la barra lateral
- [ ] 71-miembros.png — Miembros e invitaciones → Miembros
- [ ] 72-invitaciones.png — Miembros e invitaciones → Invitaciones (Generar invitación)
- [ ] 73-datos-org.png — Datos de la organización (datos fiscales, IVA por defecto)
- [ ] 74-logo-org.png — subir / guardar / quitar logo
- [ ] 75-inventario-propio.png — Inventario propio: precio propio de un ingrediente
- [ ] 76-ingrediente-privado.png — crear un ingrediente privado con alérgenos y su aviso de revisión
- [ ] 77-compartir-receta.png — Compartir recetas → Compartir una receta
- [ ] 78-comparticiones-activas.png — Compartir recetas → Comparticiones activas

## Notas (pantallas que faltan o son distintas)
-
- Hechas (35): 12-22, 17/17b, 30-34, 40-41, 60, 61, 61a, 62a, 62, 63, 65, 66, 68, 70, 72-75, 77, 78.
- 67 rectificativa: BLOQUEADA por fallo en producción ("Crear rectificativa" da error de session_state). Ver error-rectificativa.png.
- 71 miembros: pendiente del arreglo (el chef aparece como UUID).
- 76 ingrediente privado con alérgenos: BLOQUEADA, el formulario del gerente no permite declarar alérgenos (solo "No contiene ninguno").
- 23 recetas compartidas: la única disponible es "Cupcake sin gluten" de Samirarte, que muestra gluten; no usar. Alternativa: compartir una receta desde Pruebas a Demo.
- 78: la compartición muestra el UUID de la organización destino en vez de su nombre.
- Pendientes de Samira: 17c/17d (subir foto), 22b (Excel), 64 (PDF), bloque chef (10, 11, 50, 51), bloque sin sesión (00, 01, 02).
- Las capturas de facturas (60-68) se hicieron con la página al 80 % para que no se corten los totales.
