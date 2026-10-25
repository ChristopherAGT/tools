#!/usr/bin/env bash

# ============================================================
# SSH ROOT ACCESS | SECURE CONTROL
# Configuracion de autenticacion root por contraseña
# Compatible con Ubuntu / Debian
# ============================================================

set -Eeuo pipefail
umask 077

# ── PALETA DE COLORES ────────────────────────────────────────
RESET='\033[0m'
BOLD='\033[1m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
GRAY='\033[0;90m'

# ── CONFIGURACION ───────────────────────────────────────────
SSH_DIR="/etc/ssh"
SSH_CONFIG="$SSH_DIR/sshd_config"
DROPIN_DIR="$SSH_DIR/sshd_config.d"
DROPIN="$DROPIN_DIR/00-root-password-auth.conf"
BACKUP_DIR="/root/.ssh-root-auth-backups"
SERVICE="ssh"

SPINNER_PID=""
TEMP_LOG=""
BACKUP_FILE=""
HAD_PREVIOUS_DROPIN=0
CONFIG_APPLIED=0

# ── INTERFAZ ────────────────────────────────────────────────
line() {
    printf '%b\n' "${GRAY}────────────────────────────────────────────${RESET}"
}

header() {
    clear
    printf '\n%b\n' "${BLUE}${BOLD}   SSH ROOT ACCESS${RESET}"
    printf '%b\n' "${CYAN}   Configuracion segura de acceso SSH${RESET}"
    line
    printf '%b\n\n' "${GRAY}   Ubuntu / Debian · Administracion del servidor${RESET}"
}

success() { printf '  %b[OK]%b %s\n' "$GREEN" "$RESET" "$*"; }
info()    { printf '  %b[INFO]%b %s\n' "$CYAN" "$RESET" "$*"; }
warn()    { printf '  %b[AVISO]%b %s\n' "$YELLOW" "$RESET" "$*"; }
error()   { printf '  %b[ERROR]%b %s\n' "$RED" "$RESET" "$*"; }

pause_exit() {
    printf '\n%bPresiona ENTER para salir...%b' "$GRAY" "$RESET"
    read -r _ || true
}

# ── SPINNER ─────────────────────────────────────────────────
spinner() {
    local message="$1"
    shift

    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    local rc=0

    TEMP_LOG="$(mktemp /tmp/ssh-root-auth.XXXXXX)"

    "$@" >"$TEMP_LOG" 2>&1 &
    SPINNER_PID=$!

    while kill -0 "$SPINNER_PID" 2>/dev/null; do
        printf '\r  %b%s%b %s...' \
            "$CYAN" "${frames[i]}" "$RESET" "$message"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.10
    done

    wait "$SPINNER_PID" || rc=$?
    SPINNER_PID=""

    if (( rc == 0 )); then
        printf '\r  %b✓%b %-43s\n' "$GREEN" "$RESET" "$message"
        rm -f "$TEMP_LOG"
        TEMP_LOG=""
        return 0
    fi

    printf '\r  %b✗%b %-43s\n' "$RED" "$RESET" "$message"
    if [[ -s "$TEMP_LOG" ]]; then
        sed 's/^/    /' "$TEMP_LOG"
    fi

    rm -f "$TEMP_LOG"
    TEMP_LOG=""
    return "$rc"
}

# ── LIMPIEZA ────────────────────────────────────────────────
cleanup() {
    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" 2>/dev/null || true
    fi

    if [[ -n "$TEMP_LOG" ]]; then
        rm -f "$TEMP_LOG"
    fi
}
trap cleanup EXIT

# ── RESTAURACION DE CONFIGURACION ───────────────────────────
rollback_config() {
    warn "Restaurando la configuracion SSH anterior..."

    if (( HAD_PREVIOUS_DROPIN == 1 )); then
        if [[ -f "$BACKUP_FILE" ]]; then
            cp -a "$BACKUP_FILE" "$DROPIN" || {
                error "No se pudo restaurar el archivo anterior."
                return 1
            }
        fi
    else
        rm -f "$DROPIN" || {
            error "No se pudo retirar la configuracion nueva."
            return 1
        }
    fi

    if sshd -t; then
        if command -v systemctl >/dev/null 2>&1; then
            systemctl reload "$SERVICE" 2>/dev/null ||
                service "$SERVICE" reload 2>/dev/null || true
        else
            service "$SERVICE" reload 2>/dev/null || true
        fi
        success "Configuracion anterior restaurada."
    else
        error "La configuracion restaurada necesita revision manual."
        return 1
    fi
}

