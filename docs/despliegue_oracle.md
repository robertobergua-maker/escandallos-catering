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
   - Shape: **VM.Standard.A1.Flex**, con 2 OCPU y 12 GB. Es la VM actual: `escandallos-vm`, región Madrid 3, Ubuntu 24.04 arm64, usuario `ubuntu`, IP `82.70.90.53`.
   - Añadir tu clave SSH pública.
   - Si sale *Out of capacity*, reintentar más tarde o probar con otro Availability Domain.
4. Anotar la **IP pública** de la instancia. Se mantiene aunque la VM se pare o reinicie, y solo se pierde si se elimina la instancia.
5. Abrir los puertos 80 y 443 en la red de Oracle: *Instance → Subnet → Security List → Add Ingress Rules*, con origen `0.0.0.0/0`, protocolo TCP y puertos `80,443`.

## 2. Preparar la VM

```bash
ssh -i <clave_privada> ubuntu@82.70.90.53
sudo apt update && sudo apt -y upgrade
sudo apt -y install unattended-upgrades  # parches de seguridad automáticos
```

Las imágenes Ubuntu de Oracle traen un cortafuegos (iptables) que rechaza todo salvo SSH, con un `REJECT` final en la cadena INPUT. Las reglas de 80 y 443 se insertan **justo antes de ese REJECT** y se guardan **antes de instalar Docker**, para no persistir también las reglas que Docker crea solo:

```bash
sudo iptables -L INPUT -n --line-numbers          # localizar el número N del REJECT
sudo iptables -I INPUT N -p tcp -m state --state NEW --dport 443 -j ACCEPT
sudo iptables -I INPUT N -p tcp -m state --state NEW --dport 80 -j ACCEPT
sudo netfilter-persistent save
```

