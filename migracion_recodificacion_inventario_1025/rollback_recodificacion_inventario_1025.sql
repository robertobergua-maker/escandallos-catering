-- Rollback manual desde backups creados por la migración.
-- Úsalo solo si necesitas volver al estado anterior y entiendes que reemplaza las tablas actuales.

begin;

truncate table public.receta_ingredientes;
insert into public.receta_ingredientes
select * from public.receta_ingredientes_backup_antes_recodificacion_1025;

truncate table public.inventario;
insert into public.inventario
select * from public.inventario_backup_antes_recodificacion_1025;

commit;