# ── VALIDACIONES INICIALES ──────────────────────────────────
header

if [[ "$(id -u)" -ne 0 ]]; then
    error "Debes ejecutar este script como root."
    printf '\n  Ejecuta: %bsudo -i%b\n\n' "$CYAN" "$RESET"
    exit 1
fi

if [[ ! -f "$SSH_CONFIG" ]]; then
    error "No se encontro $SSH_CONFIG."
    error "Comprueba que el servidor OpenSSH este instalado."
    exit 1
fi

if ! command -v sshd >/dev/null 2>&1; then
    error "No se encontro el comando sshd."
    error "Instala OpenSSH Server antes de continuar."
    exit 1
fi

if ! command -v chpasswd >/dev/null 2>&1; then
    error "No se encontro el comando chpasswd."
    exit 1
fi

if ! command -v systemctl >/dev/null 2>&1 &&
   ! command -v service >/dev/null 2>&1; then
    error "No se encontro un administrador del servicio SSH."
    exit 1
fi

if ! sshd -t; then
    error "La configuracion SSH actual contiene errores."
    error "No se realizo ningun cambio."
    exit 1
fi

mkdir -p "$DROPIN_DIR" "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# ── INFORMACION ─────────────────────────────────────────────
printf '%b\n' "${WHITE}${BOLD}  RESUMEN DE LA OPERACION${RESET}"
printf '  • Habilitar acceso SSH de root por contraseña\n'
printf '  • Validar la configuracion antes de aplicarla\n'
printf '  • Mantener intactas las reglas del firewall\n'
printf '  • No modificar DNS ni actualizar paquetes\n'
printf '  • Crear una copia de seguridad recuperable\n\n'

warn "El acceso de root por contraseña aumenta el riesgo de ataques."
warn "Asegurate de disponer de una contraseña robusta."
printf '\n'

read -r -p "  ¿Deseas continuar? [s/N]: " answer
case "$answer" in
    s|S|si|SI|Si|sí|Sí|sI) ;;
    *)
        info "Operacion cancelada. No se realizaron cambios."
        exit 0
        ;;
esac

# ── RESPALDO ────────────────────────────────────────────────
header
info "Preparando respaldo de la configuracion..."

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILE="$BACKUP_DIR/00-root-password-auth.conf.$STAMP.bak"

if [[ -e "$DROPIN" ]]; then
    cp -a "$DROPIN" "$BACKUP_FILE"
    HAD_PREVIOUS_DROPIN=1
    success "Configuracion anterior respaldada."
else
    HAD_PREVIOUS_DROPIN=0
    info "No existia el archivo de configuracion adicional."
fi

# ── CONFIGURACION SSH ───────────────────────────────────────
printf '\n'
info "Configurando autenticacion SSH..."

if ! cat > "$DROPIN" <<'EOF'
# Administracion de acceso root por contraseña
# Archivo administrado por SSH ROOT ACCESS
PermitRootLogin yes
PasswordAuthentication yes
EOF
then
    error "No se pudo escribir la configuracion SSH."
    rollback_config
    exit 1
fi

chmod 600 "$DROPIN"
CONFIG_APPLIED=1

if ! spinner "Validando configuracion SSH" sshd -t; then
    error "La configuracion no es valida."
    rollback_config
    exit 1
fi

# Comprueba los valores efectivos, no solo el contenido del archivo.
EFFECTIVE_CONFIG="$(sshd -T 2>/dev/null)" || {
    error "No se pudo consultar la configuracion efectiva de SSH."
    rollback_config
    exit 1
}

