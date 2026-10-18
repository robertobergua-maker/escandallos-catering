# Diseño técnico: Evolución a multiorganización
## Gestor de Escandallos — rama `multiorganizacion`

> Documento vivo. Actualizar a medida que cada fase se valida en producción.

---

## 1. Estado actual (base de partida)

| Tabla | Aislamiento actual |
|---|---|
| `inventario` | Compartida; cualquier usuario autenticado lee y escribe |
| `alergenos`, `ingrediente_alergenos` | Compartidas; solo admin escribe |
| `recetas`, `receta_ingredientes` | Por `user_id = auth.uid()` |
| `menus`, `menu_recetas` | Por `user_id = auth.uid()` |
| `clientes`, `facturas`, `factura_lineas` | Por `user_id = auth.uid()` |
| `presupuestos`, `presupuesto_menus`, `factura_menus` | Por `user_id = auth.uid()` |
| `usuarios_app` | Perfil interno; rol `usuario` o `admin` |

El único concepto de "administrador" es `usuarios_app.rol = 'admin'` + la función
`es_admin_app()`. No existe ningún concepto de organización.

---

## 2. Modelo de datos objetivo

### 2.1 Nuevas tablas de infraestructura

```
organizaciones
  id uuid PK
  nombre text
  slug text UNIQUE            -- para URLs limpias
  activa boolean
  created_at / updated_at

organizacion_miembros
  id uuid PK
  organizacion_id uuid FK→organizaciones
  user_id uuid FK→auth.users
  rol text CHECK ('gerente','chef')
  activo boolean
  invited_at / joined_at
  UNIQUE(organizacion_id, user_id)

invitaciones
  id uuid PK
  organizacion_id uuid FK→organizaciones
  email text
  rol text
  codigo text UNIQUE          -- token opaco, 32 chars
  creado_por uuid FK→auth.users
  canjeada boolean
  expires_at timestamptz
  created_at
```

### 2.2 Columna `organizacion_id` en tablas operativas

Se añade `organizacion_id uuid NOT NULL FK→organizaciones` (con ON DELETE RESTRICT)
a todas las tablas que hoy se aíslan por `user_id`:

`inventario_precios` (nueva), `recetas`, `menus`, `clientes`, `facturas`,
`factura_lineas`, `presupuestos`, `presupuesto_menus`, `factura_menus`.

`user_id` **se mantiene** en todas ellas: sigue indicando quién creó la fila
y es útil para auditoría.

### 2.3 Separación catálogo global / precios por organización (Fase 3)

```
inventario           → catálogo global (solo admin de plataforma escribe)
inventario_org       → tabla nueva
  id uuid PK
  organizacion_id uuid FK→organizaciones
  codigo_ingrediente text FK→inventario(codigo)
  precio_unidad numeric
  merma numeric
  proveedor_precio text
  formato_compra text
  cantidad_formato_compra numeric
  unidad_formato_compra text
  precio_formato_compra numeric
  url_precio text
  observaciones_precio text
  updated_at
  UNIQUE(organizacion_id, codigo_ingrediente)
```

Los ingredientes privados de una organización (que no existen en el catálogo global)
se registran en `inventario` con una FK a `organizacion_id` en `inventario`
(columna nullable que, siendo NULL, indica catálogo global).

### 2.4 Comparticiones (Fase 4)

```
comparticiones
  id uuid PK
  origen_organizacion_id uuid FK→organizaciones  (NULL = admin de plataforma)
  tipo text CHECK ('receta','menu')
  objeto_id uuid             -- receta.id o menu.id
  destino text CHECK ('todas','especifica')
  destino_organizacion_id uuid nullable FK→organizaciones
  activa boolean
  created_by uuid FK→auth.users
  created_at
  UNIQUE(tipo, objeto_id, destino, destino_organizacion_id)
```

