# Gestor de Escandallos — guía para Claude Code

App de Samira (Samirarte) para escandallos de recetas, menús, clientes, presupuestos y facturas.
Multiorganización: varias organizaciones (empresas) comparten la app con sus datos aislados.

## Stack y entornos
- App: Streamlit, casi todo en `generador_fichas.py` (+ `calculos_jerarquia.py`, `assets/`). Python 3.11.
- BD: Supabase (Postgres + Auth + RLS). La app usa SOLO la clave publishable; nunca la secreta.
- Producción: VM Oracle con Docker + Caddy → `escandallos.samirarte.com` (servicio `app`).
- Pruebas: `nuevo-escandallos.escandallos.samirarte.com` (servicio `app-pruebas`, clon git en la VM).
- ⚠️ Pruebas y producción comparten la MISMA base de datos.
- Despliegue, BD y DNS los hace Samira a mano. Tú no tienes acceso a la VM ni a Supabase.

## Normas (obligatorias)
1. Cada tarea en una rama nueva desde `main` (o la rama que se indique). Commit + push de ESA rama.
   NUNCA commit, push ni merge a `main`. No despliegues nada.
2. Nunca ejecutes SQL contra la BD. Las migraciones se escriben en `sql/` y Samira las revisa y aplica.
3. No pidas, muestres ni escribas secretos, contraseñas, claves ni cadenas de conexión.
4. Para y pregunta antes de: borrar datos, cambiar permisos, gastar dinero o cualquier cosa irreversible.
5. Alérgenos = seguridad alimentaria. Cualquier cambio que les afecte se señala explícitamente.
6. Al terminar: resumen corto, commits, y lista de decisiones que hayas tomado por tu cuenta.

## Migraciones SQL
- Fichero `sql/NNN_descripcion.sql` + `sql/NNN_rollback.sql` + `sql/NNN_prueba.sql`. Todo en `begin; … commit;`.
- Comprueba la sintaxis antes de entregar (por ejemplo `pip install pglast` y `pglast.parser.parse_sql` +
  `pglast.parse_plpgsql` para los cuerpos de funciones). Ya hubo fallos por `raise` dentro de un `CASE`.
- Funciones: `security definer` + `set search_path = public` + `revoke … from public, anon` + `grant … to authenticated`.
- Toda tabla nueva con RLS y políticas. Sin bypass de admin (ver 023d).
- Pruebas `NNN_prueba.sql`: deben pegarse TAL CUAL en el SQL Editor de Supabase:
  - sin metacomandos psql (`\set`…) y sin huecos `<uid_…>`;
  - tabla temporal `r(prueba, resultado_esperado, obtenido, ok)` y `grant all on r to authenticated, anon`;
  - usuarios de prueba: tomar de `auth.users` y asignar membresías dentro de la transacción;
  - cada caso en un bloque `do $$ … $$` con `set local role authenticated` +
    `perform set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true)`;
    los casos que esperan error, con `begin … exception when others then … end`;
  - `reset role;` fuera de los bloques; al final `select * from r order by prueba; rollback;`.
- Migraciones aplicadas en producción: 022, 023a, 023c, 023d, 024, 024b, 025, 025b, 025c, 026
  (+ versión actualizada de `emitir_documento`). No reapliques ficheros enteros: si cambias una función
  ya aplicada, entrega un fichero aparte solo con el `create or replace` de esa función.

## Modelo multiorganización
- `organizaciones`, `organizacion_miembros(rol in ('gerente','chef'), activo)`.
- Funciones: `es_miembro_org(org)`, `es_gerente_org(org)`. Todas las tablas operativas llevan `organizacion_id NOT NULL`.
- La propiedad es por ORGANIZACIÓN, no por usuario: cualquier miembro de la org activa ve/edita los datos de
  su org (lo garantiza RLS). No añadas comprobaciones por `user_id`.
- Solo el gerente: precios propios (`inventario_org`), ingredientes privados, compartir/copiar recetas,
  emitir documentos, datos de la organización y logo.
- Catálogo global de ingredientes (`inventario` con `organizacion_id is null`): visible para todas las orgs,
  precios incluidos (decisión deliberada; el "bloque G" de 024 NO se aplica).
- Ingredientes privados: código `P-<slug>-NNNN` (`crear_ingrediente_privado`). Alérgenos declarados por la org
  con revisión obligatoria (`alergenos_revisados`).
- `merma` se guarda en PORCENTAJE (0–100), en `inventario` y en `inventario_org`.
- `recetas.codigo_receta` es UNIQUE global: usar siempre `siguiente_codigo_receta()` (RPC).

## Fase 025 (compartir recetas) — en producción
- Compartir con una org concreta o con todas; vista previa sin precios; copia independiente (`copiada_de`).
- Al copiar: precios de la org destino; privados copiados con sus alérgenos y `alergenos_revisados=false`.

## Fase 026 (facturación por organización) — en producción (main)
- Numeración anual por org y tipo: `FAC-AAAA-NNNN`, `REC-AAAA-NNNN`, `PRE-AAAA-NNNN` (`emitir_documento`).
- Borradores sin número; solo el gerente emite. Emitido = inmutable (trigger con lista blanca: solo cambian
  estado, estado_cobro, metodo_pago). Factura emitida no se anula: se corrige con rectificativa
  (`crear_rectificativa`). Presupuesto emitido sí puede anularse. Cobrada/anulada solo por el gerente.
- `organizacion_config`: datos fiscales + logo (bytea, ≤300 KB) por org; editables por el gerente en
  Gerente → Datos de la organización. Al emitir se guarda snapshot de emisor y de cliente en la factura.
- Logo y nombre de la org activa en toda la app. NUNCA el logo, nombre ni datos fiscales de Samirarte para
  otra organización. Excepción: la portada/login (antes de iniciar sesión) usa la marca de la plataforma.
- El PDF de un documento emitido usa tipo, número, líneas y totales GUARDADOS en la BD.

## Trampas conocidas de Streamlit en esta app
- Un `st.success`/`st.error` seguido de `st.rerun()` se pierde: guarda el mensaje en `st.session_state` y
  muéstralo tras el rerun.
- Las `key` de los widgets deben ser únicas: usa el código/UUID completo, nunca recortado (`[:12]`).
- `st.rerun` antes de escribir cookies rompe la escritura (login con Google).
- No cambies la plantilla de correo "Reset Password" de Supabase (la app depende de su formato).

## Pendiente
- Rama `fix-facturas-026`: arreglos de facturas (rectificativa, estados, venta neta por PVP), alérgenos de
  ingredientes privados y emails en Miembros. En pruebas, aún no en producción.
- Manual de usuario (Word + PowerPoint) en `docs/manual/` — ver `docs/manual/INSTRUCCIONES_NUBE.md`.
- Después: revisión completa de alérgenos de ingredientes y recetas; limpieza de datos de prueba.
- Aviso: la facturación no está certificada VERI*FACTU (no usar como sistema fiscal definitivo sin revisión).