Docker y el plugin compose desde el repositorio oficial de Docker:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker ubuntu        # salir y volver a entrar por SSH
docker compose version
sudo mkdir -p /opt/escandallos/app /opt/escandallos/secrets
sudo chown ubuntu:ubuntu /opt/escandallos /opt/escandallos/app
```

> **⚠️ Tras instalar Docker, no volver a ejecutar `sudo netfilter-persistent save`.** Docker crea sus propias reglas de iptables (cadenas `DOCKER-*` en FORWARD y NAT) cada vez que arranca. Si se guardan, se cargan duplicadas en el siguiente arranque y pueden romper la red de los contenedores. Para cambiar el cortafuegos, editar directamente `/etc/iptables/rules.v4` (solo la cadena `INPUT`, siempre antes del `REJECT`) y aplicarlo con `sudo reboot`, o con `sudo netfilter-persistent reload && sudo systemctl restart docker` (el reload vacía las cadenas de Docker y el reinicio de Docker las recrea).

Estructura en la VM:

```
/opt/escandallos/app/              código (copia del repo)
/opt/escandallos/app/deploy/.env   APP_DOMAIN y ruta del secreto (no es secreto)
/opt/escandallos/secrets/secrets.toml   secretos, permisos 600, dueño UID 10001
```

## 3. Apuntar el subdominio en Hostalia

En Hostalia, `escandallos.samirarte.com` es **una zona DNS propia** (con su SOA y sus NS), separada de la de `samirarte.com`. Por eso los registros de este subdominio se crean dentro de la zona `escandallos.samirarte.com`.

**Primero, prueba con un subdominio provisional** sin tocar el actual: en la zona `escandallos.samirarte.com`, registro **A** `nuevo-escandallos` → `82.70.90.53`. El nombre completo es `nuevo-escandallos.escandallos.samirarte.com`, y en `.env` se pone `APP_DOMAIN=nuevo-escandallos.escandallos.samirarte.com`. El panel tarda unos minutos en publicar los cambios. Para comprobarlo sin cachés, **desde la VM** (la red de casa puede interceptar las consultas DNS y dar resultados falsos): `dig +short A nuevo-escandallos.escandallos.samirarte.com @ns10.servicio-online.net`, o `dig +trace` para seguir la delegación completa.

Cuando todo funcione, se hace el cambio definitivo:

1. En el panel de Hostalia, quitar la configuración actual de `escandallos.samirarte.com` como subdominio de hosting (la redirección de `redirect-hostalia/`).
2. En la *zona DNS* `escandallos.samirarte.com`, editar el registro **A** del propio nombre de la zona (`escandallos.samirarte.com`, a veces mostrado como `@` o vacío), que hoy apunta a `82.194.68.97`, para que apunte a la IP de la VM. Si la zona desaparece al quitar el subdominio de hosting, crear en la zona `samirarte.com` un registro **A** `escandallos` → IP de la VM y volver a crear el provisional si sigue haciendo falta.
3. Comprobar la propagación (puede tardar de minutos a unas horas) con `nslookup escandallos.samirarte.com`, que debe devolver la IP de la VM.

Hasta que el DNS no apunte a la VM, Caddy no podrá obtener el certificado. Conviene hacer este paso antes de arrancar.

## 4. Secretos y arranque

El secreto se escribe directamente en la VM; nunca pasa por git ni por el chat. La app lee estas claves:

| Clave | Obligatoria | Nota |
|---|---|---|
| `SUPABASE_URL` | Sí | |
| `SUPABASE_KEY` | Sí | Clave anon/publishable (RLS) |
| `OPENAI_API_KEY` | Sí, para las funciones de IA | |
| `PASSWORD_RECOVERY_REDIRECT_URL` | Recomendada | URL pública actual (provisional o definitiva) |
| `EMISOR_NOMBRE_FISCAL`, `EMISOR_NIF`, `EMISOR_DIRECCION`, `EMISOR_CP_CIUDAD`, `EMISOR_PROVINCIA`, `EMISOR_PAIS` | Opcionales | Datos fiscales de facturas |

```bash
sudo install -m 600 -o 10001 -g 10001 /dev/null /opt/escandallos/secrets/secrets.toml
sudo nano /opt/escandallos/secrets/secrets.toml   # pegar el contenido de Streamlit Cloud
cd /opt/escandallos/app/deploy
cp .env.example .env && nano .env   # APP_DOMAIN
docker compose up -d --build
docker compose ps
docker compose logs -f caddy app   # Caddy debe indicar "certificate obtained successfully"
```

Tanto la URL provisional como la definitiva deben estar en Supabase → *Authentication → URL Configuration → Redirect URLs*.

## 5. Actualizar la app

Desde Windows, en la carpeta del repo (copia el último commit, sin pasar por GitHub):

```powershell
git -c core.autocrlf=false archive --format=tar HEAD | ssh -i <clave_privada> ubuntu@82.70.90.53 "tar -x -C /opt/escandallos/app && cd /opt/escandallos/app/deploy && docker compose up -d --build"
```

## 6. Retirar lo antiguo (cuando todo funcione)

- Borrar `.github/workflows/keepalive.yml`.
- Borrar la app en Streamlit Community Cloud.
- Borrar las carpetas `cloudflare-proxy/` (el Worker no se usa) y `redirect-hostalia/`.

## Límites gratuitos y cómo crecer

| Recurso | Límite gratis | Cuándo se notaría |
|---|---|---|
| VM Oracle A1 | 4 OCPU / 24 GB RAM / 200 GB disco / 10 TB tráfico al mes (en uso: 2 OCPU / 12 GB) | Decenas de usuarios simultáneos. Streamlit usa unos 100-200 MB por sesión activa. |
| Supabase Free | 500 MB de BBDD, 50.000 usuarios activos al mes, 1 GB de storage | Cuando la BBDD pase de 500 MB. Hoy son datos de texto (recetas, facturas), así que queda mucho margen. |
| Caddy + Let's Encrypt | Sin límite práctico | — |

Vías de crecimiento sin coste:

1. **Más capacidad para la app**: subir la VM de 2/12 a 4/24 (sigue siendo gratis), o levantar varias réplicas de `app` balanceadas por Caddy con sesión fija (`lb_policy cookie`), que Streamlit necesita porque cada usuario mantiene su sesión en una réplica concreta.
2. **Independizarse de Supabase Free** (si llega a los 500 MB o se quiere eliminar el keepalive): autoalojar Supabase con Docker en la misma VM. Hay RAM de sobra, y Auth, RLS y la API siguen siendo compatibles, así que el código no cambia. A cambio hay que gestionar backups propios (por ejemplo, un `pg_dump` diario a Cloudflare R2, cuyo plan gratuito incluye 10 GB).

## Copias de seguridad

Supabase Free **no incluye backups descargables**. Recomendado: un `pg_dump` semanal desde la VM con la cadena de conexión de Supabase (*Project Settings → Database*), guardado fuera de la VM.
