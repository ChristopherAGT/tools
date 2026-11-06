#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# ============================================================
#                         BHTTP FIX
# ============================================================

SERVICE="bhttp.service"
BINARY="/bin/BHTTP"

# ------------------------------------------------------------
# COLORS
# ------------------------------------------------------------

NAVY='\033[38;5;24m'
BLUE='\033[38;5;39m'
CYAN='\033[38;5;51m'
STEEL='\033[38;5;75m'
SILVER='\033[38;5;250m'
GREEN='\033[38;5;82m'
RED='\033[38;5;196m'
GRAY='\033[38;5;245m'
WHITE='\033[1;37m'
RESET='\033[0m'

# ------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------

err() {
    printf "\n${RED}✗ %s${RESET}\n" "$*" >&2
}

show_title() {
    local TITLE_WIDTH=9
    local TERM_WIDTH
    local PADDING

    TERM_WIDTH=$(tput cols 2>/dev/null || printf '%s' "${COLUMNS:-80}")

    [[ "$TERM_WIDTH" =~ ^[0-9]+$ ]] || TERM_WIDTH=80

    PADDING=$(( (TERM_WIDTH - TITLE_WIDTH) / 2 ))
    (( PADDING < 0 )) && PADDING=0

    printf "\n%*s" "$PADDING" ""
    printf "${BLUE}BHTTP${RESET} ${WHITE}FIX${RESET}\n\n"
}

TEMP_FILE=""
CHECK_DIR=""
LOG=""

cleanup() {
    [[ -n "$TEMP_FILE" && -f "$TEMP_FILE" ]] && rm -f "$TEMP_FILE"
    [[ -n "$CHECK_DIR" && -d "$CHECK_DIR" ]] && rm -rf "$CHECK_DIR"
    [[ -n "$LOG" && -f "$LOG" ]] && rm -f "$LOG"
}

trap cleanup EXIT

clear 2>/dev/null || true

show_title

# ------------------------------------------------------------
# SPINNER
# ------------------------------------------------------------

run_repair() {
    local PID
    local STATUS
    local FRAME=0

    local -a FRAMES=(
        "● ○ ○ ○ ○ ○"
        "○ ● ○ ○ ○ ○"
        "○ ○ ● ○ ○ ○"
        "○ ○ ○ ● ○ ○"
        "○ ○ ○ ○ ● ○"
        "○ ○ ○ ○ ○ ●"
    )

    LOG=$(mktemp)

    (
        set -Eeuo pipefail

        systemd-analyze verify "$CHECK_DIR/$SERVICE"

        systemctl stop "$SERVICE"

        if ! mv -f "$TEMP_FILE" "$UNIT"; then
            systemctl start "$SERVICE" >/dev/null 2>&1 || true
            exit 1
        fi

        systemctl daemon-reload

        systemctl reset-failed "$SERVICE" >/dev/null 2>&1 || true

        systemctl restart "$SERVICE"

        sleep 2

        systemctl is-active --quiet "$SERVICE"

    ) >"$LOG" 2>&1 &

    PID=$!

    while kill -0 "$PID" 2>/dev/null; do
        printf "\r\033[K${CYAN}%s${RESET}" "${FRAMES[$FRAME]}"

        FRAME=$(( (FRAME + 1) % 6 ))

        sleep 0.12
    done

    if wait "$PID"; then
        printf "\r\033[K"
        rm -f "$LOG"
        LOG=""
        return 0
    else
        STATUS=$?

        printf "\r\033[K"

        err "No se pudo completar la reparación."

        if [[ -s "$LOG" ]]; then
            tail -n 8 "$LOG" >&2 || true
        fi

        journalctl -u "$SERVICE" -n 8 --no-pager 2>/dev/null || true

        return "$STATUS"
    fi
}

# ------------------------------------------------------------
# DEPENDENCIES
# ------------------------------------------------------------

if (( EUID != 0 )); then
    err "Ejecuta este script como root."
    exit 1
fi

for CMD in systemctl systemd-analyze awk grep; do
    command -v "$CMD" >/dev/null 2>&1 || {
        err "Dependencia no encontrada: $CMD"
        exit 1
    }
done

if [[ ! -x "$BINARY" ]]; then
    err "No se encontró el binario BHTTP."
    exit 1
fi

if ! systemctl cat "$SERVICE" >/dev/null 2>&1; then
    err "No se encontró el servicio BHTTP."
    exit 1
fi

UNIT=$(systemctl show "$SERVICE" -p FragmentPath --value)

if [[ -z "$UNIT" || ! -f "$UNIT" ]]; then
    err "No se encontró la configuración del servicio."
    exit 1
