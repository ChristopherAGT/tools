#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# ============================================================
#       SSH ROOT ACCESS | SECURE CONTROL
#       Configuracion de acceso SSH por contraseña
# ============================================================

# ── COLORES ─────────────────────────────────────────────────
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
BOLD='\033[1m'
RESET='\033[0m'

# ── CONFIGURACION ───────────────────────────────────────────
SSH_DIR="/etc/ssh"
SSH_CONFIG="$SSH_DIR/sshd_config"
DROPIN_DIR="$SSH_DIR/sshd_config.d"
DROPIN="$DROPIN_DIR/00-root-password-auth.conf"
BACKUP_DIR="/root/.ssh-root-auth-backups"

CONFIG_CHANGED=0
PASSWORD_CHANGED=0
BACKUP_PATH=""
SERVICE=""
SERVICE_RESTARTED=0

# ── INTERFAZ ────────────────────────────────────────────────
line() {
    printf '%b\n' "${CYAN}────────────────────────────────────────────────${RESET}"
}

header() {
    clear 2>/dev/null || true
    printf '\n%b\n' "${BLUE}${BOLD}   SSH ROOT ACCESS${RESET}"
    printf '%b\n' "${CYAN}   Configuracion segura de acceso SSH${RESET}"
    line
    printf '%b\n\n' "${GRAY}   Ubuntu / Debian · Administracion del servidor${RESET}"
}

check() {
    printf '%b\n' "${GREEN}  ✓${RESET} $*"
}

fail() {
    printf '%b\n' "${RED}  ✗ ERROR:${RESET} $*" >&2
}

notice() {
    printf '%b\n' "${YELLOW}  !${RESET} $*"
}

# ── ELEVACION AUTOMATICA A ROOT ─────────────────────────────
if [[ "${EUID}" -ne 0 ]]; then
    SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"

    if command -v sudo >/dev/null 2>&1; then
        exec sudo -E bash "$SCRIPT_PATH" "$@"
    elif command -v su >/dev/null 2>&1; then
        exec su -c 'exec bash "$1" "${@:2}"' _ "$SCRIPT_PATH" "$@"
    else
        printf '%b\n' "${RED}  ✗ ERROR:${RESET} No hay sudo ni su disponibles para obtener permisos root." >&2
        exit 1
    fi
fi

# ── DETECCION DEL SERVICIO SSH ──────────────────────────────
detect_service() {
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl cat ssh.service >/dev/null 2>&1; then
            SERVICE="ssh"
            return 0
        elif systemctl cat sshd.service >/dev/null 2>&1; then
            SERVICE="sshd"
            return 0
        fi
    fi

    if command -v service >/dev/null 2>&1; then
        if service ssh status >/dev/null 2>&1; then
            SERVICE="ssh"
            return 0
        elif service sshd status >/dev/null 2>&1; then
            SERVICE="sshd"
            return 0
        fi
    fi

    fail "No se pudo detectar el servicio SSH."
    return 1
}

# ── RESPALDO Y RESTAURACION ─────────────────────────────────
rollback_config() {
    local original_status="${1:-1}"

    trap - ERR
    set +e

    if [[ "$CONFIG_CHANGED" -eq 1 && -n "$BACKUP_PATH" ]]; then
        printf '\n'
        notice "Se produjo un error. Restaurando la configuracion anterior..."

        if [[ -f "$BACKUP_PATH/dropin-existed" ]]; then
            if [[ -f "$BACKUP_PATH/previous-dropin.conf" ]]; then
                cp -p -- "$BACKUP_PATH/previous-dropin.conf" "$DROPIN"
            else
                fail "No se encontro el respaldo del archivo anterior."
            fi
        else
            rm -f -- "$DROPIN"
        fi

        if command -v sshd >/dev/null 2>&1 && sshd -t; then
            local restore_ok=0

            if command -v systemctl >/dev/null 2>&1; then
                systemctl restart "$SERVICE" >/dev/null 2>&1 &&
                    restore_ok=1
            elif command -v service >/dev/null 2>&1; then
                service "$SERVICE" restart >/dev/null 2>&1 &&
                    restore_ok=1
            fi

            if [[ "$restore_ok" -eq 1 ]]; then
                printf '%b\n' "${GREEN}  ✓${RESET} Configuracion anterior restaurada."
            else
                fail "No se pudo reiniciar SSH con la configuracion restaurada."
            fi
        else
            fail "La configuracion restaurada no supera sshd -t."
            fail "Revisa manualmente: $DROPIN"
        fi
    fi

    if [[ "$PASSWORD_CHANGED" -eq 1 ]]; then
        notice "La contraseña ya se habia actualizado; no se puede revertir automaticamente."
    fi

    exit "$original_status"
}

on_error() {
    local status="$1"
    fail "La operacion fallo (codigo $status)."
    rollback_config "$status"
}

trap 'on_error $?' ERR

# ── VALIDACIONES INICIALES ──────────────────────────────────
header

if [[ ! -f "$SSH_CONFIG" ]]; then
    fail "No se encontro $SSH_CONFIG."
    exit 1
fi

if ! command -v sshd >/dev/null 2>&1; then
    fail "No se encontro el ejecutable sshd."
    exit 1
fi

if ! command -v chpasswd >/dev/null 2>&1; then
    fail "No se encontro el comando chpasswd."
    exit 1
fi

if ! command -v install >/dev/null 2>&1; then
    fail "No se encontro el comando install."
    exit 1
fi

if ! detect_service; then
    exit 1
fi

if ! command -v systemctl >/dev/null 2>&1 &&
   ! command -v service >/dev/null 2>&1; then
    fail "No se encontro systemctl ni service."
    exit 1
fi

