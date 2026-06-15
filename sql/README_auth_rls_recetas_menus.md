# RLS de usuarios para recetas y menus

El archivo `sql/014_auth_rls_recetas_menus.sql` prepara la seguridad por
usuario para recetas y menus usando Supabase Auth. Anade la columna `user_id`
en las tablas principales y define politicas RLS para que cada usuario
autenticado trabaje solo con sus propios datos.

## Tablas con RLS

El SQL activa Row Level Security en:

- `recetas`
- `receta_ingredientes`
- `menus`
- `menu_recetas`

Con estas politicas, cada usuario autenticado solo podra ver y modificar:

- sus recetas;
- los ingredientes de sus recetas;
- sus menus;
- las lineas de sus menus.

`receta_ingredientes` no tiene `user_id` propio porque hereda los permisos
desde `recetas` mediante `receta_id`.

`menu_recetas` no tiene `user_id` propio porque hereda los permisos desde
`menus` mediante `menu_id`.

Los registros antiguos con `user_id null` dejaran de verse cuando se active
RLS estricto, porque las politicas comparan `user_id` con `auth.uid()`.

Antes de ejecutar este SQL en Supabase conviene hacer backup o revisar bien el
estado de los datos existentes.

## Comprobar RLS

```sql
select schemaname, tablename, rowsecurity
from pg_tables
where schemaname = 'public'
  and tablename in ('recetas', 'receta_ingredientes', 'menus', 'menu_recetas');
```

## Ver politicas

```sql
select schemaname, tablename, policyname, cmd
from pg_policies
where schemaname = 'public'
  and tablename in ('recetas', 'receta_ingredientes', 'menus', 'menu_recetas')
order by tablename, policyname;
```

## Orden recomendado

1. Revisar SQL.
2. Hacer backup.
3. Ejecutar SQL en Supabase.
4. Comprobar RLS.
5. Adaptar app para login.
6. Guardar recetas y menus con `user_id`.
