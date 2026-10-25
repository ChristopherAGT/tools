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
BACKUP_PATH=""
SERVICE=""

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

success() {
    printf '%b\n' "${GREEN}[OK]${RESET} $*"
}

info() {
    printf '%b\n' "${CYAN}[INFO]${RESET} $*"
}

warn() {
    printf '%b\n' "${YELLOW}[AVISO]${RESET} $*"
}

error() {
    printf '%b\n' "${RED}[ERROR]${RESET} $*" >&2
}

# ── ELEVACION AUTOMATICA A ROOT ─────────────────────────────
if [[ "${EUID}" -ne 0 ]]; then
    SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"

    if command -v sudo >/dev/null 2>&1; then
        exec sudo -E bash "$SCRIPT_PATH" "$@"
    elif command -v su >/dev/null 2>&1; then
        exec su -c 'exec bash "$1" "${@:2}"' _ "$SCRIPT_PATH" "$@"
    else
        printf '%b\n' "${RED}[ERROR]${RESET} No hay un metodo disponible para obtener permisos root." >&2
        exit 1
    fi
fi

# ── DETECCION DEL SERVICIO ──────────────────────────────────
detect_service() {
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl list-unit-files ssh.service --no-legend 2>/dev/null |
            grep -q 'ssh.service'; then
            SERVICE="ssh"
            return 0
        elif systemctl list-unit-files sshd.service --no-legend 2>/dev/null |
            grep -q 'sshd.service'; then
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

    error "No se pudo detectar el servicio SSH."
    return 1
}

# ── RESPALDO Y RESTAURACION ─────────────────────────────────
rollback_config() {
    local original_status="${1:-1}"

    trap - ERR
    set +e

    if [[ "$CONFIG_CHANGED" -eq 1 && -n "$BACKUP_PATH" ]]; then
        warn "Se produjo un error. Restaurando la configuracion anterior..."

        if [[ -f "$BACKUP_PATH/dropin-existed" ]]; then
            if [[ -f "$BACKUP_PATH/previous-dropin.conf" ]]; then
                cp -p -- "$BACKUP_PATH/previous-dropin.conf" "$DROPIN"
            else
                error "No se encontro el respaldo del archivo anterior."
            fi
        else
            rm -f -- "$DROPIN"
        fi

        if command -v sshd >/dev/null 2>&1 && sshd -t; then
            if command -v systemctl >/dev/null 2>&1; then
                systemctl reload "$SERVICE" >/dev/null 2>&1 ||
                    systemctl restart "$SERVICE" >/dev/null 2>&1
            elif command -v service >/dev/null 2>&1; then
                service "$SERVICE" reload >/dev/null 2>&1 ||
                    service "$SERVICE" restart >/dev/null 2>&1
            fi
            success "Se restauro la configuracion SSH anterior."
        else
            error "La configuracion restaurada no supera sshd -t."
            error "Revisa manualmente: $DROPIN"
        fi
    fi

    exit "$original_status"
}

on_error() {
    local status="$1"
    error "La operacion fallo (codigo $status)."
    rollback_config "$status"
}

trap 'on_error $?' ERR

# ── VALIDACIONES INICIALES ──────────────────────────────────
header

info "Verificando requisitos del sistema..."

if [[ ! -f "$SSH_CONFIG" ]]; then
    error "No se encontro el archivo $SSH_CONFIG"
    exit 1
fi

if ! command -v sshd >/dev/null 2>&1; then
    error "No se encontro el ejecutable sshd."
    exit 1
fi

if ! command -v chpasswd >/dev/null 2>&1; then
    error "No se encontro el comando chpasswd."
    exit 1
fi

if ! command -v install >/dev/null 2>&1; then
    error "No se encontro el comando install."
    exit 1
fi

detect_service

if ! command -v systemctl >/dev/null 2>&1 &&
   ! command -v service >/dev/null 2>&1; then
    error "No se encontro systemctl ni service."
    exit 1
fi

if ! sshd -t; then
    error "La configuracion SSH actual contiene errores."
    error "No se modificara hasta corregirlos."
    exit 1
fi

success "Requisitos verificados."
info "Servicio detectado: $SERVICE"

# ── PREPARAR DIRECTORIOS ────────────────────────────────────
install -d -m 0755 "$DROPIN_DIR"
install -d -m 0700 "$BACKUP_DIR"

# ── RESPALDO ────────────────────────────────────────────────
info "Preparando respaldo de la configuracion..."

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_PATH="$BACKUP_DIR/$TIMESTAMP"

install -d -m 0700 "$BACKUP_PATH"

if [[ -f "$DROPIN" ]]; then
    cp -p -- "$DROPIN" "$BACKUP_PATH/previous-dropin.conf"
    touch "$BACKUP_PATH/dropin-existed"
    success "Archivo de configuracion anterior respaldado."
