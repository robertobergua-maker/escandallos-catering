#!/usr/bin/env bash
# =============================================================================
# backup.sh — Copia de seguridad cifrada de Supabase → Google Drive
# =============================================================================
# Dependencias en la VM:
#   postgresql-client  (pg_dump)
#   age                (cifrado asimétrico)
#   rclone             (subida a GDrive)
#
# Variables de entorno requeridas:
#   DATABASE_URL   cadena de conexión Postgres de Supabase
#                  formato: postgres://user:password@host:5432/postgres
#
# Uso manual:
#   DATABASE_URL="postgres://..." bash scripts/backup.sh
#
# Ver scripts/README.md para instalación, prueba y crontab.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuración
# ---------------------------------------------------------------------------

AGE_PUBKEY="age1u7qgmyjqys7hvhnap0yyzl0gwfu3vlq7gjtjxz05qqghsygtf4jsc2zq7l"
RCLONE_DEST="gdrive:Escandallos_Backups"
BACKUP_DIR="${BACKUP_DIR:-/tmp}"
DATE=$(date -u +"%Y-%m-%d")
FILENAME="backup_escandallos_${DATE}.dump.age"
FILEPATH="${BACKUP_DIR}/${FILENAME}"

# ---------------------------------------------------------------------------
# Comprobaciones previas
# ---------------------------------------------------------------------------

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "ERROR: la variable DATABASE_URL no está definida." >&2
  echo "       Ejemplo: export DATABASE_URL='postgres://user:pass@host:5432/postgres'" >&2
  exit 1
fi

for cmd in pg_dump age rclone; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' no está instalado o no está en el PATH." >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Volcado + cifrado al vuelo (sin fichero intermedio sin cifrar)
# ---------------------------------------------------------------------------

echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Iniciando pg_dump → age → ${FILEPATH}"

pg_dump \
  --format=custom \
  --no-password \
  "${DATABASE_URL}" \
| age \
  --recipient "${AGE_PUBKEY}" \
  --output "${FILEPATH}"

echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Volcado cifrado listo: ${FILEPATH} ($(du -sh "${FILEPATH}" | cut -f1))"

# ---------------------------------------------------------------------------
# Subida a Google Drive con rclone
# ---------------------------------------------------------------------------

echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Subiendo a ${RCLONE_DEST}/${FILENAME} …"

rclone copyto \
  "${FILEPATH}" \
  "${RCLONE_DEST}/${FILENAME}" \
  --stats-one-line \
  --stats=10s

echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Subida completada."

# ---------------------------------------------------------------------------
# Limpieza del fichero local
# ---------------------------------------------------------------------------

rm -f "${FILEPATH}"
echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Fichero local eliminado. Copia finalizada con éxito."
