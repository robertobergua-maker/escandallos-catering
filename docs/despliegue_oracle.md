# Despliegue sin paradas por inactividad

## Arquitectura

```
Usuario ──► escandallos.samirarte.com
              │  DNS en Hostalia: registro A → IP pública de la VM
              ▼
        VM Oracle Cloud Always Free (siempre encendida)
          ├─ caddy             (HTTPS automático con Let's Encrypt, puertos 80/443)
          ├─ app               (Streamlit en Docker)
          └─ supabase-keepalive (ping cada 6 h)
              │
              ▼
        Supabase (Postgres + Auth + RLS)
```

- **Front**: una VM ARM Ampere A1 de Oracle Cloud *Always Free* (hasta 4 OCPU y 24 GB de RAM, sin caducidad). No se duerme: el contenedor corre 24/7 y Docker lo reinicia si cae o si la VM se reinicia.
- **BBDD**: se mantiene Supabase (Auth y RLS siguen igual, sin cambios en el código). El contenedor `supabase-keepalive` evita la pausa del plan Free por 7 días de inactividad. Sustituye al workflow de GitHub Actions.
- **Dominio**: el subdominio sigue gestionado en Hostalia, pero deja de ser una redirección a `escandallos.streamlit.app` y pasa a apuntar a la VM. Caddy obtiene y renueva el certificado HTTPS solo. El dominio no se mueve a Cloudflare, así que el correo y la web de `samirarte.com` no se tocan.

## 1. Crear la VM en Oracle Cloud

1. Crear cuenta en https://cloud.oracle.com (pide tarjeta para verificar, no cobra).
2. **Recomendado**: pasar la cuenta a *Pay As You Go*. Sigue siendo gratis mientras no se superen los límites Always Free, y evita que Oracle recupere instancias gratuitas que considere inactivas. Poner una alerta de presupuesto de 1 € en *Billing → Budgets*.
3. *Compute → Instances → Create instance*:
   - Image: **Ubuntu 24.04** (aarch64)
   - Shape: **VM.Standard.A1.Flex**, con 2 OCPU y 12 GB (o 4/24).
   - Añadir tu clave SSH pública.
   - Si sale *Out of capacity*, reintentar más tarde o probar con otro Availability Domain.
4. Anotar la **IP pública** de la instancia. Se mantiene aunque la VM se pare o reinicie, y solo se pierde si se elimina la instancia.
5. Abrir los puertos 80 y 443 en la red de Oracle: *Instance → Subnet → Security List → Add Ingress Rules*, con origen `0.0.0.0/0`, protocolo TCP y puertos `80,443`.

## 2. Preparar la VM

```bash
ssh ubuntu@<IP_PUBLICA>
sudo apt update && sudo apt -y upgrade
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker ubuntu && exit   # volver a entrar por SSH
sudo apt -y install unattended-upgrades  # parches de seguridad automáticos
git clone <URL_DEL_REPO> escandallos
```

Las imágenes Ubuntu de Oracle traen un cortafuegos (iptables) que bloquea todo salvo SSH. Hay que abrir también 80 y 443 dentro de la VM:

```bash
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
sudo netfilter-persistent save
```

## 3. Apuntar el subdominio en Hostalia

1. En el panel de Hostalia, quitar la configuración actual de `escandallos.samirarte.com` como subdominio de hosting (la redirección de `redirect-hostalia/`).
2. En la *zona DNS* de `samirarte.com`, crear un registro **A** con nombre `escandallos` y valor igual a la IP pública de la VM. Si Hostalia no deja crear el registro porque ya existe, editar el que haya o borrar antes el subdominio.
3. Comprobar la propagación (puede tardar de minutos a unas horas) con `nslookup escandallos.samirarte.com`, que debe devolver la IP de la VM.

Hasta que el DNS no apunte a la VM, Caddy no podrá obtener el certificado. Conviene hacer este paso antes de arrancar.

## 4. Secretos y arranque

```bash
cd ~/escandallos/deploy
cp .env.example .env && nano .env   # APP_DOMAIN + SUPABASE_URL/KEY
nano secrets.toml                   # mismo contenido que en Streamlit Cloud
docker compose up -d --build
docker compose ps
docker compose logs -f caddy app   # Caddy debe indicar "certificate obtained successfully"
```

`secrets.toml` debe incluir `PASSWORD_RECOVERY_REDIRECT_URL = "https://escandallos.samirarte.com"`. Esa URL también debe estar en Supabase → *Authentication → URL Configuration* (Site URL y Redirect URLs).

## 5. Actualizar la app

```bash
cd ~/escandallos && git pull && cd deploy && docker compose up -d --build
```

## 6. Retirar lo antiguo (cuando todo funcione)

- Borrar `.github/workflows/keepalive.yml`.
- Borrar la app en Streamlit Community Cloud.
- Borrar las carpetas `cloudflare-proxy/` (el Worker no se usa) y `redirect-hostalia/`.

## Límites gratuitos y cómo crecer

| Recurso | Límite gratis | Cuándo se notaría |
|---|---|---|
| VM Oracle A1 | 4 OCPU / 24 GB RAM / 200 GB disco / 10 TB tráfico al mes | Decenas de usuarios simultáneos. Streamlit usa unos 100-200 MB por sesión activa. |
| Supabase Free | 500 MB de BBDD, 50.000 usuarios activos al mes, 1 GB de storage | Cuando la BBDD pase de 500 MB. Hoy son datos de texto (recetas, facturas), así que queda mucho margen. |
| Caddy + Let's Encrypt | Sin límite práctico | — |

Vías de crecimiento sin coste:

1. **Más capacidad para la app**: subir la VM de 2/12 a 4/24 (sigue siendo gratis), o levantar varias réplicas de `app` balanceadas por Caddy con sesión fija (`lb_policy cookie`), que Streamlit necesita porque cada usuario mantiene su sesión en una réplica concreta.
2. **Independizarse de Supabase Free** (si llega a los 500 MB o se quiere eliminar el keepalive): autoalojar Supabase con Docker en la misma VM. Hay RAM de sobra, y Auth, RLS y la API siguen siendo compatibles, así que el código no cambia. A cambio hay que gestionar backups propios (por ejemplo, un `pg_dump` diario a Cloudflare R2, cuyo plan gratuito incluye 10 GB).

## Copias de seguridad

Supabase Free **no incluye backups descargables**. Recomendado: un `pg_dump` semanal desde la VM con la cadena de conexión de Supabase (*Project Settings → Database*), guardado fuera de la VM.
