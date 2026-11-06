
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# ============================================================
#                 BHTTP AUTO REPAIR
#                      EPRO DEV
# ============================================================

SERVICE="bhttp.service"
BINARY="/bin/BHTTP"
BACKUP_DIR="/var/backups/bhttp-auto-repair"

CYAN='\033[38;5;51m'
BLUE='\033[38;5;39m'
GREEN='\033[38;5;82m'
YELLOW='\033[38;5;220m'
RED='\033[38;5;196m'
WHITE='\033[1;37m'
GRAY='\033[38;5;245m'
RESET='\033[0m'

info() { printf "${CYAN}●${RESET} %s\n" "$*"; }
ok()   { printf "${GREEN}✓${RESET} %s\n" "$*"; }
warn() { printf "${YELLOW}!${RESET} %s\n" "$*"; }
err()  { printf "${RED}✗${RESET} %s\n" "$*" >&2; }

TEMP_FILE=""
CHECK_DIR=""
BACKUP=""

cleanup() {
    [[ -n "$TEMP_FILE" && -f "$TEMP_FILE" ]] && rm -f "$TEMP_FILE"
    [[ -n "$CHECK_DIR" && -d "$CHECK_DIR" ]] && rm -rf "$CHECK_DIR"
}
trap cleanup EXIT

clear 2>/dev/null || true

echo
printf "${CYAN}             BHTTP AUTO REPAIR${RESET}\n"
printf "${GRAY}                  EPRO DEV${RESET}\n"
echo

# ------------------------------------------------------------
# DEPENDENCIES
# ------------------------------------------------------------

if (( EUID != 0 )); then
    err "Este script requiere permisos root."
    exit 1
fi

for CMD in systemctl systemd-analyze awk grep cp ss journalctl; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        err "Dependencia no encontrada: $CMD"
        exit 1
    fi
done

if [[ ! -x "$BINARY" ]]; then
    err "No se encontró el ejecutable $BINARY."
    exit 1
fi

if ! systemctl cat "$SERVICE" >/dev/null 2>&1; then
    err "No se pudo identificar $SERVICE."
    exit 1
fi

UNIT=$(systemctl show "$SERVICE" -p FragmentPath --value)

if [[ -z "$UNIT" || ! -f "$UNIT" ]]; then
    err "No se encontró el archivo principal de la unidad."
    exit 1
fi

# ------------------------------------------------------------
# CHECK DROP-INS
# ------------------------------------------------------------

DROPINS=$(systemctl show "$SERVICE" -p DropInPaths --value)

if [[ -n "$DROPINS" ]]; then
    err "Se detectaron archivos drop-in que pueden sobrescribir ExecStart."
    printf '%s\n' "$DROPINS"
    warn "No se modificó ningún archivo."
    exit 1
fi

# ------------------------------------------------------------
# READ EXECSTART
# ------------------------------------------------------------

EXEC_COUNT=$(grep -Ec '^[[:space:]]*ExecStart[[:space:]]*=' "$UNIT" || true)

if [[ "$EXEC_COUNT" != "1" ]]; then
    err "Se esperaba exactamente una línea ExecStart; encontradas: $EXEC_COUNT."
    exit 1
fi

EXEC_LINE=$(grep -E '^[[:space:]]*ExecStart[[:space:]]*=' "$UNIT")