ROOT_LOGIN="$(awk '$1=="permitrootlogin" {print $2; exit}' <<< "$EFFECTIVE_CONFIG")"
PASSWORD_AUTH="$(awk '$1=="passwordauthentication" {print $2; exit}' <<< "$EFFECTIVE_CONFIG")"

if [[ "$ROOT_LOGIN" != "yes" || "$PASSWORD_AUTH" != "yes" ]]; then
    error "Otra directiva SSH esta impidiendo aplicar los valores requeridos."
    info "PermitRootLogin efectivo: ${ROOT_LOGIN:-desconocido}"
    info "PasswordAuthentication efectivo: ${PASSWORD_AUTH:-desconocido}"
    rollback_config
    exit 1
fi

success "Autenticacion root por contraseña configurada."

# ── RECARGA DEL SERVICIO ────────────────────────────────────
printf '\n'
info "Aplicando la configuracion..."

if command -v systemctl >/dev/null 2>&1 &&
   systemctl is-active --quiet "$SERVICE"; then
    if ! spinner "Recargando servicio SSH" systemctl reload "$SERVICE"; then
        warn "La recarga fallo; intentando reiniciar SSH..."
        if ! spinner "Reiniciando servicio SSH" systemctl restart "$SERVICE"; then
            error "No se pudo aplicar la configuracion al servicio."
            rollback_config
            exit 1
        fi
    fi
else
    if ! spinner "Reiniciando servicio SSH" service "$SERVICE" restart; then
        error "No se pudo reiniciar el servicio SSH."
        rollback_config
        exit 1
    fi
fi

success "Servicio SSH actualizado."

# ── CONTRASEÑA ROOT ─────────────────────────────────────────
printf '\n'
line
printf '%b\n' "${WHITE}${BOLD}  NUEVA CONTRASEÑA DE ROOT${RESET}"
line
printf '\n'
warn "La contraseña no se mostrara mientras escribes."
printf '\n'

while true; do
    senha=""
    confirmacao=""

    read -r -s -p "  Nueva contraseña: " senha
    printf '\n'

    if [[ -z "$senha" ]]; then
        error "La contraseña no puede estar vacia."
        continue
    fi

    if [[ "$senha" == *:* || "$senha" == *$'\n'* ]]; then
        error "La contraseña contiene caracteres no admitidos."
        unset senha
        continue
    fi

    read -r -s -p "  Confirmar contraseña: " confirmacao
    printf '\n'

    if [[ "$senha" != "$confirmacao" ]]; then
        error "Las contraseñas no coinciden. Intenta nuevamente."
        unset senha confirmacao
        continue
    fi

    unset confirmacao
    break
done

set_root_password() {
    printf 'root:%s\n' "$senha" | chpasswd
}

if ! spinner "Estableciendo contraseña de root" set_root_password; then
    unset senha
    error "No se pudo establecer la contraseña."
    warn "La configuracion SSH ya fue aplicada, pero la contraseña no se cambio."
    warn "Revisa el estado de la cuenta root antes de cerrar tu sesion."
    exit 1
fi

unset senha
success "Contraseña de root establecida."

# ── VERIFICACION FINAL ──────────────────────────────────────
printf '\n'
if ! sshd -t; then
    error "La verificacion final de SSH fallo."
    rollback_config
    exit 1
fi

if command -v systemctl >/dev/null 2>&1 &&
   systemctl is-active --quiet "$SERVICE"; then
    success "Servicio SSH activo."
else
    warn "No se pudo confirmar que SSH este activo."
fi

line
printf '%b\n' "${GREEN}${BOLD}  OPERACION COMPLETADA${RESET}"
printf '\n'
printf '  %bUsuario:%b       root\n' "$CYAN" "$RESET"
printf '  %bAutenticacion:%b contraseña SSH\n' "$CYAN" "$RESET"
printf '  %bRespaldo:%b      %s\n' "$CYAN" "$RESET" "$BACKUP_DIR"
printf '\n'
warn "Mantén abierta esta sesión hasta verificar otro acceso SSH."
warn "Confirma desde otra terminal que puedes conectarte correctamente."
line
printf '\n'
