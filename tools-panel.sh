#!/usr/bin/env bash

# ==============================================================
# TOOLS ADMINISTRATIVE CENTER
# Centro de control de herramientas y scripts de GitHub
# Versión: v1.4
# Compatible con Debian / Ubuntu
# Ejecución directa desde repositorios públicos
# ==============================================================

set -o pipefail
export LC_ALL=C.UTF-8
umask 077

# --------------------------------------------------------------
# CONFIGURACION GENERAL
# --------------------------------------------------------------

VERSION="v1.0"

BOX_WIDTH=58
CARD_WIDTH=24
CARD_GAP=2

REPOSITORY="https://github.com/ChristopherAGT/tools"
RAW_BASE="https://raw.githubusercontent.com/ChristopherAGT/tools/main"

LOG_FILE="/var/log/tools-admin.log"

# --------------------------------------------------------------
# HERRAMIENTAS REMOTAS FIJAS
# --------------------------------------------------------------

declare -a MENU_SCRIPTS=(
    "darnix-backup-manager.sh"
    "edit-reseller.sh"
    "firewalld-setup.sh"
    "dns-repair.sh"
    "bandwidth-manager.sh"
    "keys-manager.sh"
    "ssh-root-access.sh"
    "hostname-manager.sh"
    "cleanup.sh"
    "tcp-bbr.sh"
)

declare -a MENU_DESCRIPTIONS=(
    "Respaldar / Restaurar usuarios Darnix"
    "Modificar Reseller"
    "Configurar Firewall TCP/UDP"
    "Restaurar DNS a valores de fabrica"
    "Modificar limite de ancho de banda"
    "Administrar claves SLOWDNS"
    "Habilitar acceso SSH como root"
    "Modificar Hostname"
    "Limpiar memoria del sistema"
    "Optimizar TCP y activar BBR"
)

declare -a MENU_CATEGORIES=(
    "1" "1"
    "2" "2" "2"
    "3" "3" "3"
    "4" "4"
)

# --------------------------------------------------------------
# COLORES
# --------------------------------------------------------------

if [[ -t 1 ]]; then
    R=$'\033[0m'
    B=$'\033[1m'
    D=$'\033[2m'

    RED=$'\033[1;31m'
    GREEN=$'\033[1;32m'
    YELLOW=$'\033[1;33m'
    BLUE=$'\033[1;34m'
    MAGENTA=$'\033[1;35m'
    CYAN=$'\033[1;36m'
    WHITE=$'\033[1;37m'
    GRAY=$'\033[0;37m'

    NUM1=$'\033[1;36m'
    NUM2=$'\033[1;32m'
    NUM3=$'\033[1;33m'
    NUM4=$'\033[1;35m'
    NUM5=$'\033[1;34m'
    NUM6=$'\033[1;31m'
    NUM7=$'\033[1;36m'
    NUM8=$'\033[1;32m'
    NUM9=$'\033[1;33m'
    NUM10=$'\033[1;35m'
else
    R='' B='' D=''
    RED='' GREEN='' YELLOW='' BLUE=''
    MAGENTA='' CYAN='' WHITE='' GRAY=''
    NUM1='' NUM2='' NUM3='' NUM4='' NUM5=''
    NUM6='' NUM7='' NUM8='' NUM9='' NUM10=''
fi

# --------------------------------------------------------------
# UTILIDADES VISUALES
# --------------------------------------------------------------

repeat_char() {
    local char="$1"
    local count="$2"

    (( count < 0 )) && count=0

    printf -v REPEAT_RESULT '%*s' "$count" ''
    REPEAT_RESULT="${REPEAT_RESULT// /$char}"

    printf '%s' "$REPEAT_RESULT"
}

visible_width() {
    python3 -c '
import re, sys, unicodedata

s = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", sys.argv[1])
w = 0

for c in s:
    cp = ord(c)

    if unicodedata.combining(c) or c in ("\u200d", "\ufe0f"):
        continue

    if 0x1F000 <= cp <= 0x1FAFF or 0x2600 <= cp <= 0x27BF:
        w += 2
    else:
        w += 2 if unicodedata.east_asian_width(c) in ("W", "F") else 1

print(w)
' "$1"
}