fi

DROPINS=$(systemctl show "$SERVICE" -p DropInPaths --value)

if [[ -n "$DROPINS" ]]; then
    err "El servicio tiene configuraciones adicionales."
    exit 1
fi

# ------------------------------------------------------------
# READ EXECSTART
# ------------------------------------------------------------

EXEC_COUNT=$(grep -Ec '^[[:space:]]*ExecStart[[:space:]]*=' "$UNIT" || true)

if [[ "$EXEC_COUNT" != "1" ]]; then
    err "ExecStart debe aparecer exactamente una vez."
    exit 1
fi

EXEC_LINE=$(grep -E '^[[:space:]]*ExecStart[[:space:]]*=' "$UNIT")

if [[ "$EXEC_LINE" == *'"'* || "$EXEC_LINE" == *"'"* || "$EXEC_LINE" == *'\'* ]]; then
    err "ExecStart contiene sintaxis especial no compatible."
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
# PARSE PARAMETERS
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

        "$BINARY"|/usr/bin/BHTTP|/usr/local/bin/BHTTP|BHTTP)
            if (( i != 0 )); then
                err "Ejecutable adicional detectado."
                exit 1
            fi
            ;;

        --port|-port)
            i=$((i + 1))

            (( i < ${#ARGS[@]} )) || {
                err "Falta el valor de --port."
                exit 1
            }

            (( SEEN_PORT == 0 )) || {
                err "Puerto antiguo duplicado."
                exit 1
            }

            OLD_PORT="${ARGS[$i]}"
            SEEN_PORT=1
            ;;

        --port=*|-port=*)
            (( SEEN_PORT == 0 )) || {
                err "Puerto antiguo duplicado."
                exit 1
            }

            OLD_PORT="${ARG#*=}"
            SEEN_PORT=1
            ;;

        --ssh|-ssh)
            i=$((i + 1))

            (( i < ${#ARGS[@]} )) || {
                err "Falta el valor de --ssh."
                exit 1
            }

            (( SEEN_SSH == 0 )) || {
                err "Redirección SSH duplicada."
                exit 1
            }

            OLD_SSH="${ARGS[$i]}"
            SEEN_SSH=1
            ;;

        --ssh=*|-ssh=*)
            (( SEEN_SSH == 0 )) || {
                err "Redirección SSH duplicada."
                exit 1
            }

            OLD_SSH="${ARG#*=}"
            SEEN_SSH=1
            ;;

        -listen|--listen)
            i=$((i + 1))

            (( i < ${#ARGS[@]} )) || {
                err "Falta el valor de -listen."
                exit 1
            }

            (( SEEN_LISTEN == 0 )) || {
                err "Parámetro -listen duplicado."
                exit 1
            }

            LISTEN="${ARGS[$i]}"
            SEEN_LISTEN=1
            ;;

        -listen=*|--listen=*)
            (( SEEN_LISTEN == 0 )) || {
                err "Parámetro -listen duplicado."
                exit 1
            }

            LISTEN="${ARG#*=}"
            SEEN_LISTEN=1
            ;;

        -target|--target)
            i=$((i + 1))

            (( i < ${#ARGS[@]} )) || {
                err "Falta el valor de -target."
                exit 1
            }

            (( SEEN_TARGET == 0 )) || {
                err "Parámetro -target duplicado."
                exit 1
            }

            TARGET="${ARGS[$i]}"
            SEEN_TARGET=1
            ;;

        -target=*|--target=*)
            (( SEEN_TARGET == 0 )) || {
                err "Parámetro -target duplicado."
                exit 1
            }

            TARGET="${ARG#*=}"
            SEEN_TARGET=1
            ;;

        -bhttp-v2-max-lanes|-session-timeout|-tls-cert|-tls-key|-xhttp-listen)
            i=$((i + 1))

            (( i < ${#ARGS[@]} )) || {
                err "Falta el valor de $ARG."
                exit 1
            }

            EXTRA+=("$ARG" "${ARGS[$i]}")
            ;;

        -bhttp-v2-max-lanes=*|-session-timeout=*|-tls-cert=*|-tls-key=*|-xhttp-listen=*)
            EXTRA+=("$ARG")
            ;;

        -*)
            err "Parámetro no compatible: $ARG"
            exit 1
            ;;

        *)
            err "Argumento inesperado: $ARG"
            exit 1
            ;;
    esac

    i=$((i + 1))
done

# ------------------------------------------------------------
# NORMALIZE CONFIGURATION
# ------------------------------------------------------------