if ! sshd -t; then
    fail "La configuracion SSH actual contiene errores. No se modificara."
    exit 1
fi

check "Requisitos del sistema verificados."
check "Servicio SSH detectado: $SERVICE"
check "Configuracion SSH actual valida."

# ── PREPARAR DIRECTORIOS ────────────────────────────────────
install -d -m 0755 "$DROPIN_DIR"
install -d -m 0700 "$BACKUP_DIR"

# ── CREAR RESPALDO ──────────────────────────────────────────
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_PATH="$BACKUP_DIR/$TIMESTAMP"

install -d -m 0700 "$BACKUP_PATH"

if [[ -f "$DROPIN" ]]; then
    cp -p -- "$DROPIN" "$BACKUP_PATH/previous-dropin.conf"
    touch "$BACKUP_PATH/dropin-existed"
else
    touch "$BACKUP_PATH/dropin-did-not-exist"
fi

printf '%s\n' "$DROPIN" > "$BACKUP_PATH/managed-file.txt"
printf '%s\n' "$SERVICE" > "$BACKUP_PATH/service.txt"

check "Respaldo de configuracion creado."

# ── CONFIGURAR AUTENTICACION SSH ────────────────────────────
CONFIG_CHANGED=1

cat > "$DROPIN" <<'EOF'
# Administracion de acceso root por contraseña
# Archivo administrado por SSH ROOT ACCESS
PermitRootLogin yes
PasswordAuthentication yes
EOF

chmod 0600 "$DROPIN"
chown root:root "$DROPIN"

# ── VALIDAR CONFIGURACION SSH ───────────────────────────────
if ! sshd -t; then
    fail "La configuracion modificada no supera sshd -t."
    false
fi

check "Sintaxis de la configuracion SSH valida."

EFFECTIVE_CONFIG="$(sshd -T)"

if ! grep -qx 'permitrootlogin yes' <<< "$EFFECTIVE_CONFIG"; then
    fail "PermitRootLogin yes no esta activo en la configuracion efectiva."
    fail "Revisa las directivas existentes y las reglas Match."
    false
fi

if ! grep -qx 'passwordauthentication yes' <<< "$EFFECTIVE_CONFIG"; then
    fail "PasswordAuthentication yes no esta activo en la configuracion efectiva."
    fail "Revisa las directivas existentes y las reglas Match."
    false
fi

check "Acceso root por contraseña habilitado en la configuracion efectiva."

# ── REINICIAR SERVICIO SSH ──────────────────────────────────
if command -v systemctl >/dev/null 2>&1; then
    if ! systemctl restart "$SERVICE"; then
        fail "No se pudo reiniciar el servicio $SERVICE."
        false
    fi

    if ! systemctl is-active --quiet "$SERVICE"; then
        fail "El servicio $SERVICE no quedo activo despues del reinicio."
        false
    fi
else
    if ! service "$SERVICE" restart; then
        fail "No se pudo reiniciar el servicio $SERVICE."
        false
    fi
fi

SERVICE_RESTARTED=1
check "Servicio SSH reiniciado correctamente."

# ── VERIFICACION POSTERIOR AL REINICIO ──────────────────────
if ! sshd -t; then
    fail "La configuracion SSH fallo en la verificacion posterior al reinicio."
    false
fi

if command -v systemctl >/dev/null 2>&1; then
    if ! systemctl is-active --quiet "$SERVICE"; then
        fail "El servicio SSH no esta activo."
        false
    fi
fi

check "Servicio SSH activo y configuracion valida."

# ── ESTABLECER CONTRASEÑA DE ROOT ───────────────────────────
printf '\n'
line
printf '%b\n' "${WHITE}${BOLD}   CONFIGURAR CONTRASEÑA DE ROOT${RESET}"
line
printf '\n'

while true; do
    ROOT_PASSWORD=""
    ROOT_PASSWORD_CONFIRM=""

    IFS= read -r -s -p "Nueva contraseña de root: " ROOT_PASSWORD </dev/tty
    printf '\n'
    IFS= read -r -s -p "Confirma la contraseña: " ROOT_PASSWORD_CONFIRM </dev/tty
    printf '\n'

    if [[ -z "$ROOT_PASSWORD" ]]; then
        notice "La contraseña no puede estar vacia."
        continue
    fi

    if [[ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]]; then
        notice "Las contraseñas no coinciden. Intentalo nuevamente."
        unset ROOT_PASSWORD ROOT_PASSWORD_CONFIRM
        continue
    fi

    break
done

# ── ACTUALIZAR CONTRASEÑA ───────────────────────────────────
if ! printf 'root:%s\n' "$ROOT_PASSWORD" | chpasswd; then
    unset ROOT_PASSWORD ROOT_PASSWORD_CONFIRM
    fail "No se pudo actualizar la contraseña de root."
    false
fi

unset ROOT_PASSWORD ROOT_PASSWORD_CONFIRM
PASSWORD_CHANGED=1

check "Contraseña de root actualizada correctamente."

# ── FINALIZAR ───────────────────────────────────────────────
CONFIG_CHANGED=0
trap - ERR

printf '\n'
line
printf '%b\n' "${GREEN}${BOLD}   OPERACION COMPLETADA${RESET}"
line

check "Configuracion SSH validada."
check "Acceso root por contraseña habilitado."
check "Contraseña de root actualizada."

if [[ "$SERVICE_RESTARTED" -eq 1 ]]; then
    check "Servicio SSH reiniciado correctamente."
else
    fail "No se pudo confirmar el reinicio del servicio SSH."
fi

check "Respaldo guardado en: $BACKUP_PATH"

printf '\n'
notice "Mantén abierta tu sesión actual hasta probar una nueva conexión SSH."
printf '\n'