box_top() {
    printf '%b  ╭' "$1"
    repeat_char '─' "$BOX_WIDTH"
    printf '╮%b\n' "$R"
}

box_bottom() {
    printf '%b  ╰' "$1"
    repeat_char '─' "$BOX_WIDTH"
    printf '╯%b\n' "$R"
}

box_separator() {
    printf '%b  ├' "$1"
    repeat_char '─' "$BOX_WIDTH"
    printf '┤%b\n' "$R"
}

box_row() {
    local color="$1"
    local content="$2"
    local width padding max_width

    max_width=$((BOX_WIDTH - 2))
    width="$(visible_width "$content")"

    if (( width > max_width )); then
        content="$(printf '%b' "$content" |
            sed -E $'s/\033\\[[0-?]*[ -/]*[@-~]//g')"
        content="${content:0:max_width}"
        width="$(visible_width "$content")"
    fi

    padding=$((max_width - width))
    (( padding < 0 )) && padding=0

    printf '  %b│%b ' "$color" "$R"
    printf '%b' "$content"
    printf '%*s' "$padding" ''
    printf ' %b│%b\n' "$color" "$R"
}

center_text() {
    local content="$1"
    local available="$2"
    local width left right

    width="$(visible_width "$content")"

    if (( width >= available )); then
        printf '%s' "$content"
        return
    fi

    left=$(((available - width) / 2))
    right=$((available - width - left))

    printf '%*s%b%*s' "$left" '' "$content" "$right" ''
}

# --------------------------------------------------------------
# TARJETAS DEL DASHBOARD
# --------------------------------------------------------------

card_top() {
    printf '%b┌' "$1"
    repeat_char '─' "$CARD_WIDTH"
    printf '┐%b' "$R"
}

card_bottom() {
    printf '%b└' "$1"
    repeat_char '─' "$CARD_WIDTH"
    printf '┘%b' "$R"
}

card_row() {
    local color="$1"
    local content="$2"
    local width padding

    width="$(visible_width "$content")"

    if (( width > CARD_WIDTH - 2 )); then
        content="${content:0:CARD_WIDTH-2}"
        width="$(visible_width "$content")"
    fi

    padding=$((CARD_WIDTH - 2 - width))
    (( padding < 0 )) && padding=0

    printf '%b│%b ' "$color" "$R"
    printf '%b' "$content"
    printf '%*s' "$padding" ''
    printf ' %b│%b' "$color" "$R"
}

# --------------------------------------------------------------
# REGISTRO DE ACTIVIDAD
# --------------------------------------------------------------