if (( SEEN_LISTEN == 1 && SEEN_PORT == 1 )); then
    err "Se detectaron dos configuraciones de escucha."
    exit 1
fi

if [[ -z "$LISTEN" ]]; then
    if [[ -n "$OLD_PORT" ]]; then
        LISTEN="0.0.0.0:$OLD_PORT"
    else
        LISTEN="0.0.0.0:80"
    fi
fi

if (( SEEN_TARGET == 1 && SEEN_SSH == 1 )); then
    err "Se detectaron dos configuraciones de redirección."
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
# VALIDATION
# ------------------------------------------------------------

valid_port() {
    local P="$1"

    [[ "$P" =~ ^[0-9]{1,5}$ ]] || return 1

    (( 10#$P >= 1 && 10#$P <= 65535 ))
}

if [[ -n "$OLD_PORT" ]] && ! valid_port "$OLD_PORT"; then
    err "Puerto de escucha antiguo inválido."
    exit 1
fi

if [[ -n "$OLD_SSH" ]] && ! valid_port "$OLD_SSH"; then
    err "Puerto SSH antiguo inválido."
    exit 1
fi

if [[ "$TARGET" =~ ^(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9._-]+):([0-9]{1,5})$ ]]; then
    TARGET_PORT="${BASH_REMATCH[2]}"
else
    err "Formato de redirección inválido."
    exit 1
fi

if ! valid_port "$TARGET_PORT"; then
    err "Puerto de redirección fuera de rango."
    exit 1
fi

if [[ -z "$LISTEN" || "$LISTEN" == *[[:space:]]* ]]; then
    err "Formato de escucha inválido."
    exit 1
fi

if [[ "$LISTEN" == ,* || "$LISTEN" == *, || "$LISTEN" == *,,* ]]; then
    err "Lista de listeners inválida."
    exit 1
fi

IFS=',' read -r -a LISTENERS <<< "$LISTEN"

for LISTENER in "${LISTENERS[@]}"; do

    if [[ "$LISTENER" =~ ^(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9._*-]*):([0-9]{1,5})$ ]]; then
        PORT="${BASH_REMATCH[2]}"
    else
        err "Formato de listener inválido."
        exit 1
    fi

    if ! valid_port "$PORT"; then
        err "Puerto de escucha fuera de rango."
        exit 1
    fi

done

for ARG in "${EXTRA[@]}"; do
    if [[ ! "$ARG" =~ ^[-A-Za-z0-9_./:+,@=-]+$ ]]; then
        err "Parámetro adicional no compatible."
        exit 1
    fi
done

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
# PREPARE CONFIGURATION
# ------------------------------------------------------------

TEMP_FILE=$(mktemp "${UNIT}.XXXXXX")

if ! awk -v replacement="$NEW_EXEC" '
    /^[[:space:]]*ExecStart[[:space:]]*=/ {
        print "ExecStart=" replacement
        next
    }
    { print }
' "$UNIT" > "$TEMP_FILE"; then
    err "No se pudo preparar la configuración."
    exit 1
fi

chown --reference="$UNIT" "$TEMP_FILE"
chmod --reference="$UNIT" "$TEMP_FILE"

CHECK_DIR=$(mktemp -d)

cp "$TEMP_FILE" "$CHECK_DIR/$SERVICE"

# ------------------------------------------------------------
# EXECUTION
# ------------------------------------------------------------

if ! run_repair; then
    err "BHTTP no pudo completar la reparación."
    exit 1
fi

TEMP_FILE=""

# ------------------------------------------------------------
# FINAL RESULT
# ------------------------------------------------------------

clear 2>/dev/null || true

show_title

printf "  ${GRAY}Puerto Configurado:${RESET}       ${CYAN}%s${RESET}\n" \
    "${LISTENERS[0]##*:}"

printf "  ${GRAY}Puerto de Redirección:${RESET}    ${CYAN}%s${RESET}\n" \
    "$TARGET_PORT"

printf "\n"

SUCCESS_TEXT="BHTTP FUNCIONANDO CORRECTEMENTE"
TERM_WIDTH=$(tput cols 2>/dev/null || printf '%s' "${COLUMNS:-80}")
[[ "$TERM_WIDTH" =~ ^[0-9]+$ ]] || TERM_WIDTH=80

PADDING=$(( (TERM_WIDTH - ${#SUCCESS_TEXT}) / 2 ))
(( PADDING < 0 )) && PADDING=0

printf "%*s${GREEN}${WHITE}%s${RESET}\n" \
    "$PADDING" "" "$SUCCESS_TEXT"

printf "\n"
