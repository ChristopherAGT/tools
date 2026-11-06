
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# ============================================================
#                 BHTTP AUTO REPAIR
#                      EPRO DEV
# ============================================================

SERVICE="bhttp.service"
UNIT="/etc/systemd/system/$SERVICE"
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

info() { echo -e "${CYAN}●${RESET} $*"; }
ok()   { echo -e "${GREEN}✓${RESET} $*"; }
warn() { echo -e "${YELLOW}!${RESET} $*"; }
err()  { echo -e "${RED}✗${RESET} $*" >&2; }

TEMP_FILE=""
BACKUP=""
REPAIRED=0

cleanup() {
    [[ -n "$TEMP_FILE" && -f "$TEMP_FILE" ]] && rm -f "$TEMP_FILE"
}
trap cleanup EXIT

clear 2>/dev/null || true

echo
echo -e "${CYAN}             BHTTP AUTO REPAIR${RESET}"
echo -e "${GRAY}                  EPRO DEV${RESET}"
echo

# ------------------------------------------------------------
# VALIDATIONS
# ------------------------------------------------------------

if (( EUID != 0 )); then
    err "Este script requiere permisos root."
    exit 1
fi

for CMD in systemctl systemd-analyze python3 ss awk grep cp; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        err "Dependencia no encontrada: $CMD"
        exit 1
    fi
done

if [[ ! -f "$UNIT" ]]; then
    err "No se encontró el servicio $UNIT"
    exit 1
fi

if [[ ! -x "$BINARY" ]]; then
    err "No se encontró el ejecutable $BINARY"
    exit 1
fi

if ! systemctl cat "$SERVICE" >/dev/null 2>&1; then
    err "No se pudo identificar el servicio."
    exit 1
fi

# ------------------------------------------------------------
# READ EXECSTART
# ------------------------------------------------------------

EXEC_LINE=$(awk '
    /^[[:space:]]*ExecStart[[:space:]]*=/ {
        sub(/^[[:space:]]*/, "")
        print
        exit
    }
' "$UNIT")

if [[ -z "$EXEC_LINE" ]]; then
    err "No se encontró ExecStart."
    exit 1
fi

# ------------------------------------------------------------
# PARSE SYSTEMD COMMAND
# ------------------------------------------------------------

declare -a ARGS=()
declare -a EXTRA=()
declare -a NEW_ARGS=()

if ! python3 - "$EXEC_LINE" > /tmp/bhttp-args.$$ <<'PY'
import sys
import shlex

line = sys.argv[1]
line = line.split("=", 1)[1]

try:
    args = shlex.split(line)
except ValueError as e:
    print("Error al interpretar ExecStart:", e, file=sys.stderr)
    sys.exit(1)

for arg in args:
    sys.stdout.buffer.write(arg.encode() + b"\0")
PY
then
    err "No se pudieron interpretar los argumentos."
    exit 1
fi

mapfile -d '' -t ARGS < "/tmp/bhttp-args.$$"
rm -f "/tmp/bhttp-args.$$"

if (( ${#ARGS[@]} == 0 )); then
    err "ExecStart está vacío."
    exit 1
fi

# ------------------------------------------------------------
# DETECT PARAMETERS
# ------------------------------------------------------------

LISTEN=""
TARGET=""
OLD_PORT=""
OLD_SSH=""

i=0

while (( i < ${#ARGS[@]} )); do

    ARG="${ARGS[$i]}"

    case "$ARG" in

        /bin/BHTTP|/usr/bin/BHTTP|BHTTP)
            ;;

        --port|-port)
            ((i+=1))
            OLD_PORT="${ARGS[$i]:-}"
            ;;

        --port=*|-port=*)
            OLD_PORT="${ARG#*=}"
            ;;

        --ssh|-ssh)
            ((i+=1))
            OLD_SSH="${ARGS[$i]:-}"
            ;;

        --ssh=*|-ssh=*)
            OLD_SSH="${ARG#*=}"
            ;;

        -listen|--listen)
            ((i+=1))
            LISTEN="${ARGS[$i]:-}"
            ;;

        -listen=*|--listen=*)
            LISTEN="${ARG#*=}"
            ;;

        -target|--target)
            ((i+=1))
            TARGET="${ARGS[$i]:-}"
            ;;

        -target=*|--target=*)
            TARGET="${ARG#*=}"
            ;;

        *)
            EXTRA+=("$ARG")
            ;;

    esac

    ((i+=1))

done

# ------------------------------------------------------------
# DETECT LISTEN PORT
# ------------------------------------------------------------

if [[ -z "$LISTEN" ]]; then

    if [[ -n "$OLD_PORT" ]]; then
        LISTEN="0.0.0.0:$OLD_PORT"
    else
        LISTEN="0.0.0.0:80"
    fi

fi

# ------------------------------------------------------------
# DETECT REDIRECTION
# ------------------------------------------------------------

if [[ -z "$TARGET" ]]; then

    if [[ -n "$OLD_SSH" ]]; then
        TARGET="127.0.0.1:$OLD_SSH"
    else
        TARGET="127.0.0.1:22"
    fi

fi

# ------------------------------------------------------------
# VALIDATE PARAMETERS
# ------------------------------------------------------------

if [[ ! "$TARGET" =~ ^[^[:space:]]+:[0-9]+$ ]]; then
    err "Destino SSH inválido: $TARGET"
    exit 1
fi

TARGET_PORT="${TARGET##*:}"

