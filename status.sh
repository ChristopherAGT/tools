#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# ============================================================
#                       BHTTP FIX
#                 AUTOMATIC SERVICE REPAIR
# ============================================================

SERVICE="bhttp.service"
BINARY="/bin/BHTTP"
BACKUP_DIR="/var/backups/bhttp-auto-repair"

# ------------------------------------------------------------
# COLORS
# ------------------------------------------------------------

NAVY='\033[38;5;24m'
BLUE='\033[38;5;39m'
CYAN='\033[38;5;51m'
STEEL='\033[38;5;75m'
SILVER='\033[38;5;250m'
GOLD='\033[38;5;220m'
GREEN='\033[38;5;82m'
RED='\033[38;5;196m'
GRAY='\033[38;5;245m'
WHITE='\033[1;37m'
RESET='\033[0m'

info() { printf "${CYAN}●${RESET} %s\n" "$*"; }
ok()   { printf "${GREEN}✓${RESET} %s\n" "$*"; }
warn() { printf "${GOLD}!${RESET} %s\n" "$*"; }
err()  { printf "${RED}✗${RESET} %s\n" "$*" >&2; }

TEMP_FILE=""
CHECK_DIR=""
BACKUP=""

# ------------------------------------------------------------
# CLEANUP
# ------------------------------------------------------------

cleanup() {
    [[ -n "$TEMP_FILE" && -f "$TEMP_FILE" ]] && rm -f "$TEMP_FILE"
    [[ -n "$CHECK_DIR" && -d "$CHECK_DIR" ]] && rm -rf "$CHECK_DIR"
}
trap cleanup EXIT

clear 2>/dev/null || true

# ------------------------------------------------------------
# HEADER
# ------------------------------------------------------------

echo
printf "${BLUE}                    BHTTP${RESET} ${WHITE}FIX${RESET}\n"
printf "${GRAY}             AUTOMATIC SERVICE REPAIR${RESET}\n"
echo
printf "${STEEL}────────────────────────────────────────${RESET}\n"
echo

# ------------------------------------------------------------
# SPINNER
# ------------------------------------------------------------

run_step() {
    local LABEL="$1"
    shift

    local LOG
    local PID
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

    "$@" >"$LOG" 2>&1 &
    PID=$!

    while kill -0 "$PID" 2>/dev/null; do
        printf "\r\033[K${BLUE}%s${RESET} ${CYAN}%s${RESET}" \
            "$LABEL" "${FRAMES[$FRAME]}"

        FRAME=$(( (FRAME + 1) % 6 ))
        sleep 0.12
    done

    if wait "$PID"; then
        printf "\r\033[K${GREEN}✓${RESET} %s\n" "$LABEL"
        rm -f "$LOG"
        return 0
    else
        printf "\r\033[K${RED}✗${RESET} %s\n" "$LABEL"
        echo
        tail -n 8 "$LOG" >&2
        rm -f "$LOG"
        return 1
    fi
}

# ------------------------------------------------------------
# DEPENDENCIES
# ------------------------------------------------------------

if (( EUID != 0 )); then
    err "Ejecuta este script como root."
    exit 1
fi

for CMD in systemctl systemd-analyze awk grep cp ss journalctl; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        err "Dependencia no encontrada: $CMD"
        exit 1
    fi
done

if [[ ! -x "$BINARY" ]]; then
    err "No se encontró $BINARY."
    exit 1
fi

if ! systemctl cat "$SERVICE" >/dev/null 2>&1; then
    err "No se encontró el servicio $SERVICE."
    exit 1
fi

UNIT=$(systemctl show "$SERVICE" -p FragmentPath --value)

if [[ -z "$UNIT" || ! -f "$UNIT" ]]; then
    err "No se encontró el archivo de configuración."
    exit 1
fi

# ------------------------------------------------------------
# CHECK DROP-INS
# ------------------------------------------------------------

DROPINS=$(systemctl show "$SERVICE" -p DropInPaths --value)

if [[ -n "$DROPINS" ]]; then
    err "La unidad tiene configuraciones adicionales (drop-ins)."
    printf '%s\n' "$DROPINS"
    warn "No se realizaron modificaciones."
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