La copia genera una fila nueva en `recetas` / `menus` con:
- `copiada_de uuid nullable FK→recetas/menus` (traza de origen)
- `organizacion_id` = organización que copia
- Los ingredientes se recalculan con `inventario_org` de la organización destino

### 2.5 Facturación por organización (Fase 5)

```
organizacion_config
  organizacion_id uuid PK FK→organizaciones
  razon_social text
  nif_cif text
  direccion_fiscal text
  logo_url text               -- ruta pública en Supabase Storage
  serie_factura text          -- p.ej. "SMR"
  siguiente_numero_factura integer
  tipo_iva_defecto numeric
  notas_pie_factura text
  updated_at
```

---

## 3. Roles y funciones SQL

| Función | Semántica |
|---|---|
| `es_admin_app(uid)` | Ya existe. Pasa a ser "admin de plataforma" |
| `es_miembro_org(org_id, uid)` | True si hay fila activa en `organizacion_miembros` |
| `es_gerente_org(org_id, uid)` | True si es miembro con `rol='gerente'` |
| `org_activa(uid)` | Devuelve el `organizacion_id` activo de la sesión (ver §4) |

### Jerarquía de permisos

```
Admin de plataforma (es_admin_app)
  └── puede todo en cualquier organización
      └── Gerente (es_gerente_org)
              └── puede todo en su organización (datos + usuarios + comparticiones)
                  └── Chef (es_miembro_org y rol='chef')
                          └── puede CRUD datos de su organización
```

---

## 4. Organización activa en sesión

Supabase no tiene "contexto de organización" nativo. La estrategia es:

1. Al hacer login, la app lee las organizaciones del usuario desde `organizacion_miembros`.
2. Si solo pertenece a una, se selecciona automáticamente.
3. Si pertenece a varias, se muestra un selector en la barra lateral.
4. La elección se guarda en `st.session_state["organizacion_activa_id"]`.
5. **Todas** las consultas incluyen `.eq("organizacion_id", org_activa)`.
6. Las políticas RLS también filtran por `organizacion_id` vía función SQL
   `es_miembro_org(organizacion_id, auth.uid())`, lo que garantiza aislamiento
   aunque la app pase el filtro incorrecto por error.

---

## 5. Flujo de invitaciones (sin clave secreta)

```
Gerente crea invitación
  → INSERT invitaciones(org_id, email, rol, codigo=gen_random_uuid()::text, expires_at=now()+7d)
  → La app muestra el enlace: https://escandallos.samirarte.com/?invitacion=<codigo>

Chef recibe enlace, se registra o inicia sesión
  → La app lee invitaciones WHERE codigo=? AND NOT canjeada AND expires_at > now()
  → Si ok: INSERT organizacion_miembros(org_id, user_id, rol)
            UPDATE invitaciones SET canjeada=true
```

No se necesita Edge Function: la política RLS de `invitaciones` permite que
`anon` lea por código (solo las columnas necesarias para validar), y que
`authenticated` inserte la fila de membresía propia.

---

## 6. Política de alérgenos en la migración

> ⚠️ **Seguridad alimentaria**: los alérgenos están en el catálogo global y viajan
> siempre con cualquier copia de receta o menú. No se pueden sobreescribir
> por organización. La tabla `alergenos` y `ingrediente_alergenos` permanecen
> globales y de solo lectura para todos salvo el admin de plataforma.
>
> Al copiar una receta entre organizaciones, los `ingrediente_alergenos`
> del catálogo global se replican automáticamente en la copia consultando
> el catálogo (no se copian las filas, se leen dinámicamente desde el catálogo).
>
> Los ingredientes privados de una organización llevan su propio registro
> en `ingrediente_alergenos` con las mismas restricciones de RLS.

---

## 7. Plan de migración de datos existentes

### Fase 1 (sin tocar app)

