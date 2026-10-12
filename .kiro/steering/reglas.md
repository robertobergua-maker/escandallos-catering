# Reglas del proyecto Gestor de Escandallos
- Producción: VM Oracle (Docker + Caddy), BD Supabase (proyecto zpwgbebolrkzxsxuucog).
- Trabaja siempre en una rama nueva (multiorganizacion). Nunca commit ni push a main.
- Nunca cambies la base de datos: prepara las migraciones SQL en sql/ y yo las reviso y ejecuto.
- Toda tabla nueva lleva RLS y políticas; la app usa la clave publishable, nunca la secreta.
- No pidas, muestres ni escribas secretos o contraseñas.
- Para y pregunta antes de: desplegar en la VM, tocar DNS, borrar datos, gastar dinero,
  cambiar permisos o abrir puertos.
- Los datos de alérgenos son de seguridad alimentaria: cualquier cambio que les afecte se
  señala explícitamente.