log_message() {
    printf '[%s] %s\n' \
        "$(date '+%F %T')" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

# --------------------------------------------------------------
# ENCABEZADO PRINCIPAL
# --------------------------------------------------------------

header() {
    clear 2>/dev/null || true

    printf '\n'

    box_top "$CYAN"
    box_row "$CYAN" ""
    box_row "$CYAN" "$(center_text "${CYAN}${B}TOOLS ADMINISTRATIVE CENTER${R}" "$((BOX_WIDTH - 2))")"
    box_row "$CYAN" "$(center_text "${WHITE}${B}CENTRO DE CONTROL DE HERRAMIENTAS${R}" "$((BOX_WIDTH - 2))")"
    box_row "$CYAN" "$(center_text "${GRAY}Administración · Scripts · Mantenimiento${R}" "$((BOX_WIDTH - 2))")"
    box_row "$CYAN" ""
    box_bottom "$CYAN"

    printf '\n'

    box_top "$GRAY"

    local status_text version_text gap

    status_text="${GREEN}● Repositorio configurado${R}"
    version_text="${YELLOW}Versión ${VERSION}${R}"

    gap=$((BOX_WIDTH - 2 - $(visible_width "$status_text") - $(visible_width "$version_text")))
    (( gap < 1 )) && gap=1

    box_row "$GRAY" "${status_text}$(printf '%*s' "$gap" '')${version_text}"
    box_bottom "$GRAY"
}

# --------------------------------------------------------------
# INFORMACION DEL VPS
# --------------------------------------------------------------

get_os_name() {
    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        printf '%s' "${PRETTY_NAME:-Linux}"
    else
        printf 'Linux'
    fi
}

get_public_ip() {
    local ip=""

    ip="$(curl -4 -fsS \
        --connect-timeout 2 \
        --max-time 4 \
        https://api.ipify.org 2>/dev/null || true)"

    if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        ip="$(curl -4 -fsS \
            --connect-timeout 2 \
            --max-time 4 \
            https://ipv4.icanhazip.com 2>/dev/null || true)"
    fi

    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local octet valid=1
        local -a octets=()

        IFS='.' read -r -a octets <<< "$ip"

        if ((${#octets[@]} == 4)); then
            for octet in "${octets[@]}"; do
                if ((10#$octet > 255)); then
                    valid=0
                    break
                fi
            done
        else
            valid=0
        fi

        if ((valid)); then
            printf '%s' "$ip"
            return 0
        fi
    fi

    printf 'No disponible'
}

show_server_info() {
    local hostname os_name uptime_text public_ip

    hostname="$(hostname 2>/dev/null || printf 'No disponible')"
    os_name="$(get_os_name)"
    uptime_text="$(uptime -p 2>/dev/null || printf 'No disponible')"
    public_ip="$(get_public_ip)"

    printf "  %bHOSTNAME  :%b %b%s%b\n" \
        "$GRAY" "$R" "$WHITE" "$hostname" "$R"

    printf "  %bIP PUBLICA:%b %b%s%b\n" \
        "$GRAY" "$R" "$CYAN" "$public_ip" "$R"

    printf "  %bSISTEMA   :%b %b%s%b\n" \
        "$GRAY" "$R" "$WHITE" "$os_name" "$R"

    printf "  %bUPTIME    :%b %b%s%b\n" \
        "$GRAY" "$R" "$WHITE" "$uptime_text" "$R"

    printf "  %bFECHA     :%b %b%s%b\n" \
        "$GRAY" "$R" "$WHITE" "$(date '+%d/%m/%Y %H:%M:%S')" "$R"
}

# --------------------------------------------------------------
# DASHBOARD DEL SISTEMA
# --------------------------------------------------------------

show_dashboard() {
    local ram_total ram_available ram_used ram_pct
    local disk_total disk_used disk_pct
    local card_indent=4

    ram_total="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
    ram_available="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"

    ram_total="${ram_total:-0}"
    ram_available="${ram_available:-0}"
    ram_used=$((ram_total - ram_available))
    ram_pct=0

    ((ram_total > 0)) && ram_pct=$((ram_used * 100 / ram_total))

    disk_total="$(df -B1 --output=size / 2>/dev/null | awk 'NR==2 {print $1}')"
    disk_used="$(df -B1 --output=used / 2>/dev/null | awk 'NR==2 {print $1}')"

    disk_total="${disk_total:-0}"
    disk_used="${disk_used:-0}"
    disk_pct=0

    ((disk_total > 0)) && disk_pct=$((disk_used * 100 / disk_total))

    printf '\n'
    box_top "$BLUE"
    box_row "$BLUE" "$(center_text "${WHITE}${B}INFORMACIÓN DEL VPS${R}" "$((BOX_WIDTH - 2))")"
    box_separator "$BLUE"

    printf '%*s' "$card_indent" ''
    card_top "$CYAN"
    printf '%*s' "$CARD_GAP" ''
    card_top "$MAGENTA"
    printf '\n'

    printf '%*s' "$card_indent" ''
    card_row "$CYAN" "MEMORIA RAM"
    printf '%*s' "$CARD_GAP" ''
    card_row "$MAGENTA" "DISCO RAÍZ"
    printf '\n'

    printf '%*s' "$card_indent" ''
    card_row "$CYAN" "Uso: ${ram_pct}%"
    printf '%*s' "$CARD_GAP" ''
    card_row "$MAGENTA" "Uso: ${disk_pct}%"
    printf '\n'

    printf '%*s' "$card_indent" ''
    card_row "$CYAN" "Total: $((ram_total / 1024)) MiB"
    printf '%*s' "$CARD_GAP" ''
    card_row "$MAGENTA" "Total: $((disk_total / 1073741824)) GiB"
    printf '\n'

    printf '%*s' "$card_indent" ''
    card_bottom "$CYAN"
    printf '%*s' "$CARD_GAP" ''
    card_bottom "$MAGENTA"
    printf '\n'

    # Identificación centrada en color blanco.
    box_separator "$BLUE"
    box_row "$BLUE" "$(center_text "${WHITE}${B}CHRISTOPHER ACKERMAN${R}" "$((BOX_WIDTH - 2))")"
    box_bottom "$BLUE"
}

# --------------------------------------------------------------
# CATEGORIAS DEL MENU
# --------------------------------------------------------------

category_name() {
    case "$1" in
        1) printf 'USUARIOS Y ACCESOS' ;;
        2) printf 'RED Y CONECTIVIDAD' ;;
        3) printf 'SISTEMA Y CONFIGURACIÓN' ;;
        4) printf 'MANTENIMIENTO Y RENDIMIENTO' ;;
        *) printf 'OTRAS HERRAMIENTAS' ;;
    esac
}

# --------------------------------------------------------------
# NUMEROS COLOREADOS DEL MENU
# --------------------------------------------------------------

number_color() {
    case "$1" in
        1) printf '%s' "$NUM1" ;;
        2) printf '%s' "$NUM2" ;;
        3) printf '%s' "$NUM3" ;;
        4) printf '%s' "$NUM4" ;;
        5) printf '%s' "$NUM5" ;;
        6) printf '%s' "$NUM6" ;;
        7) printf '%s' "$NUM7" ;;
        8) printf '%s' "$NUM8" ;;
        9) printf '%s' "$NUM9" ;;
        10) printf '%s' "$NUM10" ;;
        *) printf '%s' "$CYAN" ;;
    esac
}

