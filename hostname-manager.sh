#!/usr/bin/env bash

# ============================================================
# GESTOR DE HOSTNAME VPS
# Ubuntu / Debian | Validación | Respaldo | Verificación
# Conserva mayúsculas y minúsculas
# ============================================================

set -Eeuo pipefail
umask 077

# ============================================================
# PALETA DE COLORES
# ============================================================

if [[ -t 1 ]]; then
    RESET=$'\033[0m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    CYAN=$'\033[1;36m'
    BLUE=$'\033[1;34m'
    GREEN=$'\033[1;32m'
    YELLOW=$'\033[1;33m'
    RED=$'\033[1;31m'
    WHITE=$'\033[1;37m'
    MAGENTA=$'\033[1;35m'
    GRAY=$'\033[0;37m'
else
    RESET='' BOLD='' DIM='' CYAN='' BLUE=''
    GREEN='' YELLOW='' RED='' WHITE=''
    MAGENTA='' GRAY=''
fi

# ============================================================
# CONFIGURACIÓN
# ============================================================

HOSTS_FILE="/etc/hosts"
BACKUP_DIR="/var/backups/hostname-manager"

TMP_FILE=""
BACKUP_FILE=""
OLD_HOST=""
CHANGE_STARTED=0

# ============================================================
# COMPONENTES DE INTERFAZ
# ============================================================

line() {
    printf '  %b%s%b\n' "$BLUE" \
        '────────────────────────────────────────────────────' "$RESET"
}

header() {
    clear 2>/dev/null || true

    printf '\n'
    printf '  %b◆%b  %bHOSTNAME MANAGER%b\n' \
        "$CYAN" "$RESET" "$WHITE$BOLD" "$RESET"

    printf '     %bAdministración del nombre del servidor%b\n' \
        "$GRAY" "$RESET"

    line
}

section() {
    printf '\n'
    printf '  %b▸%b  %b%s%b\n' \
        "$CYAN$BOLD" "$RESET" "$WHITE$BOLD" "$1" "$RESET"
    line
}

success() {
    printf '  %b✓%b  %b%s%b\n' \
        "$GREEN$BOLD" "$RESET" "$WHITE" "$1" "$RESET"
}

error() {
    printf '  %b✗%b  %b%s%b\n' \
        "$RED$BOLD" "$RESET" "$WHITE" "$1" "$RESET" >&2
}

warning() {
    printf '  %b!%b  %b%s%b\n' \
        "$YELLOW$BOLD" "$RESET" "$YELLOW" "$1" "$RESET"
}

detail() {
    printf '  %b›%b  %s\n' "$CYAN" "$RESET" "$1"
}

field() {
    local label="$1"
    local value="$2"
    local style="${3:-$WHITE}"

    printf '  %b%-21s%b %b%s%b\n' \
        "$GRAY" "$label" "$RESET" "$style" "$value" "$RESET"
}

status() {
    local label="$1"
    local value="$2"

    printf '  %b●%b  %-25s %b%s%b\n' \
        "$GREEN" "$RESET" "$label" "$GREEN$BOLD" "$value" "$RESET"
}

cleanup() {
    if [[ -n "$TMP_FILE" && -f "$TMP_FILE" ]]; then
        rm -f -- "$TMP_FILE"
    fi
}

trap cleanup EXIT

# ============================================================
# CONTROL DE ERRORES
# ============================================================

on_error() {
    local code=$?
    trap - ERR

    error "La operación falló (código $code)."

    if (( CHANGE_STARTED == 1 )); then
        warning "Revisa el hostname y el archivo /etc/hosts."

        if [[ -n "$BACKUP_FILE" && -f "$BACKUP_FILE" ]]; then
            detail "Respaldo disponible: $BACKUP_FILE"
        fi
    fi

    exit "$code"
}

trap on_error ERR

# ============================================================
# COMPROBACIONES INICIALES
# ============================================================

if (( EUID != 0 )); then
    error "Este script debe ejecutarse como root."
    detail "Ejemplo: sudo bash hostname-manager.sh"
    exit 1
fi

for cmd in hostnamectl python3 mktemp cp mv date uname grep chmod chown; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error "No se encontró el comando requerido: $cmd"
        exit 1
    fi
done

if [[ ! -f "$HOSTS_FILE" || ! -r "$HOSTS_FILE" ||
      ! -w "$HOSTS_FILE" ]]; then
    error "No se puede leer o modificar $HOSTS_FILE."
    exit 1
fi

if ! hostnamectl --static >/dev/null 2>&1; then
    error "No se pudo consultar el hostname actual."
    exit 1
fi

CURRENT_HOST="$(hostnamectl --static)"
OLD_HOST="$CURRENT_HOST"

OS_NAME="$(
    . /etc/os-release
    printf '%s' "${PRETTY_NAME:-Linux}"
)"