# No interpretar incorrectamente sintaxis compleja de systemd.
if [[ "$EXEC_LINE" == *'"'* || "$EXEC_LINE" == *"'"* || "$EXEC_LINE" == *'\'* ]]; then
    err "ExecStart contiene comillas o escapes especiales."
    warn "Se necesita revisar la unidad manualmente."
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

            if (( i >= ${#ARGS[@]} )); then
                err "Falta el valor de --port."
                exit 1
            fi

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

            if (( i >= ${#ARGS[@]} )); then
                err "Falta el valor de --ssh."
                exit 1
            fi

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

            if (( i >= ${#ARGS[@]} )); then
                err "Falta el valor de -listen."
                exit 1
            fi

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

            if (( i >= ${#ARGS[@]} )); then
                err "Falta el valor de -target."
                exit 1
            fi

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

            if (( i >= ${#ARGS[@]} )); then
                err "Falta el valor de $ARG."
                exit 1
            fi

            EXTRA+=("$ARG" "${ARGS[$i]}")
            ;;

        -bhttp-v2-max-lanes=*|-session-timeout=*|-tls-cert=*|-tls-key=*|-xhttp-listen=*)
            EXTRA+=("$ARG")
            ;;

        -*)
            err "Parámetro no compatible: $ARG"
            warn "No se modificó el servicio."
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
# NORMALIZE LISTEN
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

# ------------------------------------------------------------
# NORMALIZE TARGET
# ------------------------------------------------------------

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
# PORT VALIDATION
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

# ------------------------------------------------------------
# TARGET VALIDATION
# ------------------------------------------------------------

if [[ "$TARGET" =~ ^(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9._-]+):([0-9]{1,5})$ ]]; then
    TARGET_PORT="${BASH_REMATCH[2]}"
else
    err "Formato de redirección inválido: $TARGET"
    exit 1
fi

if ! valid_port "$TARGET_PORT"; then
    err "Puerto de redirección fuera de rango."
    exit 1
fi

# ------------------------------------------------------------
# LISTENER VALIDATION
# ------------------------------------------------------------

if [[ -z "$LISTEN" || "$LISTEN" == *[[:space:]]* ]]; then
    err "Formato de escucha inválido."
    exit 1
fi

if [[ "$LISTEN" == ,* || "$LISTEN" == *, || "$LISTEN" == *,,* ]]; then
    err "Lista de listeners inválida."
    exit 1
fi

IFS=',' read -r -a LISTENERS <<< "$LISTEN"

if (( ${#LISTENERS[@]} == 0 )); then
    err "No se detectaron listeners."
    exit 1
fi

for LISTENER in "${LISTENERS[@]}"; do

    if [[ "$LISTENER" =~ ^(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9._*-]*):([0-9]{1,5})$ ]]; then
        PORT="${BASH_REMATCH[2]}"
    else
        err "Formato de listener inválido: $LISTENER"
        exit 1
    fi

    if ! valid_port "$PORT"; then
        err "Puerto de escucha fuera de rango."
        exit 1
    fi

done

# ------------------------------------------------------------
# VALIDATE EXTRA PARAMETERS
# ------------------------------------------------------------

for ARG in "${EXTRA[@]}"; do
    if [[ ! "$ARG" =~ ^[-A-Za-z0-9_./:+,@=-]+$ ]]; then
        err "Parámetro adicional contiene caracteres no admitidos."
        exit 1
    fi
done

# ------------------------------------------------------------
# CONFIGURATION SUMMARY
# ------------------------------------------------------------

echo
printf "${SILVER}CONFIGURACIÓN${RESET}\n"
echo

printf "  ${GRAY}Escucha${RESET}       ${CYAN}%s${RESET}\n" "$LISTEN"
printf "  ${GRAY}Redirección${RESET}   ${CYAN}%s${RESET}\n" "$TARGET"

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
# BACKUP
# ------------------------------------------------------------

mkdir -p "$BACKUP_DIR"

BACKUP="$BACKUP_DIR/bhttp-$(date +%Y%m%d-%H%M%S)-$$.service"

if ! cp -a "$UNIT" "$BACKUP"; then
    err "No se pudo crear el respaldo."
    exit 1
fi

# ------------------------------------------------------------
# PREPARE UNIT
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

# ------------------------------------------------------------
# SYSTEMD VALIDATION
# ------------------------------------------------------------

CHECK_DIR=$(mktemp -d)

cp "$TEMP_FILE" "$CHECK_DIR/$SERVICE"

if ! run_step "Validando configuración" \
    systemd-analyze verify "$CHECK_DIR/$SERVICE"; then
    err "La configuración no superó la validación."
    exit 1
fi

# ------------------------------------------------------------
# APPLY REPAIR
# ------------------------------------------------------------

if ! run_step "Deteniendo servicio" systemctl stop "$SERVICE"; then
    err "No se pudo detener el servicio."
    exit 1
fi

if ! mv -f "$TEMP_FILE" "$UNIT"; then
    err "No se pudo instalar la configuración."
    systemctl start "$SERVICE" || true
    exit 1
fi

TEMP_FILE=""

if ! run_step "Recargando systemd" systemctl daemon-reload; then
    err "Falló la recarga. Restaurando configuración original."

    cp -a "$BACKUP" "$UNIT"
    systemctl daemon-reload || true
    systemctl start "$SERVICE" || true
    exit 1
fi

systemctl reset-failed "$SERVICE" >/dev/null 2>&1 || true

# ------------------------------------------------------------
# RESTART SERVICE
# ------------------------------------------------------------

if ! run_step "Iniciando BHTTP" systemctl restart "$SERVICE"; then
    err "No fue posible iniciar BHTTP."
    echo
    journalctl -u "$SERVICE" -n 8 --no-pager
    echo
    warn "Respaldo disponible: $BACKUP"
    exit 1
fi

sleep 2

# ------------------------------------------------------------
# FINAL STATUS
# ------------------------------------------------------------

if ! systemctl is-active --quiet "$SERVICE"; then
    err "BHTTP no consiguió mantenerse activo."
    journalctl -u "$SERVICE" -n 8 --no-pager
    warn "Respaldo disponible: $BACKUP"
    exit 1
fi

# ------------------------------------------------------------
# SUCCESS
# ------------------------------------------------------------

echo
printf "${STEEL}────────────────────────────────────────${RESET}\n"
echo

printf "${GREEN}       ✓ BHTTP REPARADO CORRECTAMENTE${RESET}\n"
echo

printf "  ${GRAY}Estado${RESET}        ${GREEN}ACTIVO${RESET}\n"
printf "  ${GRAY}Escucha${RESET}       ${CYAN}%s${RESET}\n" "$LISTEN"
printf "  ${GRAY}Redirección${RESET}   ${CYAN}%s${RESET}\n" "$TARGET"

echo
printf "${GRAY}  Respaldo: %s${RESET}\n" "$BACKUP"
echo
