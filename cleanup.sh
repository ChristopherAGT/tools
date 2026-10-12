#!/usr/bin/env bash

# ==============================================================
# LINUX CLEANUP MANAGER
# Centro de control de limpieza, mantenimiento y diagnóstico
# Versión: v1.2
# Compatible con Debian / Ubuntu
# ==============================================================

set -o pipefail
export LC_ALL=C.UTF-8
umask 077

VERSION="v1.2"
BOX_WIDTH=58
TMP_MAX_AGE=1440
LOG_FILE="/var/log/cleanup-manager.log"

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
else
    R='' B='' D='' RED='' GREEN=''
    YELLOW='' BLUE='' MAGENTA=''
    CYAN='' WHITE='' GRAY=''
fi

# --------------------------------------------------------------
# VARIABLES
# --------------------------------------------------------------

declare -a STEP_NAMES=()
declare -a STEP_RESULTS=()
declare -a STEP_DETAILS=()

TOTAL_OK=0
TOTAL_FAIL=0
TOTAL_SKIP=0

START_TIME=0

MEM_BEFORE=0
MEM_AFTER=0
CACHE_BEFORE=0
CACHE_AFTER=0
DISK_BEFORE=0
DISK_AFTER=0
APT_BEFORE=0
APT_AFTER=0
TMP_BEFORE=0
TMP_AFTER=0

JOURNAL_FREED="0 B"

# --------------------------------------------------------------
# UTILIDADES
# --------------------------------------------------------------

repeat_char() {
    local char="$1"
    local count="$2"

    (( count < 0 )) && count=0

    printf -v REPEAT_RESULT '%*s' "$count" ''
    REPEAT_RESULT="${REPEAT_RESULT// /$char}"

    printf '%s' "$REPEAT_RESULT"
}

strip_ansi() {
    printf '%s' "$1" |
        sed -E $'s/\033\\[[0-?]*[ -/]*[@-~]//g'
}

# --------------------------------------------------------------
# ANCHO VISIBLE UNICODE
# --------------------------------------------------------------

visible_width() {
    python3 -c '
import re
import sys
import unicodedata

text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", sys.argv[1])

width = 0
previous_width = 0
join_next = False

for char in text:
    cp = ord(char)

    if cp == 0x200D:
        join_next = True
        continue

    if (
        unicodedata.combining(char)
        or 0x0300 <= cp <= 0x036F
        or 0x1AB0 <= cp <= 0x1AFF
        or 0x1DC0 <= cp <= 0x1DFF
        or 0xFE00 <= cp <= 0xFE0F
        or 0xE0100 <= cp <= 0xE01EF
        or cp == 0x20E3
    ):
        if cp == 0xFE0F and previous_width == 1:
            width += 1
            previous_width = 2
        continue

    east_width = unicodedata.east_asian_width(char)

    # Los tres símbolos del resumen se cuentan como caracteres
    # de texto de una columna, evitando diferencias de ancho
    # entre fuentes y terminales.
    if cp in (0x2714, 0x2716, 0x21B7):
        char_width = 1
    else:
        is_emoji = (
            0x1F000 <= cp <= 0x1FAFF
            or 0x1FC00 <= cp <= 0x1FFFF
            or (
                0x2600 <= cp <= 0x27BF
                and cp not in (0x2714, 0x2716)
            )
        )

        char_width = (
            2 if east_width in ("W", "F") or is_emoji else 1
        )

    if join_next:
        width += max(0, char_width - previous_width)
        join_next = False
    else:
        width += char_width

    previous_width = char_width

print(width)
' "$1"
}

format_bytes() {
    local bytes="${1:-0}"

    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0

    awk -v b="$bytes" 'BEGIN {
        if (b >= 1073741824)
            printf "%.2f GiB", b / 1073741824
        else if (b >= 1048576)
            printf "%.2f MiB", b / 1048576
        else if (b >= 1024)
            printf "%.2f KiB", b / 1024
        else
            printf "%.0f B", b
    }'
}