# Se rechaza sintaxis compleja para no interpretar incorrectamente
# comillas, escapes o expansiones propias de systemd.
if [[ "$EXEC_LINE" == *'"'* || "$EXEC_LINE" == *"'"* || "$EXEC_LINE" == *'\'* ]]; then
    err "ExecStart contiene comillas o escapes especiales."
    warn "Se requiere revisar su sintaxis antes de modificarlo."
    exit 1
fi

COMMAND=${EXEC_LINE#*=}
COMMAND="${COMMAND#"${COMMAND%%[![:space:]]*}"}"

declare -a ARGS=()
declare -a EXTRA=()
declare -a NEW_ARGS=()

read -r -a ARGS <<< "$COMMAND"

if (( ${#ARGS[@]} == 0 )); then
    err "ExecStart está vacío."
    exit 1
fi

# ------------------------------------------------------------
# PARSE ARGUMENTS
# ------------------------------------------------------------

LISTEN=""
TARGET=""
OLD_PORT=""
OLD_SSH=""

SEEN_LISTEN=0
SEEN_TARGET=0
SEEN_PORT=0
SEEN_SSH=0

i=0

while (( i < ${#ARGS[@]} )); do

    ARG="${ARGS[$i]}"

    case "$ARG" in

        "$BINARY"|/usr/bin/BHTTP|BHTTP)
            if (( i != 0 )); then
                err "Ejecutable adicional detectado en ExecStart."
                exit 1
            fi
            ;;

        --port|-port)
            i=$((i + 1))

            if (( i >= ${#ARGS[@]} )); then
                err "Falta el valor de --port."
                exit 1
            fi

            if (( SEEN_PORT == 1 )); then
                err "El puerto antiguo está duplicado."
                exit 1
            fi

            OLD_PORT="${ARGS[$i]}"
            SEEN_PORT=1
            ;;

        --port=*|-port=*)
            if (( SEEN_PORT == 1 )); then
                err "El puerto antiguo está duplicado."
                exit 1
            fi

            OLD_PORT="${ARG#*=}"
            SEEN_PORT=1
            ;;

        --ssh|-ssh)
            i=$((i + 1))

            if (( i >= ${#ARGS[@]} )); then
                err "Falta el valor de --ssh."
                exit 1
            fi

            if (( SEEN_SSH == 1 )); then
                err "La redirección SSH antigua está duplicada."
                exit 1
            fi

            OLD_SSH="${ARGS[$i]}"
            SEEN_SSH=1
            ;;

        --ssh=*|-ssh=*)
            if (( SEEN_SSH == 1 )); then
                err "La redirección SSH antigua está duplicada."
                exit 1
            fi

            OLD_SSH="${ARG#*=}"
            SEEN_SSH=1
            ;;

        -listen|--listen)
            i=$((i + 1))

            if (( i >= ${#ARGS[@]} )); then
                err "Falta el valor de -listen."
                exit 1
            fi

            if (( SEEN_LISTEN == 1 )); then
                err "El parámetro -listen está duplicado."
                exit 1
            fi

            LISTEN="${ARGS[$i]}"
            SEEN_LISTEN=1
            ;;

        -listen=*|--listen=*)
            if (( SEEN_LISTEN == 1 )); then
                err "El parámetro -listen está duplicado."
                exit 1
            fi

            LISTEN="${ARG#*=}"
            SEEN_LISTEN=1
            ;;

        -target|--target)
            i=$((i + 1))

            if (( i >= ${#ARGS[@]} )); then
                err "Falta el valor de -target."
                exit 1
            fi

            if (( SEEN_TARGET == 1 )); then
                err "El parámetro -target está duplicado."
                exit 1
            fi

            TARGET="${ARGS[$i]}"
            SEEN_TARGET=1
            ;;

        -target=*|--target=*)
            if (( SEEN_TARGET == 1 )); then
                err "El parámetro -target está duplicado."
                exit 1
            fi

            TARGET="${ARG#*=}"
            SEEN_TARGET=1
            ;;

        -bhttp-v2-max-lanes|-session-timeout|-tls-cert|-tls-key|-xhttp-listen)
            i=$((i + 1))

            if (( i >= ${#ARGS[@]} )); then
                err "Falta el valor del parámetro $ARG."
                exit 1
            fi

            EXTRA+=("$ARG" "${ARGS[$i]}")
            ;;

        -bhttp-v2-max-lanes=*|-session-timeout=*|-tls-cert=*|-tls-key=*|-xhttp-listen=*)
            EXTRA+=("$ARG")
            ;;

        -*)
            err "Parámetro no reconocido: $ARG"
            warn "No se modificó el servicio para evitar perder opciones."
            exit 1
            ;;

        *)
            err "Argumento inesperado en ExecStart: $ARG"
            exit 1
            ;;
    esac

    i=$((i + 1))
done

# ------------------------------------------------------------
# NORMALIZE LISTEN
# ------------------------------------------------------------

if (( SEEN_LISTEN == 1 && SEEN_PORT == 1 )); then
    err "Se encontraron simultáneamente -listen y --port."
    exit 1
fi

if [[ -z "$LISTEN" ]]; then
    if [[ -n "$OLD_PORT" ]]; then
        LISTEN="0.0.0.0:$OLD_PORT"
    else
        # Listener explícito para evitar el puerto 53 predeterminado.
        LISTEN="0.0.0.0:80"
    fi
fi

# ------------------------------------------------------------
# NORMALIZE TARGET
# ------------------------------------------------------------

if (( SEEN_TARGET == 1 && SEEN_SSH == 1 )); then
    err "Se encontraron simultáneamente -target y --ssh."
    exit 1
fi

if [[ -z "$TARGET" ]]; then
    if [[ -n "$OLD_SSH" ]]; then
        TARGET="127.0.0.1:$OLD_SSH"
    else
        TARGET="127.0.0.1:22"
    fi
fi

# ------------------------------------------------------------
# VALIDATE PORT
# ------------------------------------------------------------

valid_port() {
    local P="$1"

    [[ "$P" =~ ^[0-9]{1,5}$ ]] || return 1
    (( 10#$P >= 1 && 10#$P <= 65535 ))
}

if [[ -n "$OLD_PORT" ]] && ! valid_port "$OLD_PORT"; then
    err "Puerto antiguo inválido: $OLD_PORT"
    exit 1
fi

if [[ -n "$OLD_SSH" ]] && ! valid_port "$OLD_SSH"; then
    err "Puerto SSH antiguo inválido: $OLD_SSH"
    exit 1
fi

# ------------------------------------------------------------
# VALIDATE TARGET
# ------------------------------------------------------------

if [[ "$TARGET" =~ ^(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9._-]+):([0-9]{1,5})$ ]]; then
    TARGET_PORT="${BASH_REMATCH[2]}"
else
    err "Formato de destino inválido: $TARGET"
    exit 1
fi

if ! valid_port "$TARGET_PORT"; then
    err "Puerto de redirección fuera de rango."
    exit 1
fi

# ------------------------------------------------------------
# VALIDATE LISTENERS
# ------------------------------------------------------------

if [[ -z "$LISTEN" || "$LISTEN" == *[[:space:]]* ]]; then
    err "Formato de escucha inválido: $LISTEN"
    exit 1
fi

if [[ "$LISTEN" == ,* || "$LISTEN" == *, || "$LISTEN" == *,,* ]]; then
    err "La lista de listeners contiene separadores vacíos."
    exit 1
fi

IFS=',' read -r -a LISTENERS <<< "$LISTEN"

if (( ${#LISTENERS[@]} == 0 )); then
    err "No se detectaron listeners."
    exit 1
fi

for LISTENER in "${LISTENERS[@]}"; do

    if [[ "$LISTENER" =~ ^(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9._-]*):([0-9]{1,5})$ ]]; then
        PORT="${BASH_REMATCH[2]}"
    else
        err "Listener inválido: $LISTENER"
        exit 1
    fi

    if ! valid_port "$PORT"; then
        err "Puerto de escucha fuera de rango: $PORT"
        exit 1
    fi

done

# ------------------------------------------------------------
# VALIDATE EXTRA ARGUMENTS
# ------------------------------------------------------------

for ARG in "${EXTRA[@]}"; do
    if [[ ! "$ARG" =~ ^[-A-Za-z0-9_./:+,@=-]+$ ]]; then
        err "Argumento adicional contiene caracteres no admitidos: $ARG"
        exit 1
    fi
done

# ------------------------------------------------------------
# DISPLAY CONFIGURATION
# ------------------------------------------------------------

echo
printf "${WHITE}CONFIGURACIÓN DETECTADA${RESET}\n\n"

printf "  Servicio:             ${CYAN}%s${RESET}\n" "$SERVICE"
printf "  Ejecutable:           ${CYAN}%s${RESET}\n" "$BINARY"
printf "  Escucha:              ${CYAN}%s${RESET}\n" "$LISTEN"
printf "  Redirección SSH:      ${CYAN}%s${RESET}\n" "$TARGET"
printf "  Listeners:            ${CYAN}%s${RESET}\n" "${#LISTENERS[@]}"

echo

# ------------------------------------------------------------
# BUILD EXECSTART
# ------------------------------------------------------------

NEW_ARGS=(
    "$BINARY"
    "-listen"
    "$LISTEN"
    "-target"
    "$TARGET"
)

NEW_ARGS+=("${EXTRA[@]}")

NEW_EXEC=""

for ARG in "${NEW_ARGS[@]}"; do
    NEW_EXEC+="${NEW_EXEC:+ }$ARG"
done

# ------------------------------------------------------------
# CREATE BACKUP
# ------------------------------------------------------------

mkdir -p "$BACKUP_DIR"

BACKUP="$BACKUP_DIR/bhttp-$(date +%Y%m%d-%H%M%S)-$$.service"

if ! cp -a "$UNIT" "$BACKUP"; then
    err "No se pudo crear el respaldo."
    exit 1
fi

ok "Respaldo original creado."

# ------------------------------------------------------------
# PREPARE TEMPORARY UNIT
# ------------------------------------------------------------

TEMP_FILE=$(mktemp "${UNIT}.XXXXXX")

if ! awk -v replacement="$NEW_EXEC" '
    /^[[:space:]]*ExecStart[[:space:]]*=/ {
        print "ExecStart=" replacement
        next
    }
    { print }
' "$UNIT" > "$TEMP_FILE"; then
    err "No se pudo generar la unidad temporal."
    exit 1
fi

chown --reference="$UNIT" "$TEMP_FILE"
chmod --reference="$UNIT" "$TEMP_FILE"

# ------------------------------------------------------------
# VALIDATE SYSTEMD UNIT
# ------------------------------------------------------------

CHECK_DIR=$(mktemp -d)

cp "$TEMP_FILE" "$CHECK_DIR/bhttp.service"

if ! systemd-analyze verify "$CHECK_DIR/bhttp.service"; then
    err "Systemd rechazó la configuración."
    exit 1
fi

# ------------------------------------------------------------
# APPLY REPAIR
# ------------------------------------------------------------

info "Aplicando reparación..."

if ! systemctl stop "$SERVICE"; then
    err "No se pudo detener el servicio."
    exit 1
fi

if ! mv -f "$TEMP_FILE" "$UNIT"; then
    err "No se pudo instalar la nueva configuración."
    systemctl start "$SERVICE" || true
    exit 1
fi

TEMP_FILE=""

if ! systemctl daemon-reload; then
    err "No se pudo recargar systemd. Restaurando respaldo."

    cp -a "$BACKUP" "$UNIT"
    systemctl daemon-reload || true
    systemctl start "$SERVICE" || true
    exit 1
fi

systemctl reset-failed "$SERVICE" || true

# ------------------------------------------------------------
# RESTART
# ------------------------------------------------------------

info "Reiniciando BHTTP..."

if ! systemctl restart "$SERVICE"; then

    err "BHTTP no pudo reiniciarse."

    echo
    journalctl -u "$SERVICE" -n 30 --no-pager

    echo
    warn "La configuración reparada se conserva."
    warn "Respaldo original: $BACKUP"

    exit 1
fi

sleep 2

# ------------------------------------------------------------
# FINAL VERIFICATION
# ------------------------------------------------------------

echo

if systemctl is-active --quiet "$SERVICE"; then

    ok "BHTTP está activo."

    echo
    printf "${WHITE}ESTADO DEL SERVICIO${RESET}\n\n"
    systemctl status "$SERVICE" --no-pager -l

    echo
    printf "${WHITE}PUERTOS TCP EN ESCUCHA${RESET}\n\n"
    ss -lntp

    echo
    ok "Reparación completada."
    info "Respaldo: $BACKUP"

else

    err "BHTTP no consiguió mantenerse activo."

    echo
    journalctl -u "$SERVICE" -n 30 --no-pager

    echo
    warn "La configuración reparada se conserva."
    warn "Respaldo original: $BACKUP"

    exit 1
fi

echo
printf "${GRAY}SCRIPT BY. ChristopherAGT${RESET}\n"
echo