```sql
-- 1. Crear org "Samirarte"
INSERT INTO organizaciones(nombre, slug) VALUES ('Samirarte', 'samirarte');

-- 2. Meter a todos los usuarios actuales como miembros
INSERT INTO organizacion_miembros(organizacion_id, user_id, rol)
SELECT (SELECT id FROM organizaciones WHERE slug='samirarte'),
       user_id,
       CASE WHEN rol='admin' THEN 'gerente' ELSE 'chef' END
FROM usuarios_app WHERE activo=true;
-- Los admin de plataforma mantienen su fila en usuarios_app con rol='admin'
```

### Fase 2 (transición con columna nullable primero)

```
a) ADD COLUMN organizacion_id uuid nullable FK→organizaciones
b) UPDATE SET organizacion_id = id_samirarte WHERE organizacion_id IS NULL
c) ALTER COLUMN organizacion_id SET NOT NULL
d) Desplegar nueva versión de la app que envía organizacion_id
e) Reemplazar políticas RLS viejas (user_id) por nuevas (es_miembro_org)
```

Durante el paso b→d la app vieja sigue funcionando porque las políticas
viejas (por `user_id`) coexisten con las nuevas hasta el despliegue.

---

## 8. Consideraciones de rendimiento (plan gratuito Supabase)

- Índice `(organizacion_id)` en todas las tablas operativas (obligatorio para RLS eficiente).
- Índice compuesto `(organizacion_id, activa)` en recetas.
- Índice `(organizacion_id, user_id)` en `organizacion_miembros` (la función `es_miembro_org` lo usa en cada evaluación RLS).
- Las funciones de rol son `STABLE SECURITY DEFINER` con `search_path = public` para que PostgreSQL pueda cachearlas por transacción.
- Evitar `SELECT *` en tablas grandes; la app ya usa selects con columnas explícitas.

---

## 9. Tests de RLS por fase

Antes de desplegar cada fase, ejecutar en Supabase SQL Editor con `SET LOCAL ROLE authenticated; SET LOCAL "request.jwt.claims" TO '{"sub":"<uid_org_B>"}'`:

```sql
-- Debe devolver 0 filas
SELECT * FROM recetas WHERE organizacion_id = '<id_org_A>';
-- Debe devolver error de política
INSERT INTO recetas(organizacion_id, ...) VALUES ('<id_org_A>', ...);
```

Los scripts de test de RLS se incluirán como comentarios al final de cada
migración correspondiente.

---

## 10. Ficheros SQL a generar

| Fichero | Fase | Descripción |
|---|---|---|
| `sql/022_fase1_organizaciones_miembros.sql` | 1 | Tablas org + miembros + funciones de rol + datos Samirarte |
| `sql/023_fase2_organizacion_id_rls.sql` | 2 | `organizacion_id` en tablas + RLS nueva + invitaciones |
| `sql/024_fase3_catalogo_global_precios_org.sql` | 3 | `inventario_org` + separar catálogo |
| `sql/025_fase4_comparticiones_copia.sql` | 4 | Comparticiones + columna `copiada_de` |
| `sql/023a_fase2_columnas_nullable_backfill.sql` | 2A | Columnas nullable + backfill Samirarte + invitaciones |
| `sql/023c_fase2_not_null_rls.sql` | 2C | NOT NULL + swap de políticas RLS |
| `sql/023c_rollback.sql` | 2C | Rollback del paso C |
| `sql/023d_admin_solo_por_invitacion.sql` | 2D | ⚠️ OBLIGATORIO antes de primera org externa |
| `sql/023d_rollback.sql` | 2D | Rollback de 023d |
| `sql/024_fase3_catalogo_global_precios_org.sql` | 3 | `inventario_org` + separar catálogo |
| `sql/025_fase4_comparticiones_copia.sql` | 4 | Comparticiones + columna `copiada_de` |
| `sql/026_fase5_facturacion_por_org.sql` | 5 | `organizacion_config` + numeración propia |

---

## 11. Cambios en la app Streamlit por fase