if (( TARGET_PORT < 1 || TARGET_PORT > 65535 )); then
    err "Puerto SSH fuera de rango."
    exit 1
fi

if [[ ! "$LISTEN" =~ ^[a-zA-Z0-9.:,\[\]]+$ ]]; then
    err "Formato de escucha inválido."
    exit 1
fi

IFS=',' read -r -a LISTENERS <<< "$LISTEN"

if (( ${#LISTENERS[@]} == 0 )); then
    err "No se detectaron listeners."
    exit 1
fi

for LISTENER in "${LISTENERS[@]}"; do

    if [[ ! "$LISTENER" =~ :([0-9]+)$ ]]; then
        err "Listener inválido: $LISTENER"
        exit 1
    fi

    PORT="${BASH_REMATCH[1]}"

    if (( PORT < 1 || PORT > 65535 )); then
        err "Puerto de escucha inválido: $PORT"
        exit 1
    fi

done

# ------------------------------------------------------------
# VALIDATE EXTRA ARGUMENTS
# ------------------------------------------------------------

HELP_OUTPUT=$("$BINARY" --help 2>&1 || true)

for ARG in "${EXTRA[@]}"; do

    case "$ARG" in
        -*)
            FLAG="${ARG%%=*}"

            if ! grep -Fq -- "$FLAG" <<< "$HELP_OUTPUT"; then
                err "Parámetro no compatible con el binario: $FLAG"
                exit 1
            fi
            ;;
    esac

done

# ------------------------------------------------------------
# DISPLAY CONFIGURATION
# ------------------------------------------------------------

echo -e "${WHITE}CONFIGURACIÓN DETECTADA${RESET}"
echo

echo -e "  Servicio:             ${CYAN}$SERVICE${RESET}"
echo -e "  Ejecutable:           ${CYAN}$BINARY${RESET}"
echo -e "  Escucha:              ${CYAN}$LISTEN${RESET}"
echo -e "  Redirección SSH:      ${CYAN}$TARGET${RESET}"
echo -e "  Listeners:            ${CYAN}${#LISTENERS[@]}${RESET}"

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

# Build a systemd-compatible command line.
# Values containing special characters are double-quoted.

quote_systemd() {
    local VALUE="$1"

    if [[ "$VALUE" =~ [[:space:]\"\\] ]]; then
        VALUE=${VALUE//\\/\\\\}
        VALUE=${VALUE//\"/\\\"}
        printf '"%s"' "$VALUE"
    else
        printf '%s' "$VALUE"
    fi
}

NEW_EXEC=""

for ARG in "${NEW_ARGS[@]}"; do
    QUOTED=$(quote_systemd "$ARG")
    NEW_EXEC+="${NEW_EXEC:+ }$QUOTED"
done

# ------------------------------------------------------------
# CREATE BACKUP
# ------------------------------------------------------------

mkdir -p "$BACKUP_DIR"

BACKUP="$BACKUP_DIR/bhttp-$(date +%Y%m%d-%H%M%S).service"

if [[ -e "$BACKUP" ]]; then
    err "El respaldo ya existe. Intenta nuevamente."
    exit 1
fi

cp -a "$UNIT" "$BACKUP"

ok "Respaldo original creado."

# ------------------------------------------------------------
# PREPARE TEMPORARY UNIT
# ------------------------------------------------------------

TEMP_FILE=$(mktemp "${UNIT}.XXXXXX")

awk -v replacement="$NEW_EXEC" '
    BEGIN { replaced=0 }

    /^[[:space:]]*ExecStart[[:space:]]*=/ {
        if (!replaced) {
            print "ExecStart=" replacement
            replaced=1
            next
        }
    }

    { print }

    END {
        if (!replaced) exit 1
    }
' "$UNIT" > "$TEMP_FILE" || {
    err "No se pudo generar el servicio."
    exit 1
}

chmod --reference="$UNIT" "$TEMP_FILE"

# ------------------------------------------------------------
# VALIDATE SYSTEMD UNIT
# ------------------------------------------------------------

if ! systemd-analyze verify "$TEMP_FILE" 2>&1; then
    err "Systemd rechazó la configuración."
    exit 1
fi

# ------------------------------------------------------------
# APPLY REPAIR
# ------------------------------------------------------------

info "Aplicando reparación..."

systemctl stop "$SERVICE"

if ! cat "$TEMP_FILE" > "$UNIT"; then
    err "No se pudo actualizar el servicio."
    cp -a "$BACKUP" "$UNIT"
    systemctl daemon-reload
    exit 1
fi

REPAIRED=1

rm -f "$TEMP_FILE"
TEMP_FILE=""

systemctl daemon-reload

# ------------------------------------------------------------
# RESTART
# ------------------------------------------------------------

info "Reiniciando BHTTP..."

systemctl reset-failed "$SERVICE" || true

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
    echo -e "${WHITE}ESTADO DEL SERVICIO${RESET}"

    systemctl status "$SERVICE" --no-pager -l

    echo
    echo -e "${WHITE}PUERTOS DE ESCUCHA${RESET}"

    ss -lntp | grep -F 'BHTTP' || true

    echo
    ok "Reparación completada."
    info "Respaldo: $BACKUP"

else

    err "BHTTP no consiguió mantenerse activo."

    echo
    journalctl -u "$SERVICE" -n 30 --no-pager

    echo
    warn "Revisa los registros antes de realizar otros cambios."
    warn "Respaldo original: $BACKUP"

    exit 1

fi

echo
echo -e "${GRAY}SCRIPT BY. ChristopherAGT${RESET}"
echo