else
    success "No existia un archivo anterior; se registrara su ausencia."
fi

printf '%s\n' "$DROPIN" > "$BACKUP_PATH/managed-file.txt"
printf '%s\n' "$SERVICE" > "$BACKUP_PATH/service.txt"

# ── CONFIGURAR AUTENTICACION ────────────────────────────────
info "Configurando autenticacion SSH de root..."

CONFIG_CHANGED=1

cat > "$DROPIN" <<'EOF'
# Administracion de acceso root por contraseña
# Archivo administrado por SSH ROOT ACCESS
PermitRootLogin yes
PasswordAuthentication yes
EOF

chmod 0600 "$DROPIN"
chown root:root "$DROPIN"

# ── VALIDAR CONFIGURACION ───────────────────────────────────
info "Validando la configuracion antes de aplicarla..."

if ! sshd -t; then
    error "La nueva configuracion no supera la validacion."
    false
fi

EFFECTIVE_CONFIG="$(sshd -T)"

if ! grep -qx 'permitrootlogin yes' <<< "$EFFECTIVE_CONFIG"; then
    error "SSH no esta aplicando PermitRootLogin yes."
    error "Puede existir otra directiva o una regla Match que lo sobrescriba."
    false
fi

if ! grep -qx 'passwordauthentication yes' <<< "$EFFECTIVE_CONFIG"; then
    error "SSH no esta aplicando PasswordAuthentication yes."
    error "Puede existir otra directiva que lo sobrescriba."
    false
fi

success "Configuracion validada correctamente."

# ── APLICAR CAMBIOS ─────────────────────────────────────────
info "Aplicando los cambios al servicio SSH..."

if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet "$SERVICE"; then
        systemctl reload "$SERVICE" ||
            systemctl restart "$SERVICE"
    else
        systemctl start "$SERVICE"
    fi
else
    service "$SERVICE" reload ||
        service "$SERVICE" restart ||
        service "$SERVICE" start
fi

if ! sshd -t; then
    error "La validacion posterior a la recarga fallo."
    false
fi

success "Servicio SSH actualizado."

# ── ESTABLECER CONTRASEÑA DE ROOT ───────────────────────────
printf '\n'
line
printf '%b\n' "${WHITE}${BOLD}   CONFIGURAR CONTRASEÑA DE ROOT${RESET}"
line
printf '\n'
warn "Introduce una contraseña robusta y exclusiva para este servidor."
warn "La contraseña no se mostrara en pantalla."
printf '\n'

while true; do
    ROOT_PASSWORD=""
    ROOT_PASSWORD_CONFIRM=""

    IFS= read -r -s -p "Nueva contraseña de root: " ROOT_PASSWORD </dev/tty
    printf '\n'
    IFS= read -r -s -p "Confirma la contraseña: " ROOT_PASSWORD_CONFIRM </dev/tty
    printf '\n'

    if [[ -z "$ROOT_PASSWORD" ]]; then
        warn "La contraseña no puede estar vacia."
        continue
    fi

    if [[ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]]; then
        warn "Las contraseñas no coinciden. Intentalo nuevamente."
        unset ROOT_PASSWORD ROOT_PASSWORD_CONFIRM
        continue
    fi

    break
done

info "Actualizando la contraseña de root..."

if ! printf 'root:%s\n' "$ROOT_PASSWORD" | chpasswd; then
    unset ROOT_PASSWORD ROOT_PASSWORD_CONFIRM
    error "No se pudo actualizar la contraseña de root."
    false
fi

unset ROOT_PASSWORD ROOT_PASSWORD_CONFIRM

success "Contraseña de root actualizada."

# ── VERIFICACION FINAL ──────────────────────────────────────
info "Realizando comprobaciones finales..."

if ! sshd -t; then
    error "La configuracion SSH no supera la verificacion final."
    false
fi

if command -v systemctl >/dev/null 2>&1; then
    if ! systemctl is-active --quiet "$SERVICE"; then
        error "El servicio $SERVICE no esta activo."
        false
    fi
fi

CONFIG_CHANGED=0
trap - ERR

printf '\n'
line
printf '%b\n' "${GREEN}${BOLD}   OPERACION COMPLETADA${RESET}"
line
success "Autenticacion SSH de root por contraseña habilitada."
success "Configuracion validada correctamente."
success "Servicio SSH: $SERVICE"
info "Archivo administrado: $DROPIN"
info "Respaldo guardado en: $BACKUP_PATH"
printf '\n'
warn "El acceso root por contraseña aumenta el riesgo de ataques."
warn "Comprueba el acceso desde otra sesion SSH antes de cerrar la actual."
printf '\n'