### Fase 1 — Sin cambios visibles
La app sigue funcionando idéntica. Internamente `asegurar_usuario_app_supabase()`
podría empezar a rellenar `organizacion_miembros` pero no es obligatorio en F1.

### Fase 2 — Selector de organización
- Nuevo componente en sidebar: `seleccionar_organizacion()`.
- Todas las funciones de carga añaden `.eq("organizacion_id", org_activa)`.
- Nueva pantalla "Gerente": gestión de miembros e invitaciones.
- Nueva pantalla "Administrador": gestión de organizaciones.

> ⚠️ **Paso 023d — OBLIGATORIO antes de dar de alta la primera organización externa**
>
> Las políticas `*_admin_all` de la Fase 2C dan acceso total a los admins de plataforma
> sobre todas las tablas operativas. Esto es aceptable mientras solo existe Samirarte,
> pero **antes de invitar a usuarios de cualquier otra organización** hay que ejecutar
> `sql/023d_admin_solo_por_invitacion.sql` para que los admins solo accedan a los datos
> de las organizaciones de las que sean miembros (igual que cualquier usuario).
>
> Si se ejecuta después de dar acceso a una org externa, los admins ya habrán podido
> ver sus datos. El script tiene su propio rollback (`023d_rollback.sql`).
>
> La pantalla de administración de plataforma mostrará un aviso al crear cualquier
> organización que no sea Samirarte.

### Fase 3 — Precios propios
- La pantalla de inventario muestra el catálogo global en solo lectura.
- Una pestaña "Mis precios" carga/guarda `inventario_org`.
- El cálculo de recetas resuelve precio: `inventario_org` → fallback `inventario`.

> ⚠️ **Decisiones OBLIGATORIAS antes de la primera organización externa (Fase 3)**
>
> **(a) Bloque G — precios del catálogo global**: ~~vaciar precios antes de la primera org externa~~
> **DECISIÓN TOMADA (2026-10-18): el bloque G NO se aplica.**
> Los precios del catálogo global (`inventario` con `organizacion_id IS NULL`) permanecen
> visibles para todas las organizaciones. Es una decisión deliberada: el catálogo compartido
> incluye los precios de referencia de Samirarte, accesibles a cualquier org como punto de
> partida antes de definir sus propios precios en `inventario_org`.
> El bloque G de `sql/024` queda comentado como referencia histórica únicamente.
>
> **(b) SMTP propio**: configurar en Supabase → Authentication → SMTP Settings el servidor
> de correo propio antes de que usuarios de otras organizaciones reciban invitaciones.
> El SMTP gratuito de Supabase tiene límites bajos y el dominio remitente no es el del proyecto.

### Fase 4 — Compartir

> ⚠️ **Ingredientes privados en recetas compartidas**
>
> Si una receta de la org A contiene ingredientes privados (código `P-<slug>-NNNN`),
> al copiarla a la org B mediante `copiar_receta_a_org` (sql/025) **no se pueden perder
> los alérgenos**. Las opciones son:
>
> 1. **Bloquear la copia** si la receta contiene privados de la org origen que no existen
>    en el catálogo global ni en la org destino.
> 2. **Copiar también el ingrediente privado** a la org destino con sus alérgenos, marcando
>    `alergenos_revisados = true` (ya que vienen declarados de origen).
>
> La opción 2 es preferible para no bloquear comparticiones válidas. La función
> `copiar_receta_a_org` del 025 debe detectar privados y copiarlos antes de copiar la receta.
> Esto requiere que el gerente destino tenga permiso para crear privados (lo tiene).
> Ver `sql/025_fase4_comparticiones_copia.sql` para implementar este comportamiento.

- Botón "Compartir" en receta/menú propio (solo gerente).
- Sección "Recetas y menús compartidos conmigo" en modo lectura.
- Botón "Copiar a mi organización".

### Fase 5 — Facturación
- Pantalla de configuración de facturación por organización.
- PDF generado con logotipo y datos fiscales propios de la organización.
