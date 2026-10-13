-- 021_rls_alergenos.sql
-- Políticas RLS para el catálogo de alérgenos y su relación con ingredientes.
--
-- Situación previa: public.alergenos y public.ingrediente_alergenos tienen
-- RLS activado pero ninguna política, así que con la clave publishable
-- (anon/authenticated) cualquier lectura devuelve 0 filas y las recetas salen
-- "Sin alérgenos declarados". Hasta ahora no se notaba porque producción usaba
-- la clave secreta, que se salta RLS.
--
-- Criterio:
--   - Lectura: usuarios autenticados y modo invitado (datos comunes, como
--     el inventario en sql/020).
--   - Escritura: solo administradores, mediante public.es_admin_app()
--     (sql/017_usuarios_app_entorno.sql), salvo añadir alérgenos a un
--     ingrediente, que también pueden hacer los usuarios autenticados.
--
-- Requiere: sql/017_usuarios_app_entorno.sql (función es_admin_app).
-- Es idempotente: se puede ejecutar más de una vez.

begin;

alter table public.alergenos enable row level security;
alter table public.ingrediente_alergenos enable row level security;

-- ---------------------------------------------------------------------------
-- public.alergenos
-- ---------------------------------------------------------------------------
drop policy if exists alergenos_select_authenticated on public.alergenos;
create policy alergenos_select_authenticated
on public.alergenos
for select
to authenticated
using (true);

drop policy if exists alergenos_admin_all on public.alergenos;
create policy alergenos_admin_all
on public.alergenos
for all
to authenticated
using (public.es_admin_app(auth.uid()))
with check (public.es_admin_app(auth.uid()));

-- ---------------------------------------------------------------------------
-- public.ingrediente_alergenos
-- ---------------------------------------------------------------------------
drop policy if exists ingrediente_alergenos_select_authenticated on public.ingrediente_alergenos;
create policy ingrediente_alergenos_select_authenticated
on public.ingrediente_alergenos
for select
to authenticated
using (true);

drop policy if exists ingrediente_alergenos_admin_all on public.ingrediente_alergenos;
create policy ingrediente_alergenos_admin_all
on public.ingrediente_alergenos
for all
to authenticated
using (public.es_admin_app(auth.uid()))
with check (public.es_admin_app(auth.uid()));

-- ---------------------------------------------------------------------------
-- A) Lectura también en modo invitado (anon), igual que
-- inventario_select_invitado en sql/020, para que el modo invitado muestre
-- los alérgenos de las recetas.
-- ---------------------------------------------------------------------------
drop policy if exists alergenos_select_invitado on public.alergenos;
create policy alergenos_select_invitado
on public.alergenos
for select
to anon
using (true);

drop policy if exists ingrediente_alergenos_select_invitado on public.ingrediente_alergenos;
create policy ingrediente_alergenos_select_invitado
on public.ingrediente_alergenos
for select
to anon
using (true);

-- ---------------------------------------------------------------------------
-- B) Usuarios autenticados no admin pueden declarar alérgenos al dar de alta
-- un ingrediente: sql/020 les deja insertar en inventario y la app guarda los
-- alérgenos a la vez (guardar_alergenos_ingrediente). Solo permite añadir;
-- borrar o cambiar alérgenos existentes sigue siendo solo de admin.
-- ---------------------------------------------------------------------------
drop policy if exists ingrediente_alergenos_insert_authenticated on public.ingrediente_alergenos;
create policy ingrediente_alergenos_insert_authenticated
on public.ingrediente_alergenos
for insert
to authenticated
with check (true);

commit;

-- Comprobación (solo lectura):
-- select tablename, policyname, roles, cmd
-- from pg_policies
-- where schemaname = 'public' and tablename in ('alergenos', 'ingrediente_alergenos')
-- order by 1, 2;