ARCH="$(uname -m)"

# ============================================================
# PANEL PRINCIPAL
# ============================================================

header

section "INFORMACIÓN DEL SERVIDOR"

field "Hostname actual" "$CURRENT_HOST" "$YELLOW$BOLD"
field "Sistema operativo" "$OS_NAME" "$WHITE"
field "Arquitectura" "$ARCH" "$MAGENTA"
field "Archivo de hosts" "$HOSTS_FILE" "$CYAN"

printf '\n'
line

printf '  %b●%b  %bSistema preparado para configurar%b\n' \
    "$GREEN" "$RESET" "$WHITE" "$RESET"

detail "Se conservarán las mayúsculas y minúsculas."
detail "Se preservarán las entradas IPv6 y localhost."
detail "Se creará un respaldo antes de modificar los archivos."

# ============================================================
# SOLICITUD Y VALIDACIÓN DEL HOSTNAME
# ============================================================

section "NUEVA CONFIGURACIÓN"

while true; do
    printf '\n'
    printf '  %bNombre del nuevo hostname%b\n' "$WHITE$BOLD" "$RESET"
    printf '  %b›%b ' "$CYAN" "$RESET"

    if ! IFS= read -r NEW_HOST; then
        printf '\n'
        error "No se recibió ningún nombre."
        exit 1
    fi

    # Eliminar espacios externos sin modificar las mayúsculas.
    NEW_HOST="${NEW_HOST#"${NEW_HOST%%[![:space:]]*}"}"
    NEW_HOST="${NEW_HOST%"${NEW_HOST##*[![:space:]]}"}"

    if [[ -z "$NEW_HOST" ]]; then
        error "El hostname no puede estar vacío."
        continue
    fi

    if (( ${#NEW_HOST} > 64 )); then
        error "El hostname no puede superar 64 caracteres."
        continue
    fi

    if [[ ! "$NEW_HOST" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
        error "Usa letras, números, puntos o guiones."
        error "No utilices espacios ni guiones en los extremos."
        continue
    fi

    VALID_HOST=1
    IFS='.' read -r -a LABELS <<< "$NEW_HOST"

    for LABEL in "${LABELS[@]}"; do
        if (( ${#LABEL} > 63 )) ||
           [[ ! "$LABEL" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
            VALID_HOST=0
            break
        fi
    done

    if (( VALID_HOST == 0 )); then
        error "Una sección del hostname tiene un formato inválido."
        continue
    fi

    break
done

# ============================================================
# RESUMEN Y CONFIRMACIÓN
# ============================================================

section "REVISIÓN DE CAMBIOS"

printf '\n'

field "Hostname anterior" "$CURRENT_HOST" "$YELLOW"
field "Hostname nuevo" "$NEW_HOST" "$GREEN$BOLD"

printf '\n'
line

if [[ "$CURRENT_HOST" == "$NEW_HOST" ]]; then
    warning "El nombre introducido coincide con el actual."
fi

printf '\n'
printf '  %b¿Deseas aplicar los cambios?%b [S/n]: ' \
    "$WHITE$BOLD" "$RESET"

IFS= read -r CONFIRM || CONFIRM=""

if [[ -n "$CONFIRM" ]]; then
    CONFIRM="${CONFIRM,,}"

    if [[ "$CONFIRM" != "s" &&
          "$CONFIRM" != "si" &&
          "$CONFIRM" != "sí" ]]; then
        warning "Operación cancelada. No se realizaron cambios."
        exit 0
    fi
fi

# ============================================================
# RESPALDO DE SEGURIDAD
# ============================================================

section "RESPALDO DE SEGURIDAD"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

BACKUP_FILE="$BACKUP_DIR/hosts-$(date +%Y%m%d-%H%M%S)-$$.bak"

cp -a -- "$HOSTS_FILE" "$BACKUP_FILE"

success "Respaldo creado correctamente."
detail "$BACKUP_FILE"

# Preparar un archivo temporal en el mismo sistema de archivos.
TMP_FILE="$(mktemp /etc/.hosts.hostname.XXXXXX)"

chmod --reference="$HOSTS_FILE" "$TMP_FILE"
chown --reference="$HOSTS_FILE" "$TMP_FILE"

# ============================================================
# PREPARAR /etc/hosts
# ============================================================

section "PREPARANDO CONFIGURACIÓN"

if ! python3 - "$HOSTS_FILE" "$TMP_FILE" "$NEW_HOST" <<'PY'
import ipaddress
import sys

source, destination, hostname = sys.argv[1:4]

with open(source, "r", encoding="utf-8") as f:
    lines = f.readlines()

result = []
found = False

for line in lines:
    stripped = line.strip()

    if not stripped or stripped.startswith("#"):
        result.append(line)
        continue

    content, separator, comment = line.partition("#")
    fields = content.split()

    if not fields:
        result.append(line)
        continue

    try:
        address = ipaddress.ip_address(fields[0])
    except ValueError:
        result.append(line)
        continue

    if address == ipaddress.ip_address("127.0.1.1"):
        if not found:
            replacement = f"127.0.1.1\t{hostname}"

            if separator:
                replacement += f"  #{comment.rstrip()}"

            result.append(replacement + "\n")
            found = True

        # Evitar duplicados de 127.0.1.1.
        continue

    result.append(line)

if not found:
    insert_at = 0

    for i, line in enumerate(result):
        content = line.split("#", 1)[0].split()

        if content and content[0] == "127.0.0.1":
            insert_at = i + 1
            break

    result.insert(insert_at, f"127.0.1.1\t{hostname}\n")

with open(destination, "w", encoding="utf-8") as f:
    f.writelines(result)
PY
then
    error "No se pudo preparar el archivo /etc/hosts."
    exit 1
fi

success "Archivo de configuración preparado."
detail "Las entradas IPv6 y localhost se mantienen."

# ============================================================
# APLICAR CAMBIOS
# ============================================================

section "APLICANDO CAMBIOS"

CHANGE_STARTED=1

if ! hostnamectl set-hostname "$NEW_HOST"; then
    error "No se pudo cambiar el hostname."
    exit 1
fi

success "Hostname actualizado."

# Reemplazo atómico del archivo.
if ! mv -f -- "$TMP_FILE" "$HOSTS_FILE"; then
    warning "No se pudo instalar el nuevo /etc/hosts."
    warning "Intentando restaurar el hostname anterior."

    hostnamectl set-hostname "$OLD_HOST" || true

    error "El respaldo permanece disponible: $BACKUP_FILE"
    exit 1
fi

TMP_FILE=""

success "Archivo /etc/hosts actualizado."

# ============================================================
# VERIFICACIÓN FINAL
# ============================================================

section "VERIFICACIÓN"

FINAL_HOST="$(hostnamectl --static)"

if [[ "$FINAL_HOST" != "$NEW_HOST" ]]; then
    error "El hostname resultante no coincide con el solicitado."
    detail "Respaldo disponible: $BACKUP_FILE"
    exit 1
fi

if ! python3 - "$HOSTS_FILE" "$NEW_HOST" <<'PY'
import sys

path, hostname = sys.argv[1:3]

with open(path, encoding="utf-8") as f:
    for line in f:
        content = line.split("#", 1)[0].split()

        if len(content) >= 2 and content[0] == "127.0.1.1":
            if content[1] == hostname:
                sys.exit(0)

sys.exit(1)
PY
then
    error "No se verificó la entrada de /etc/hosts."
    detail "Respaldo disponible: $BACKUP_FILE"
    exit 1
fi

success "Hostname verificado."
success "Entrada de /etc/hosts verificada."

# ============================================================
# RESUMEN FINAL
# ============================================================

header

printf '\n'
printf '  %b✓  CONFIGURACIÓN COMPLETADA%b\n' \
    "$GREEN$BOLD" "$RESET"

printf '  %bEl hostname se actualizó correctamente.%b\n' \
    "$WHITE" "$RESET"

line

section "ESTADO FINAL"

status "Hostname" "$FINAL_HOST"
status "hostnamectl" "Verificado"
status "/etc/hosts" "Verificado"
status "Respaldo" "Guardado"

printf '\n'
line

section "ENTRADAS LOCALES"

while IFS= read -r HOST_LINE; do
    read -r IP_ADDRESS HOST_ALIASES <<< "$HOST_LINE"

    printf '  %b›%b  %b%-13s%b %s\n' \
        "$CYAN" "$RESET" \
        "$GREEN" "$IP_ADDRESS" "$RESET" \
        "$HOST_ALIASES"
done < <(
    grep -E '^(127\.0\.0\.1|127\.0\.1\.1|::1)[[:space:]]' \
        "$HOSTS_FILE" || true
)

printf '\n'
line

printf '  %b◆%b  %bPROCESO FINALIZADO%b\n' \
    "$CYAN" "$RESET" "$GREEN$BOLD" "$RESET"

printf '  %bNo es necesario reiniciar el VPS.%b\n' \
    "$GRAY" "$RESET"

printf '\n'
detail "Respaldo: $BACKUP_FILE"
printf '\n'
