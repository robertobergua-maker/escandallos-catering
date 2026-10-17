-- =============================================================================
-- 023d_admin_solo_por_invitacion.sql
-- Elimina las políticas *_admin_all de las 7 tablas operativas.
-- A partir de aquí los administradores de plataforma solo acceden a los datos
-- de una organización si son miembros de ella (igual que cualquier usuario).
-- =============================================================================
-- ⚠️  CUÁNDO EJECUTAR:
--   OBLIGATORIO antes de dar de alta la primera organización EXTERNA a Samirarte
--   (es decir, antes de invitar a usuarios de otra cocina/empresa).
--   Si se ejecuta después, los admins ya habrán podido ver datos ajenos.
--
--   Orden recomendado:
--     1. Ejecutar este script.
--     2. Verificar que es_admin_app() sigue funcionando para el panel de
--        administración de plataforma (organizaciones, usuarios_app). Esas
--        tablas tienen sus propias políticas independientes.
--     3. El admin que necesite gestionar datos de una organización debe ser
--        invitado a ella como 'gerente' con crear_invitacion().
--
-- Qué hace:
--   Elimina los 7 pares de políticas *_admin_all (una por tabla operativa)
--   que dan acceso total a quien tenga es_admin_app() = true.
--   Las políticas *_org (por es_miembro_org) permanecen intactas.
--
-- Qué NO cambia:
--   • Las funciones es_admin_app(), es_miembro_org(), es_gerente_org().
--   • Las políticas de organizaciones, organizacion_miembros, usuarios_app,
--     invitaciones, inventario, alergenos, ingrediente_alergenos.
--   • El panel de administración de plataforma (crea/desactiva orgs, gestiona
--     usuarios_app): esas tablas tienen sus propias políticas.
--
-- Reversible: ejecutar 023d_rollback.sql.
-- NO ejecutar automáticamente. Revisar y aplicar manualmente en Supabase.
-- =============================================================================

begin;

drop policy if exists recetas_admin_all              on public.recetas;
drop policy if exists receta_ingredientes_admin_all  on public.receta_ingredientes;
drop policy if exists menus_admin_all                on public.menus;
drop policy if exists menu_recetas_admin_all         on public.menu_recetas;
drop policy if exists clientes_admin_all             on public.clientes;
drop policy if exists facturas_admin_all             on public.facturas;
drop policy if exists factura_lineas_admin_all       on public.factura_lineas;

-- Verificación: ninguna política *_admin_all debe quedar en las 7 tablas.
select count(*) as admin_all_restantes
from pg_policies
where schemaname = 'public'
  and tablename in (
    'recetas','receta_ingredientes','menus','menu_recetas',
    'clientes','facturas','factura_lineas'
  )
  and policyname like '%_admin_all';
-- Debe devolver 0.

commit;