# --------------------------------------------------------------
# MENU PRINCIPAL
# --------------------------------------------------------------

show_menu_item() {
    local number="$1"
    local description="$2"
    local color

    color="$(number_color "$number")"

    # Un solo espacio entre el número y la descripción.
    box_row "$CYAN" "${color}${B}[${number}]${R} ${WHITE}${description}${R}"
}

show_category() {
    local emoji="$1"
    local title="$2"
    local color="$3"

    # El emoji empieza en la misma columna que [1].
    # El título empieza en la misma columna que la descripción.
    box_separator "$CYAN"
    box_row "$CYAN" "${color}${B}${emoji}${R}  ${color}${B}${title}${R}"
}

show_main_menu() {
    box_top "$CYAN"
    box_row "$CYAN" "$(center_text "${WHITE}${B}HERRAMIENTAS DISPONIBLES${R}" "$((BOX_WIDTH - 2))")"

    show_category "👥" "USUARIOS Y ACCESOS" "$CYAN"
    show_menu_item 1 "${MENU_DESCRIPTIONS[0]}"
    show_menu_item 2 "${MENU_DESCRIPTIONS[1]}"

    show_category "🌐" "RED Y CONECTIVIDAD" "$GREEN"
    show_menu_item 3 "${MENU_DESCRIPTIONS[2]}"
    show_menu_item 4 "${MENU_DESCRIPTIONS[3]}"
    show_menu_item 5 "${MENU_DESCRIPTIONS[4]}"

    show_category "⚙️" "SISTEMA Y CONFIGURACIÓN" "$MAGENTA"
    show_menu_item 6 "${MENU_DESCRIPTIONS[5]}"
    show_menu_item 7 "${MENU_DESCRIPTIONS[6]}"
    show_menu_item 8 "${MENU_DESCRIPTIONS[7]}"

    show_category "🛠️" "MANTENIMIENTO Y RENDIMIENTO" "$YELLOW"
    show_menu_item 9 "${MENU_DESCRIPTIONS[8]}"
    show_menu_item 10 "${MENU_DESCRIPTIONS[9]}"

    box_separator "$CYAN"
    box_row "$CYAN" "${RED}${B}[0]${R} Salir del administrador"
    box_bottom "$CYAN"

    printf '\n%b  ➤ Selecciona una opción: %b' "$CYAN" "$R"
}

