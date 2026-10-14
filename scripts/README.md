# Scripts de mantenimiento

## backup.sh — Copia de seguridad cifrada en Google Drive

Hace un `pg_dump` de Supabase, lo cifra con `age` (cifrado asimétrico de clave
pública) y lo sube a Google Drive mediante `rclone`. No deja ningún fichero sin
cifrar en disco.

### Dependencias

Instalar en la VM una sola vez:

```bash
# postgresql-client (pg_dump)
sudo apt-get install -y postgresql-client

# age (https://github.com/FiloSottile/age)
sudo apt-get install -y age
# Si la versión del repo es antigua, instalar el binario oficial:
# AGE_VERSION=$(curl -s https://api.github.com/repos/FiloSottile/age/releases/latest | grep tag_name | cut -d'"' -f4)
# curl -Lo /tmp/age.tar.gz "https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/age-${AGE_VERSION}-linux-arm64.tar.gz"
# sudo tar -xz -C /usr/local/bin --strip-components=1 -f /tmp/age.tar.gz age/age age/age-keygen

# rclone
sudo apt-get install -y rclone
```

### Configurar rclone para Google Drive

Ejecutar **una sola vez** en la VM (requiere navegador en tu ordenador local):

```bash
rclone config
# → New remote → nombre: gdrive
# → Storage: Google Drive (opción "drive")
# → Dejar client_id y client_secret en blanco (usa las credenciales públicas de rclone)
# → Scope: 1 (acceso completo a Drive)
# → Seguir el enlace que muestra para autorizar en el navegador
# → Confirmar que el token se ha guardado
rclone lsd gdrive:          # debe listar las carpetas de tu Drive
rclone mkdir gdrive:Escandallos_Backups
```

La configuración queda en `~/.config/rclone/rclone.conf`.

### Variable de entorno DATABASE_URL

La cadena de conexión está en Supabase → **Project Settings → Database →
Connection string → URI** (modo *Transaction* o *Session*, puerto 5432).
Tiene el formato:

```
postgres://postgres.[ref]:[password]@aws-0-eu-west-3.pooler.supabase.com:5432/postgres
```

Guardarla en la VM de forma persistente (fuera del repo):

```bash
# Añadir al final de /etc/environment (disponible para todos los usuarios y cron):
echo 'DATABASE_URL="postgres://postgres.[ref]:[pass]@host:5432/postgres"' \
  | sudo tee -a /etc/environment
# Recargar en la sesión actual:
source /etc/environment
```

### Prueba manual

```bash
# Desde el directorio raíz del repo en la VM:
DATABASE_URL="postgres://..." bash scripts/backup.sh
```

Debería aparecer un fichero `backup_escandallos_YYYY-MM-DD.dump.age` en GDrive
bajo la carpeta `Escandallos_Backups`.

### Crontab — ejecución semanal (domingos a las 03:00 UTC)

```bash
crontab -e
```

Añadir la línea:

```cron
0 3 * * 0  source /etc/environment && bash /opt/escandallos/app/scripts/backup.sh >> /var/log/escandallos_backup.log 2>&1
```

Para ver el log:

```bash
tail -f /var/log/escandallos_backup.log
```

### Restaurar una copia

1. Descargar el fichero cifrado desde GDrive:

```bash
rclone copyto "gdrive:Escandallos_Backups/backup_escandallos_YYYY-MM-DD.dump.age" \
  /tmp/backup.dump.age
```

2. Descifrar con la clave privada correspondiente a la clave pública del script
   (guardada fuera de la VM, en lugar seguro):

```bash
age --decrypt \
  --identity /ruta/a/tu/clave_privada.age \
  --output /tmp/backup.dump \
  /tmp/backup.dump.age
```

3. Restaurar en una base de datos (sustituir `TARGET_DATABASE_URL` por la BD
   destino; puede ser la de Supabase o una local):

```bash
pg_restore \
  --format=custom \
  --no-owner \
  --no-privileges \
  --single-transaction \
  -d "${TARGET_DATABASE_URL}" \
  /tmp/backup.dump
```

4. Limpiar:

```bash
rm /tmp/backup.dump /tmp/backup.dump.age
```

### Clave privada

La clave pública usada en el script es:

```
age133xvpxx6u6f96zhpfq9r62vt0rqlkrmvzl2804phg9rcs0k8542sh8rky7
```

La clave privada correspondiente **no está en el repo**. Guárdala en un gestor
de contraseñas (p. ej. Bitwarden) o en un fichero local cifrado fuera de la VM.
Sin ella no se puede descifrar ninguna copia.
