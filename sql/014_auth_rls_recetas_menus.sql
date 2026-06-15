-- 014_auth_rls_recetas_menus.sql
-- Preparacion base para seguridad por usuario con Supabase Auth.
--
-- IMPORTANTE:
-- - Este script no migra automaticamente recetas o menus antiguos.
-- - Las recetas y menus antiguos con user_id null dejaran de verse cuando se
--   activen politicas RLS que filtren por auth.uid().
-- - El inventario no se modifica y seguira siendo comun.
-- - Revisar y probar en un entorno seguro antes de ejecutar en Supabase.

alter table public.recetas
add column if not exists user_id uuid references auth.users(id) on delete set null;

alter table public.menus
add column if not exists user_id uuid references auth.users(id) on delete set null;

alter table public.recetas enable row level security;
alter table public.receta_ingredientes enable row level security;
alter table public.menus enable row level security;
alter table public.menu_recetas enable row level security;

-- No se crean politicas en este paso.
-- La siguiente fase debera definir politicas de select/insert/update/delete
-- para recetas y menus usando auth.uid(), y decidir como tratar los registros
-- historicos con user_id null.