# --------------------------------------------------------------
# EJECUCION REMOTA DESDE GITHUB
# Ejecución directa sin pantalla de confirmación
# --------------------------------------------------------------

execute_script() {
    local index="$1"
    local script_name label script_url script_content
    local result=0

    script_name="${MENU_SCRIPTS[$index]}"
    label="${MENU_DESCRIPTIONS[$index]}"
    script_url="${RAW_BASE}/${script_name}"
    script_content=""

    printf '\n%b  ▶ Ejecutando: %s%b\n' "$CYAN" "$label" "$R"

    if ! script_content="$(
        curl -fsSL \
            --connect-timeout 10 \
            --max-time 300 \
            -H 'User-Agent: Tools-Administrative-Center' \
            "$script_url"
    )"; then
        printf '\n%b  ✖ No se pudo descargar la herramienta.%b\n' "$RED" "$R"
        log_message "ERROR de descarga | $script_name"
        printf '\n'
        read -r -p "Presiona ENTER para volver al menú..." _ || true
        return 1
    fi

    if [[ -z "$script_content" ]]; then
        printf '\n%b  ✖ GitHub devolvió contenido vacío.%b\n' "$RED" "$R"
        log_message "ERROR contenido vacío | $script_name"
        printf '\n'
        read -r -p "Presiona ENTER para volver al menú..." _ || true
        return 1
    fi

    if ! bash -n <<< "$script_content"; then
        printf '\n%b  ✖ El script contiene errores de sintaxis.%b\n' "$RED" "$R"
        log_message "ERROR de sintaxis | $script_name"
        printf '\n'
        read -r -p "Presiona ENTER para volver al menú..." _ || true
        return 1
    fi

    export TOOLS_REPOSITORY_URL="$REPOSITORY"
    export TOOLS_RAW_BASE_URL="$RAW_BASE"
    export TOOLS_REMOTE_SCRIPT_NAME="$script_name"
    export TOOLS_REMOTE_SCRIPT_URL="$script_url"

    export SCRIPT_REPOSITORY_URL="$REPOSITORY"
    export SCRIPT_REMOTE_URL="$script_url"
    export SCRIPT_REPO_PATH="$script_name"

    printf '%b  ✔ Descarga y sintaxis verificadas.%b\n' "$GREEN" "$R"
    printf '%b  ──────────────────────────────────────────────────%b\n' "$GRAY" "$R"

    log_message "Inicio de ejecución | $script_name | $label"

    if bash -c "$script_content" "$script_name"; then
        result=0
    else
        result=$?
    fi

    unset TOOLS_REPOSITORY_URL TOOLS_RAW_BASE_URL
    unset TOOLS_REMOTE_SCRIPT_NAME TOOLS_REMOTE_SCRIPT_URL
    unset SCRIPT_REPOSITORY_URL SCRIPT_REMOTE_URL SCRIPT_REPO_PATH

    printf '\n%b  ──────────────────────────────────────────────────%b\n' "$GRAY" "$R"

    if ((result == 0)); then
        printf '%b  ✔ Herramienta finalizada correctamente.%b\n' "$GREEN" "$R"
    else
        printf '%b  ⚠ La herramienta terminó con código %s.%b\n' "$YELLOW" "$result" "$R"
    fi

    log_message "Fin de ejecución | $script_name | código=$result"

    printf '\n'
    read -r -p "Presiona ENTER para volver al menú..." _ || true
}