safe_number() {
    local number="${1:-0}"

    if [[ "$number" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$number"
    else
        printf '0\n'
    fi
}

read_meminfo() {
    local key="$1"

    awk -v key="$key" '
        $1 == key ":" {
            print $2 * 1024
            found=1
            exit
        }
        END {
            if (!found) print 0
        }
    ' /proc/meminfo
}

read_disk_used() {
    df -B1 --output=used / 2>/dev/null |
        awk 'NR == 2 {print $1; exit}'
}

read_disk_available() {
    df -B1 --output=avail / 2>/dev/null |
        awk 'NR == 2 {print $1; exit}'
}

read_disk_total() {
    df -B1 --output=size / 2>/dev/null |
        awk 'NR == 2 {print $1; exit}'
}

read_directory_size() {
    local directory="$1"

    if [[ -d "$directory" ]]; then
        du -sb "$directory" 2>/dev/null |
            awk 'NR == 1 {print $1; exit}'
    else
        printf '0\n'
    fi
}

# --------------------------------------------------------------
# CUADROS ALINEADOS
# --------------------------------------------------------------

box_top() {
    local color="$1"

    printf '%b  ╭' "$color"
    repeat_char '─' "$BOX_WIDTH"
    printf '╮%b\n' "$R"
}

box_bottom() {
    local color="$1"

    printf '%b  ╰' "$color"
    repeat_char '─' "$BOX_WIDTH"
    printf '╯%b\n' "$R"
}

box_separator() {
    local color="$1"

    printf '%b  ├' "$color"
    repeat_char '─' "$BOX_WIDTH"
    printf '┤%b\n' "$R"
}

# --------------------------------------------------------------
# FILAS DE ANCHO FIJO
# --------------------------------------------------------------

box_row() {
    local color="$1"
    local content="$2"
    local width padding max_width

    max_width=$((BOX_WIDTH - 2))
    width="$(visible_width "$content")"

    if (( width > max_width )); then
        content="$(strip_ansi "$content")"
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

CARD_WIDTH=24

card_top() {
    local color="$1"

    printf '%b┌' "$color"
    repeat_char '─' "$CARD_WIDTH"
    printf '┐%b' "$R"
}

card_bottom() {
    local color="$1"

    printf '%b└' "$color"
    repeat_char '─' "$CARD_WIDTH"
    printf '┘%b' "$R"
}

card_row() {
    local color="$1"
    local content="$2"
    local width padding max_width

    max_width=$((CARD_WIDTH - 2))
    width="$(visible_width "$content")"

    if (( width > max_width )); then
        content="$(strip_ansi "$content")"
        content="${content:0:max_width}"
        width="$(visible_width "$content")"
    fi

    padding=$((max_width - width))
    (( padding < 0 )) && padding=0

    printf '%b│%b ' "$color" "$R"
    printf '%b' "$content"
    printf '%*s' "$padding" ''
    printf ' %b│%b' "$color" "$R"
}

# --------------------------------------------------------------
# REGISTRO
# --------------------------------------------------------------

log_message() {
    printf '[%s] %s\n' \
        "$(date '+%F %T')" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

record_result() {
    local name="$1"
    local result="$2"
    local detail="$3"

    STEP_NAMES+=("$name")
    STEP_RESULTS+=("$result")
    STEP_DETAILS+=("$detail")

    case "$result" in
        OK)   ((TOTAL_OK += 1)) ;;
        FAIL) ((TOTAL_FAIL += 1)) ;;
        SKIP) ((TOTAL_SKIP += 1)) ;;
    esac

    log_message "$result | $name | $detail"
}

# --------------------------------------------------------------
# EJECUCIÓN DE OPERACIONES
# --------------------------------------------------------------

run_step() {
    local name="$1"
    shift

    local output rc

    printf '\n%b  ⚙️  %s%b\n' "$CYAN" "$name" "$R"
    printf '%b  ├─ Ejecutando operación...%b\n' "$GRAY" "$R"

    output="$("$@" 2>&1)"
    rc=$?

    if (( rc == 0 )); then
        printf '%b  └─ [OK] Completado correctamente%b\n' "$GREEN" "$R"
        record_result "$name" "OK" "Completada"
    else
        printf '%b  └─ [ERROR] Código %s%b\n' "$RED" "$rc" "$R"

        if [[ -n "$output" ]]; then
            printf '%b%s%b\n' "$GRAY" "$output" "$R"
        fi

        record_result "$name" "FAIL" "Código $rc"
    fi

    if [[ -n "$output" ]]; then
        {
            printf '\n[%s] %s | código=%s\n' \
                "$(date '+%F %T')" "$name" "$rc"
            printf '%s\n' "$output"
        } >> "$LOG_FILE" 2>/dev/null || true
    fi

    return 0
}

# --------------------------------------------------------------
# ENCABEZADO PRINCIPAL
# --------------------------------------------------------------

header() {
    clear 2>/dev/null || true

    printf '\n'

    box_top "$CYAN"
    box_row "$CYAN" ""
    box_row "$CYAN" "$(center_text "${CYAN}${B}LINUX CLEANUP MANAGER${R}" "$((BOX_WIDTH - 2))")"
    box_row "$CYAN" "$(center_text "${WHITE}${B}CENTRO DE CONTROL DEL SISTEMA${R}" "$((BOX_WIDTH - 2))")"
    box_row "$CYAN" "$(center_text "${GRAY}Limpieza · Mantenimiento · Diagnóstico${R}" "$((BOX_WIDTH - 2))")
    box_row "$CYAN" ""
    box_bottom "$CYAN"

    printf '\n'

    box_top "$GRAY"
    box_row "$GRAY" "${GREEN}● Sistema preparado${R}                 ${YELLOW}Versión ${VERSION}${R}"
    box_bottom "$GRAY"
}

# --------------------------------------------------------------
# DASHBOARD: CUATRO TARJETAS 2 X 2
# --------------------------------------------------------------

show_dashboard() {
    local total available used
    local disk_total disk_free disk_used
    local apt_size tmp_size
    local mem_pct disk_pct
    local card_gap card_pair_width card_left_padding

    total="$(safe_number "$(read_meminfo MemTotal)")"
    available="$(safe_number "$(read_meminfo MemAvailable)")"
    used=$((total - available))

    disk_total="$(safe_number "$(read_disk_total)")"
    disk_free="$(safe_number "$(read_disk_available)")"
    disk_used="$(safe_number "$(read_disk_used)")"

    apt_size="$(safe_number "$(read_directory_size /var/cache/apt/archives)")"
    tmp_size="$(safe_number "$(read_directory_size /tmp)")"

    mem_pct=0
    disk_pct=0

    (( total > 0 )) && mem_pct=$((used * 100 / total))
    (( disk_total > 0 )) && disk_pct=$((disk_used * 100 / disk_total))

    card_gap=2

    # Cada tarjeta mide CARD_WIDTH + 2 columnas:
    # una para cada borde vertical.
    card_pair_width=$(((CARD_WIDTH + 2) * 2 + card_gap))

    # Centrar el conjunto respecto al interior del cuadro principal.
    card_left_padding=$(((BOX_WIDTH - card_pair_width) / 2 + 1))

    (( card_left_padding < 0 )) && card_left_padding=0

    printf '\n'
    printf '%b  ◈ PANEL DE MONITOREO%b\n' "$BLUE" "$R"

    box_top "$BLUE"
    box_row "$BLUE" "${WHITE}${B}ESTADO ACTUAL DEL VPS${R}"
    box_separator "$BLUE"

    printf '%*s' "$((card_left_padding + 2))" ""
    card_top "$GREEN"
    printf '%*s' "$card_gap" ""
    card_top "$MAGENTA"
    printf '\n'

    printf '%*s' "$((card_left_padding + 2))" ""
    card_row "$GREEN" "🧠 MEMORIA RAM"
    printf '%*s' "$card_gap" ""
    card_row "$MAGENTA" "💽 DISCO RAÍZ"
    printf '\n'

    printf '%*s' "$((card_left_padding + 2))" ""
    card_row "$GREEN" "Uso: ${mem_pct}%"
    printf '%*s' "$card_gap" ""
    card_row "$MAGENTA" "Uso: ${disk_pct}%"
    printf '\n'

    printf '%*s' "$((card_left_padding + 2))" ""
    card_row "$GREEN" "Libre: $(format_bytes "$available")"
    printf '%*s' "$card_gap" ""
    card_row "$MAGENTA" "Libre: $(format_bytes "$disk_free")"
    printf '\n'

    printf '%*s' "$((card_left_padding + 2))" ""
    card_bottom "$GREEN"
    printf '%*s' "$card_gap" ""
    card_bottom "$MAGENTA"
    printf '\n'

    box_separator "$BLUE"

    printf '%*s' "$((card_left_padding + 2))" ""
    card_top "$YELLOW"
    printf '%*s' "$card_gap" ""
    card_top "$BLUE"
    printf '\n'

    printf '%*s' "$((card_left_padding + 2))" ""
    card_row "$YELLOW" "📦 CACHÉ APT"
    printf '%*s' "$card_gap" ""
    card_row "$BLUE" "🧹 TEMPORALES"
    printf '\n'

    printf '%*s' "$((card_left_padding + 2))" ""
    card_row "$YELLOW" "Paquetes descargados"
    printf '%*s' "$card_gap" ""
    card_row "$BLUE" "Directorio /tmp"
    printf '\n'

    printf '%*s' "$((card_left_padding + 2))" ""
    card_row "$YELLOW" "$(format_bytes "$apt_size")"
    printf '%*s' "$card_gap" ""
    card_row "$BLUE" "$(format_bytes "$tmp_size")"
    printf '\n'

    printf '%*s' "$((card_left_padding + 2))" ""
    card_bottom "$YELLOW"
    printf '%*s' "$card_gap" ""
    card_bottom "$BLUE"
    printf '\n'

    box_separator "$BLUE"
    box_row "$BLUE" "${GRAY}📈 Valores actuales del sistema.${R}"
    box_bottom "$BLUE"
}

# --------------------------------------------------------------
# INFORMACIÓN DETALLADA DEL SISTEMA
# --------------------------------------------------------------

show_system_info() {
    local total available used swap_total swap_free
    local disk_total disk_free disk_used
    local mem_pct disk_pct swap_used hostname os_name uptime_text
    local ram_status disk_status

    total="$(safe_number "$(read_meminfo MemTotal)")"
    available="$(safe_number "$(read_meminfo MemAvailable)")"
    used=$((total - available))

    swap_total="$(safe_number "$(read_meminfo SwapTotal)")"
    swap_free="$(safe_number "$(read_meminfo SwapFree)")"
    swap_used=$((swap_total - swap_free))

    disk_total="$(safe_number "$(read_disk_total)")"
    disk_free="$(safe_number "$(read_disk_available)")"
    disk_used="$(safe_number "$(read_disk_used)")"

    mem_pct=0
    disk_pct=0

    (( total > 0 )) && mem_pct=$((used * 100 / total))
    (( disk_total > 0 )) && disk_pct=$((disk_used * 100 / disk_total))

    hostname="$(hostname 2>/dev/null || printf 'Desconocido')"

    os_name="Linux"
    if [[ -r /etc/os-release ]]; then
        os_name="$(. /etc/os-release; printf '%s' "${PRETTY_NAME:-Linux}")"
    fi

    uptime_text="$(uptime -p 2>/dev/null || printf 'No disponible')"

    if (( mem_pct >= 90 )); then
        ram_status="${RED}Alto${R}"
    elif (( mem_pct >= 75 )); then
        ram_status="${YELLOW}Moderado${R}"
    else
        ram_status="${GREEN}Normal${R}"
    fi

    if (( disk_pct >= 90 )); then
        disk_status="${RED}Crítico${R}"
    elif (( disk_pct >= 75 )); then
        disk_status="${YELLOW}Elevado${R}"
    else
        disk_status="${GREEN}Normal${R}"
    fi

    printf '\n'
    printf '%b  📊 INFORMACIÓN DETALLADA%b\n' "$BLUE" "$R"

    box_top "$BLUE"
    box_row "$BLUE" "${WHITE}${B}🖥️  EQUIPO${R}"
    box_separator "$BLUE"
    box_row "$BLUE" "🖥️  Host:       $hostname"
    box_row "$BLUE" "🐧  Sistema:    $os_name"
    box_row "$BLUE" "⏱️  Encendido:  $uptime_text"
    box_bottom "$BLUE"

    printf '\n'
    box_top "$CYAN"
    box_row "$CYAN" "${WHITE}${B}🧠 MEMORIA RAM${R}"
    box_separator "$CYAN"
    box_row "$CYAN" "Total:       $(format_bytes "$total")"
    box_row "$CYAN" "Utilizada:   $(format_bytes "$used") (${mem_pct}%)"
    box_row "$CYAN" "Disponible:  $(format_bytes "$available")"
    box_row "$CYAN" "Estado:      $ram_status"
    box_bottom "$CYAN"

    printf '\n'
    box_top "$MAGENTA"
    box_row "$MAGENTA" "${WHITE}${B}💽 ALMACENAMIENTO${R}"
    box_separator "$MAGENTA"
    box_row "$MAGENTA" "Disco total:      $(format_bytes "$disk_total")"
    box_row "$MAGENTA" "Espacio usado:    $(format_bytes "$disk_used")"
    box_row "$MAGENTA" "Espacio libre:    $(format_bytes "$disk_free")"
    box_row "$MAGENTA" "Uso del disco:    ${disk_pct}%"
    box_row "$MAGENTA" "Estado:           $disk_status"
    box_bottom "$MAGENTA"

    printf '\n'
    box_top "$YELLOW"
    box_row "$YELLOW" "${WHITE}${B}🔄 MEMORIA SWAP${R}"
    box_separator "$YELLOW"
    box_row "$YELLOW" "Total:       $(format_bytes "$swap_total")"
    box_row "$YELLOW" "Utilizada:   $(format_bytes "$swap_used")"
    box_row "$YELLOW" "Libre:       $(format_bytes "$swap_free")"
    box_bottom "$YELLOW"

    printf '\n'
    printf '%b  ℹ️  Datos obtenidos directamente del sistema.%b\n' "$GRAY" "$R"
}

# --------------------------------------------------------------
# COMPROBACIONES INICIALES
# --------------------------------------------------------------

check_environment() {
    local missing=()
    local cmd

    if [[ $EUID -ne 0 ]]; then
        printf '%b✖ Ejecuta el script como root o con sudo.%b\n' "$RED" "$R"
        printf '%b  💡 Ejemplo: sudo bash cleanup-manager.sh%b\n' "$GRAY" "$R"
        return 1
    fi

    if ! command -v apt-get >/dev/null 2>&1; then
        printf '%b✖ Este script requiere Debian/Ubuntu con APT.%b\n' "$RED" "$R"
        return 1
    fi

    for cmd in awk sed python3 df du date find journalctl sysctl sync \
               apt-get hostname uptime rm tail sleep clear touch; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done

    if ((${#missing[@]} > 0)); then
        printf '%b✖ Faltan comandos: %s%b\n' "$RED" "${missing[*]}" "$R"
        return 1
    fi

    if [[ ! -r /proc/meminfo ]]; then
        printf '%b✖ No se puede leer /proc/meminfo.%b\n' "$RED" "$R"
        return 1
    fi

    if ! touch "$LOG_FILE" 2>/dev/null; then
        printf '%b✖ No se puede escribir el registro: %s%b\n' "$RED" "$LOG_FILE" "$R"
        return 1
    fi

    return 0
}

# --------------------------------------------------------------
# MÉTRICAS ANTES Y DESPUÉS
# --------------------------------------------------------------

capture_before() {
    MEM_BEFORE="$(safe_number "$(read_meminfo MemAvailable)")"
    CACHE_BEFORE="$(safe_number "$(read_meminfo Cached)")"
    DISK_BEFORE="$(safe_number "$(read_disk_used)")"
    APT_BEFORE="$(safe_number "$(read_directory_size /var/cache/apt/archives)")"
    TMP_BEFORE="$(safe_number "$(read_directory_size /tmp)")"
}

capture_after() {
    MEM_AFTER="$(safe_number "$(read_meminfo MemAvailable)")"
    CACHE_AFTER="$(safe_number "$(read_meminfo Cached)")"
    DISK_AFTER="$(safe_number "$(read_disk_used)")"
    APT_AFTER="$(safe_number "$(read_directory_size /var/cache/apt/archives)")"
    TMP_AFTER="$(safe_number "$(read_directory_size /tmp)")"
}

# --------------------------------------------------------------
# LIMPIEZA DE JOURNAL
# --------------------------------------------------------------

vacuum_journal() {
    local output rc

    output="$(journalctl --vacuum-time=3d 2>&1)"
    rc=$?

    printf '%s\n' "$output"

    JOURNAL_FREED="$(
        printf '%s\n' "$output" |
            sed -nE \
                's/.*freed[[:space:]]+([^[:space:]]+)[[:space:]]+of archived journals.*/\1/p' |
            tail -n 1
    )"

    [[ -n "$JOURNAL_FREED" ]] || JOURNAL_FREED="0 B"

    return "$rc"
}

# --------------------------------------------------------------
# LIMPIEZA SEGURA DE /tmp
# --------------------------------------------------------------

clean_tmp() {
    find /tmp -mindepth 1 -maxdepth 1 \
        -mmin "+${TMP_MAX_AGE}" \
        ! -name '.*' \
        -exec rm -rf -- {} +
}

# --------------------------------------------------------------
# LIMPIEZA COMPLETA
# --------------------------------------------------------------

perform_cleanup() {
    START_TIME="$(date +%s)"

    STEP_NAMES=()
    STEP_RESULTS=()
    STEP_DETAILS=()

    TOTAL_OK=0
    TOTAL_FAIL=0
    TOTAL_SKIP=0

    JOURNAL_FREED="0 B"

    capture_before
    header

    printf '\n'
    printf '%b  🚀 PREPARANDO MANTENIMIENTO%b\n' "$CYAN" "$R"

    box_top "$YELLOW"
    box_row "$YELLOW" "${WHITE}${B}🧹 LIMPIEZA AUTOMÁTICA${R}"
    box_separator "$YELLOW"
    box_row "$YELLOW" "${GREEN}01${R}  🔄 Sincronizar datos pendientes"
    box_row "$YELLOW" "${GREEN}02${R}  🧠 Liberar cachés recuperables del kernel"
    box_row "$YELLOW" "${GREEN}03${R}  📋 Limpiar journals archivados de más de 3 días"
    box_row "$YELLOW" "${GREEN}04${R}  📦 Limpiar paquetes descargados de APT"
    box_row "$YELLOW" "${GREEN}05${R}  🗑️  Retirar elementos antiguos de /tmp"
    box_separator "$YELLOW"
    box_row "$YELLOW" "${GRAY}ℹ️  Se mantienen los comandos y criterios originales.${R}"
    box_bottom "$YELLOW"

    printf '\n%b  ◈ Iniciando operaciones...%b\n' "$CYAN" "$R"

    run_step "🔄 Sincronización de datos" sync
    run_step "🧠 Liberación de caché del kernel" sysctl -w vm.drop_caches=3
    run_step "📋 Limpieza de journals archivados" vacuum_journal
    run_step "📦 Limpieza de paquetes APT" apt-get clean
    run_step "🗑️  Limpieza de temporales antiguos" clean_tmp

    capture_after
    show_final_report
}

# --------------------------------------------------------------
# INFORME FINAL
# --------------------------------------------------------------

show_final_report() {
    local end_time elapsed
    local mem_diff disk_diff apt_diff tmp_diff cache_diff

    end_time="$(date +%s)"
    elapsed=$((end_time - START_TIME))

    mem_diff=$((MEM_AFTER - MEM_BEFORE))
    disk_diff=$((DISK_BEFORE - DISK_AFTER))
    apt_diff=$((APT_BEFORE - APT_AFTER))
    tmp_diff=$((TMP_BEFORE - TMP_AFTER))
    cache_diff=$((CACHE_AFTER - CACHE_BEFORE))

    printf '\n\n'
    printf '%b  🏆 INFORME FINAL DE MANTENIMIENTO%b\n' "$GREEN" "$R"

    box_top "$GREEN"
    box_row "$GREEN" "$(center_text "${WHITE}${B}📋 RESUMEN DE OPERACIONES${R}" "$((BOX_WIDTH - 2))")"
    box_separator "$GREEN"

    box_row "$GREEN" "${GREEN}✔ Completadas: ${TOTAL_OK}${R}"
    box_row "$GREEN" "${RED}✖ Fallidas:    ${TOTAL_FAIL}${R}"
    box_row "$GREEN" "${YELLOW}↷ Omitidas:    ${TOTAL_SKIP}${R}"

    box_separator "$GREEN"
    box_row "$GREEN" "${WHITE}${B}📈 CAMBIOS OBSERVADOS${R}"
    box_separator "$GREEN"

    box_row "$GREEN" "RAM disponible antes:   $(format_bytes "$MEM_BEFORE")"
    box_row "$GREEN" "RAM disponible después: $(format_bytes "$MEM_AFTER")"

    if (( mem_diff >= 0 )); then
        box_row "$GREEN" "Variación RAM: +$(format_bytes "$mem_diff")"
    else
        box_row "$GREEN" "Variación RAM: -$(format_bytes "$((-mem_diff))")"
    fi

    box_row "$GREEN" "Caché archivos antes:   $(format_bytes "$CACHE_BEFORE")"
    box_row "$GREEN" "Caché archivos después: $(format_bytes "$CACHE_AFTER")"

    if (( disk_diff >= 0 )); then
        box_row "$GREEN" "Reducción uso de disco: +$(format_bytes "$disk_diff")"
    else
        box_row "$GREEN" "Cambio uso de disco: -$(format_bytes "$((-disk_diff))")"
    fi

    box_separator "$GREEN"
    box_row "$GREEN" "${WHITE}${B}📦 CACHÉ DE PAQUETES${R}"
    box_row "$GREEN" "APT antes:   $(format_bytes "$APT_BEFORE")"
    box_row "$GREEN" "APT después: $(format_bytes "$APT_AFTER")"

    if (( apt_diff >= 0 )); then
        box_row "$GREEN" "Reducción caché APT: $(format_bytes "$apt_diff")"
    else
        box_row "$GREEN" "Aumento caché APT: $(format_bytes "$((-apt_diff))")"
    fi

    box_separator "$GREEN"
    box_row "$GREEN" "${WHITE}${B}🗑️  ARCHIVOS TEMPORALES${R}"
    box_row "$GREEN" "Antes:   $(format_bytes "$TMP_BEFORE")"
    box_row "$GREEN" "Después: $(format_bytes "$TMP_AFTER")"

    if (( tmp_diff >= 0 )); then
        box_row "$GREEN" "Reducción /tmp: $(format_bytes "$tmp_diff")"
    else
        box_row "$GREEN" "Aumento /tmp: $(format_bytes "$((-tmp_diff))")"
    fi

    box_row "$GREEN" "Journals eliminados: ${JOURNAL_FREED}"

    box_separator "$GREEN"
    box_row "$GREEN" "${WHITE}${B}⏱️  EJECUCIÓN${R}"
    box_row "$GREEN" "Duración: ${elapsed} segundos"
    box_row "$GREEN" "Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
    box_bottom "$GREEN"

    printf '\n'
    printf '%b  💡 NOTAS DEL SISTEMA%b\n' "$CYAN" "$R"

    box_top "$CYAN"
    box_row "$CYAN" "ℹ️  La variación de RAM no garantiza memoria liberada."
    box_row "$CYAN" "⚠️  Vaciar cachés puede ralentizar accesos posteriores."
    box_row "$CYAN" "🗑️  /tmp elimina elementos antiguos no ocultos."
    box_row "$CYAN" "📋 Los journals eliminados dejan de estar disponibles."
    box_separator "$CYAN"
    box_row "$CYAN" "📄 Registro de operaciones:"
    box_row "$CYAN" "$LOG_FILE"
    box_bottom "$CYAN"

    log_message "Limpieza finalizada | OK=$TOTAL_OK FAIL=$TOTAL_FAIL SKIP=$TOTAL_SKIP | duración=${elapsed}s"

    printf '\n'
    box_top "$GREEN"
    box_row "$GREEN" "$(center_text "${GREEN}${B}✅ MANTENIMIENTO FINALIZADO${R}" "$((BOX_WIDTH - 2))")"
    box_bottom "$GREEN"
}

# --------------------------------------------------------------
# MENÚ PRINCIPAL
# --------------------------------------------------------------

main() {
    local option

    if ! check_environment; then
        exit 1
    fi

    while true; do
        header
        show_dashboard

        printf '\n'

        box_top "$CYAN"
        box_row "$CYAN" "$(center_text "${WHITE}${B}🎛️  CENTRO DE CONTROL${R}" "$((BOX_WIDTH - 2))")"
        box_separator "$CYAN"
        box_row "$CYAN" "${GREEN}[1]${R}  🚀 Ejecutar limpieza completa"
        box_row "$CYAN" "${BLUE}[2]${R}  📊 Información detallada del sistema"
        box_row "$CYAN" "${RED}[0]${R}  🚪 Salir del administrador"
        box_bottom "$CYAN"

        printf '\n'
        printf '%b  ➤ Selecciona una opción [0-2]: %b' "$CYAN" "$R"

        if ! read -r option; then
            printf '\n'
            exit 0
        fi

        case "$option" in
            1)
                perform_cleanup
                printf '\n'
                read -r -p "Presiona ENTER para volver al menú..." _
                ;;
            2)
                header
                show_system_info
                printf '\n'
                read -r -p "Presiona ENTER para volver al menú..." _
                ;;
            0)
                printf '\n%b  👋 Hasta pronto.%b\n' "$GREEN" "$R"
                exit 0
                ;;
            *)
                printf '\n%b  ⚠️  Opción inválida. Selecciona 0, 1 o 2.%b\n' "$YELLOW" "$R"
                sleep 1
                ;;
        esac
    done
}

main "$@"
