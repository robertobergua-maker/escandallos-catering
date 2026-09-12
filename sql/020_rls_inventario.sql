-- 020_rls_inventario.sql
-- Activa RLS en inventario (tabla comun). Usuarios autenticados pueden leer
-- y anadir articulos nuevos, igual que ya exige la interfaz. El modo
-- invitado (sin cuenta) tambien puede leer el inventario para poder probar
-- la app con datos reales, pero no puede escribir: la app bloquea el
-- guardado de recetas/menus/clientes/facturas en modo invitado antes de
-- llegar aqui, y estas politicas no dan a "anon" ningun permiso de
-- escritura.
--
-- Antes de esta migracion la tabla no tenia RLS activado: cualquiera con la
-- clave anon podia leer y modificar el inventario sin iniciar sesion.
--
-- Requiere haber ejecutado antes sql/018_admin_rls_todas_bbdd.sql (define la
-- politica inventario_admin_all y la funcion public.es_admin_app, que sigue
-- dando a los admin acceso completo de lectura/escritura/borrado).

alter table public.inventario enable row level security;

drop policy if exists inventario_select_authenticated on public.inventario;
create policy inventario_select_authenticated
on public.inventario
for select
to authenticated
using (true);

drop policy if exists inventario_select_invitado on public.inventario;
create policy inventario_select_invitado
on public.inventario
for select
to anon
using (true);

drop policy if exists inventario_insert_authenticated on public.inventario;
create policy inventario_insert_authenticated
on public.inventario
for insert
to authenticated
with check (true);