# --------------------------------------------------------------
# INFORMACION DEL SISTEMA
# --------------------------------------------------------------

show_system_info() {
    header
    show_server_info

    box_top "$BLUE"
    box_row "$BLUE" "${WHITE}${B}INFORMACIÓN ADICIONAL${R}"
    box_separator "$BLUE"
    box_row "$BLUE" "Kernel: $(uname -r 2>/dev/null || printf 'No disponible')"
    box_row "$BLUE" "Arquitectura: $(uname -m 2>/dev/null || printf 'No disponible')"
    box_row "$BLUE" "Repositorio: ChristopherAGT/tools"
    box_row "$BLUE" "Rama: main"
    box_bottom "$BLUE"

    printf '\n'
    read -r -p "Presiona ENTER para volver al menú..." _ || true
}

# --------------------------------------------------------------
# REGISTRO DE ACTIVIDAD
# --------------------------------------------------------------

show_log() {
    local line

    header

    box_top "$BLUE"
    box_row "$BLUE" "${WHITE}${B}REGISTRO DE ACTIVIDAD${R}"
    box_separator "$BLUE"

    if [[ -s "$LOG_FILE" ]]; then
        while IFS= read -r line; do
            box_row "$BLUE" "$line"
        done < <(tail -n 12 "$LOG_FILE")
    else
        box_row "$BLUE" "Todavía no hay actividad registrada."
    fi

    box_bottom "$BLUE"

    printf '\n'
    read -r -p "Presiona ENTER para volver al menú..." _ || true
}

# --------------------------------------------------------------
# COMPROBACIONES INICIALES
# --------------------------------------------------------------

check_environment() {
    local cmd
    local -a missing=()

    if ((EUID != 0)); then
        printf '%b✖ Ejecuta el panel como root o mediante sudo.%b\n' "$RED" "$R"
        return 1
    fi

    for cmd in bash curl python3 awk df uptime hostname date sed tail; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done

    if ((${#missing[@]} > 0)); then
        printf '%b✖ Faltan comandos: %s%b\n' "$RED" "${missing[*]}" "$R"
        return 1
    fi

    if ! touch "$LOG_FILE" 2>/dev/null; then
        printf '%b✖ No se puede escribir el registro: %s%b\n' "$RED" "$LOG_FILE" "$R"
        return 1
    fi

    return 0
}

# --------------------------------------------------------------
# BUCLE PRINCIPAL
# --------------------------------------------------------------

main() {
    local option index

    if ! check_environment; then
        exit 1
    fi

    log_message "Panel iniciado | versión $VERSION"

    while true; do
        header
        show_server_info
        show_dashboard
        show_main_menu

        if ! read -r option; then
            printf '\n'
            exit 0
        fi

        case "${option,,}" in
            0|q|salir|exit)
                printf '\n%b  Gracias por utilizar TOOLS ADMINISTRATIVE CENTER.%b\n' "$GREEN" "$R"
                log_message "Panel cerrado"
                exit 0
                ;;

            i|info)
                show_system_info
                ;;

            l|log)
                show_log
                ;;

            '')
                ;;

            *[!0-9]*)
                printf '\n%b  ⚠ Opción inválida.%b\n' "$YELLOW" "$R"
                sleep 1
                ;;

            *)
                # Evita errores al procesar opciones con ceros iniciales.
                if [[ "$option" =~ ^[0-9]+$ ]]; then
                    # La opción 0 se procesa antes; las opciones 1–10
                    # se convierten a índices de arreglo de 0–9.
                    index=$((10#$option - 1))

                    if ((index >= 0 && index < ${#MENU_SCRIPTS[@]})); then
                        execute_script "$index" || true
                    else
                        printf '\n%b  ⚠ Selecciona una opción del 0 al 10.%b\n' "$YELLOW" "$R"
                        sleep 1
                    fi
                else
                    printf '\n%b  ⚠ Opción inválida.%b\n' "$YELLOW" "$R"
                    sleep 1
                fi
                ;;
        esac
    done
}

main "$@"
