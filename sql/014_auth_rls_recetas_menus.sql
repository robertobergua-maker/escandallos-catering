-- 014_auth_rls_recetas_menus.sql
-- Preparacion base para seguridad por usuario con autenticacion del inventario.
--
-- IMPORTANTE:
-- - Este script no migra automaticamente recetas o menus antiguos.
-- - Las recetas y menus antiguos con user_id null dejaran de verse cuando se
--   activen politicas RLS que filtren por auth.uid().
-- - El inventario no se modifica y seguira siendo comun.
-- - Revisar y probar en un entorno seguro antes de ejecutar en el inventario real.

alter table public.recetas
add column if not exists user_id uuid references auth.users(id) on delete set null;

alter table public.menus
add column if not exists user_id uuid references auth.users(id) on delete set null;

alter table public.recetas enable row level security;
alter table public.receta_ingredientes enable row level security;
alter table public.menus enable row level security;
alter table public.menu_recetas enable row level security;

-- Politicas de recetas: cada usuario autenticado solo puede operar sobre sus
-- propias recetas.
drop policy if exists "recetas_select_propias" on public.recetas;
create policy "recetas_select_propias"
on public.recetas
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "recetas_insert_propias" on public.recetas;
create policy "recetas_insert_propias"
on public.recetas
for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "recetas_update_propias" on public.recetas;
create policy "recetas_update_propias"
on public.recetas
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "recetas_delete_propias" on public.recetas;
create policy "recetas_delete_propias"
on public.recetas
for delete
to authenticated
using (user_id = auth.uid());

-- receta_ingredientes no lleva user_id propio: hereda la seguridad desde la
-- receta propietaria mediante receta_id.
drop policy if exists "receta_ingredientes_select_por_receta_propia" on public.receta_ingredientes;
create policy "receta_ingredientes_select_por_receta_propia"
on public.receta_ingredientes
for select
to authenticated
using (
  exists (
    select 1
    from public.recetas
    where public.recetas.id = receta_ingredientes.receta_id
      and public.recetas.user_id = auth.uid()
  )
);

drop policy if exists "receta_ingredientes_insert_por_receta_propia" on public.receta_ingredientes;
create policy "receta_ingredientes_insert_por_receta_propia"
on public.receta_ingredientes
for insert
to authenticated
with check (
  exists (
    select 1
    from public.recetas
    where public.recetas.id = receta_ingredientes.receta_id
      and public.recetas.user_id = auth.uid()
  )
);

drop policy if exists "receta_ingredientes_update_por_receta_propia" on public.receta_ingredientes;
create policy "receta_ingredientes_update_por_receta_propia"
on public.receta_ingredientes
for update
to authenticated
using (
  exists (
    select 1
    from public.recetas
    where public.recetas.id = receta_ingredientes.receta_id
      and public.recetas.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.recetas
    where public.recetas.id = receta_ingredientes.receta_id
      and public.recetas.user_id = auth.uid()
  )
);

drop policy if exists "receta_ingredientes_delete_por_receta_propia" on public.receta_ingredientes;
create policy "receta_ingredientes_delete_por_receta_propia"
on public.receta_ingredientes
for delete
to authenticated
using (
  exists (
    select 1
    from public.recetas
    where public.recetas.id = receta_ingredientes.receta_id
      and public.recetas.user_id = auth.uid()
  )
);

-- Politicas de menus: cada usuario autenticado solo puede operar sobre sus
-- propios menus.
drop policy if exists "menus_select_propios" on public.menus;
create policy "menus_select_propios"
on public.menus
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "menus_insert_propios" on public.menus;
create policy "menus_insert_propios"
on public.menus
for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "menus_update_propios" on public.menus;
create policy "menus_update_propios"
on public.menus
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "menus_delete_propios" on public.menus;
create policy "menus_delete_propios"
on public.menus
for delete
to authenticated
using (user_id = auth.uid());

-- menu_recetas no lleva user_id propio: hereda la seguridad desde el menu
-- propietario mediante menu_id.
drop policy if exists "menu_recetas_select_por_menu_propio" on public.menu_recetas;
create policy "menu_recetas_select_por_menu_propio"
on public.menu_recetas
for select
to authenticated
using (
  exists (
    select 1
    from public.menus
    where public.menus.id = menu_recetas.menu_id
      and public.menus.user_id = auth.uid()
  )
);

drop policy if exists "menu_recetas_insert_por_menu_propio" on public.menu_recetas;
create policy "menu_recetas_insert_por_menu_propio"
on public.menu_recetas
for insert
to authenticated
with check (
  exists (
    select 1
    from public.menus
    where public.menus.id = menu_recetas.menu_id
      and public.menus.user_id = auth.uid()
  )
);

drop policy if exists "menu_recetas_update_por_menu_propio" on public.menu_recetas;
create policy "menu_recetas_update_por_menu_propio"
on public.menu_recetas
for update
to authenticated
using (
  exists (
    select 1
    from public.menus
    where public.menus.id = menu_recetas.menu_id
      and public.menus.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.menus
    where public.menus.id = menu_recetas.menu_id
      and public.menus.user_id = auth.uid()
  )
);

drop policy if exists "menu_recetas_delete_por_menu_propio" on public.menu_recetas;
create policy "menu_recetas_delete_por_menu_propio"
on public.menu_recetas
for delete
to authenticated
using (
  exists (
    select 1
    from public.menus
    where public.menus.id = menu_recetas.menu_id
      and public.menus.user_id = auth.uid()
  )
);
