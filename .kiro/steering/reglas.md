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
- ⚠️ ANTES de dar de alta la primera organización externa (que no sea Samirarte),
  ejecutar sql/023d_admin_solo_por_invitacion.sql para retirar el acceso total de los
  admins de plataforma a los datos de otras organizaciones.
  Ver docs/multiorganizacion_diseno_tecnico.md §11 Fase 2.
- ⚠️ ANTES de dar de alta la primera organización externa, también hay que:
  (a) ~~DECIDIR Y APLICAR el bloque G de sql/024~~ **DECISIÓN TOMADA (2026-10-18): el bloque G
      NO se aplica.** Los precios del catálogo global (inventario con organizacion_id null)
      permanecen visibles para todas las organizaciones. Es una decisión deliberada de Samira.
  (b) CONFIGURAR SMTP PROPIO en Supabase (Authentication → SMTP Settings) para que los
      correos de recuperación de contraseña e invitación lleguen con el dominio correcto
      y no fallen por límites del SMTP gratuito de Supabase.
- ⚠️ Fase 4 (compartir recetas): al copiar una receta que contiene ingredientes privados
  de la org origen a otra organización, NO se puede perder información de alérgenos.
  Ver nota en docs/multiorganizacion_diseno_tecnico.md §11 Fase 4.