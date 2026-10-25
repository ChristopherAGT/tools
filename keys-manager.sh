#!/usr/bin/env bash

# ==============================================================
# KEY-MANAGER - CONFIGURADOR DE CLAVES SLOWDNS
# Autor: Christopher + ChatGPT
# Compatible con La Casita MX y ADMRufu 2.0
# Debian / Ubuntu
# ==============================================================

set -uo pipefail
export LC_ALL=C.UTF-8
umask 077

VERSION="v2.1"
PANEL_WIDTH=58
SERVICE_NAME=""
PROFILE_FILE="/etc/key-manager/slowdns-profile"
SCRIPT_NAME=""
INSTALLATION_NAME="No detectada"
INSTALLATION_TYPE=""
INSTALLATION_OK=0

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
# ARCHIVOS DE CLAVES
# --------------------------------------------------------------

PRIVKEY_FILES=()
PUBKEY_FILES=()

# --------------------------------------------------------------
# CONFIGURACIÓN DEL PERFIL
# --------------------------------------------------------------
#
# Se admiten perfiles con este formato:
#
# INSTALLATION=ADMRufu
# SERVICE=slowdns
#
# También se admite el formato antiguo, donde la primera línea
# contiene solamente el nombre de la instalación.
#
# Variables de entorno opcionales:
# KEY_MANAGER_INSTALLATION=ADMRufu
# KEY_MANAGER_SERVICE=slowdns
# --------------------------------------------------------------

PROFILE_INSTALLATION=""
PROFILE_SERVICE=""

read_profile() {
    local line=""
    local key=""
    local value=""
    local first_line=1

    PROFILE_INSTALLATION=""
    PROFILE_SERVICE=""

    [[ -f "$PROFILE_FILE" && -r "$PROFILE_FILE" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"

        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        if [[ "$line" == *=* ]]; then
            key="${line%%=*}"
            value="${line#*=}"

            key="${key//[[:space:]]/}"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"

            case "${key^^}" in
                INSTALLATION)
                    PROFILE_INSTALLATION="$value"
                    ;;
                SERVICE)
                    PROFILE_SERVICE="$value"
                    ;;
            esac
        elif (( first_line )); then
            # Compatibilidad con el perfil antiguo:
            # primera línea = nombre de la instalación.
            PROFILE_INSTALLATION="$line"
        fi

        first_line=0
    done < "$PROFILE_FILE"
}

# --------------------------------------------------------------
# UTILIDADES PARA LAS RUTAS
# --------------------------------------------------------------

add_key_pair() {
    local private_file="$1"
    local public_file="$2"
    local private_dir
    local public_dir

    private_dir="$(dirname "$private_file")"
    public_dir="$(dirname "$public_file")"

    # No inventar directorios de una instalación inexistente.
    [[ -d "$private_dir" ]] || return 0
    [[ -d "$public_dir" ]] || return 0

    PRIVKEY_FILES+=("$private_file")
    PUBKEY_FILES+=("$public_file")
}

# --------------------------------------------------------------
# DETECCIÓN DEL SERVICIO SYSTEMD
# --------------------------------------------------------------

unit_exists() {
    local unit="$1"

    systemctl cat "$unit" >/dev/null 2>&1
}

detect_service() {
    local candidate=""
    local requested_service="${KEY_MANAGER_SERVICE:-$PROFILE_SERVICE}"
    local -a candidates=()

    SERVICE_NAME=""

    # Si se especificó un servicio, respetarlo.
    if [[ -n "$requested_service" ]]; then
        if [[ "$requested_service" =~ ^[a-zA-Z0-9_.@-]+$ ]]; then
            if unit_exists "$requested_service"; then
                SERVICE_NAME="$requested_service"
                return 0
            fi
        fi

        printf '%b  ⚠ El servicio configurado no existe: %s%b\n' \
            "$YELLOW" "$requested_service" "$R"
    fi

    # Los nombres pueden variar según la instalación.
    case "$INSTALLATION_TYPE" in
        CASITA)
            candidates=(
                slowserver
                slowdns
            )
            ;;
        ADMRUFU)
            candidates=(
                slowdns
                slowserver
                slowdns-server
                dnstt-server
            )
            ;;
        *)
            candidates=(
                slowserver
                slowdns
                slowdns-server
                dnstt-server
            )
            ;;
    esac

    for candidate in "${candidates[@]}"; do
        if unit_exists "$candidate"; then
            SERVICE_NAME="$candidate"
            return 0
        fi
    done

    return 1
}

# --------------------------------------------------------------
# DETECCIÓN DE LA INSTALACIÓN
# --------------------------------------------------------------

detect_installation() {
    local preference=""
    local casita_available=0
    local admrufu_available=0

    PRIVKEY_FILES=()
    PUBKEY_FILES=()

    INSTALLATION_NAME="No detectada"
    INSTALLATION_TYPE=""
    INSTALLATION_OK=0
    SCRIPT_NAME=""
    SERVICE_NAME=""

    read_profile

    preference="${KEY_MANAGER_INSTALLATION:-$PROFILE_INSTALLATION}"
    preference="${preference,,}"

    # ----------------------------------------------------------
    # IDENTIFICAR INSTALACIONES DISPONIBLES
    # ----------------------------------------------------------

    if [[ -d /etc/VPS-MX/Slow/Key ]]; then
        casita_available=1
    fi

    if [[ -d /root/ADMRufu/slowdns ||
          -d /etc/ADMRufu2.0/etc/slowdns ]]; then
        admrufu_available=1
    fi

    # ----------------------------------------------------------
    # LA CASITA MX
    # ----------------------------------------------------------

    if [[ "$preference" == *"casita"* ||
          "$preference" == *"vps-mx"* ]]; then

        if (( casita_available )); then
            INSTALLATION_TYPE="CASITA"
        else
            printf '%b  ⚠ Se solicitó La Casita MX, pero no se encontró su directorio.%b\n' \
                "$YELLOW" "$R"
        fi
    fi

    # ----------------------------------------------------------
    # ADMRufu 2.0
    # ----------------------------------------------------------

    if [[ "$preference" == *"admrufu"* ]]; then
        if (( admrufu_available )); then
            INSTALLATION_TYPE="ADMRUFU"
        else
            printf '%b  ⚠ Se solicitó ADMRufu 2.0, pero no se encontraron sus rutas.%b\n' \
                "$YELLOW" "$R"
        fi
    fi

    # ----------------------------------------------------------
    # DETECCIÓN AUTOMÁTICA SI NO HAY PREFERENCIA VÁLIDA
    # ----------------------------------------------------------

    if [[ -z "$INSTALLATION_TYPE" ]]; then
        if (( casita_available )); then
            INSTALLATION_TYPE="CASITA"
        elif (( admrufu_available )); then
            INSTALLATION_TYPE="ADMRUFU"
        fi
    fi

    # ----------------------------------------------------------
    # ASIGNAR LAS RUTAS DE LA INSTALACIÓN SELECCIONADA
    # ----------------------------------------------------------

    case "$INSTALLATION_TYPE" in
        CASITA)
            INSTALLATION_NAME="La Casita MX"
            SCRIPT_NAME="La Casita MX"

            add_key_pair \
                "/etc/VPS-MX/Slow/Key/server.key" \
                "/etc/VPS-MX/Slow/Key/server.pub"
            ;;

        ADMRUFU)
            INSTALLATION_NAME="ADMRufu 2.0"
            SCRIPT_NAME="ADMRufu 2.0"

            # Primera ubicación: instalación bajo /root.
            add_key_pair \
                "/root/ADMRufu/slowdns/server.key" \
                "/root/ADMRufu/slowdns/server.pub"

            # Segunda ubicación: instalación bajo /etc.
            add_key_pair \
                "/etc/ADMRufu2.0/etc/slowdns/server.key" \
                "/etc/ADMRufu2.0/etc/slowdns/server.pub"
            ;;

        *)
            INSTALLATION_NAME="No detectada"
            SCRIPT_NAME="SlowDNS"
            return 1
            ;;
    esac

    if (( ${#PRIVKEY_FILES[@]} == 0 )); then
        printf '%b  ⚠ No hay directorios de claves disponibles para esta instalación.%b\n' \
            "$YELLOW" "$R"
        return 1
    fi

    INSTALLATION_OK=1

    # La detección del servicio es independiente de las claves.
    # Un fallo aquí no debe cerrar el configurador.
    if ! detect_service; then
        SERVICE_NAME=""
    fi

    return 0
}

# --------------------------------------------------------------
# UTILIDADES VISUALES
# --------------------------------------------------------------

repeat_char() {
    local char="$1"
    local count="$2"
    local result=""

    (( count < 0 )) && count=0

    printf -v result '%*s' "$count" ''
    result="${result// /$char}"

    printf '%s' "$result"
}

visible_width() {
    python3 -c '
import re
import sys
import unicodedata

text = sys.argv[1]
text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)

width = 0

for char in text:
    cp = ord(char)

    if char in "\r\n":
        continue

    if (
        unicodedata.combining(char)
        or cp == 0x200D
        or 0xFE00 <= cp <= 0xFE0F
        or 0x1F3FB <= cp <= 0x1F3FF
    ):
        continue

    width += 2 if (
        unicodedata.east_asian_width(char) in ("W", "F")
        or 0x1F000 <= cp <= 0x1FAFF
    ) else 1

print(width)
' "$1"
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

box_top() {
    local color="$1"

    printf '%b  ╭' "$color"
    repeat_char '─' "$PANEL_WIDTH"
    printf '╮%b\n' "$R"
}

box_bottom() {
    local color="$1"

    printf '%b  ╰' "$color"
    repeat_char '─' "$PANEL_WIDTH"
    printf '╯%b\n' "$R"
}

box_separator() {
    local color="$1"

    printf '%b  ├' "$color"
    repeat_char '─' "$PANEL_WIDTH"
    printf '┤%b\n' "$R"
}

box_row() {
    local color="$1"
    local content="$2"
    local width padding max_width

    max_width=$((PANEL_WIDTH - 2))
    width="$(visible_width "$content")"

    if (( width > max_width )); then
        printf '%b  │ %s%b\n' "$color" "$content" "$R"
        return
    fi

    padding=$((max_width - width))

    printf '  %b│%b ' "$color" "$R"
    printf '%b' "$content"
    printf '%*s' "$padding" ''
    printf ' %b│%b\n' "$color" "$R"
}

box_wrapped_row() {
    local color="$1"
    local content="$2"
    local max_width=$((PANEL_WIDTH - 2))
    local line part

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "$line" ]]; then
            box_row "$color" ""
            continue
        fi

        while (( $(visible_width "$line") > max_width )); do
            part="${line:0:max_width}"

            # Para rutas y claves ASCII, el ancho visible coincide
            # con el número de caracteres.
            box_row "$color" "$part"
            line="${line:${#part}}"
        done

        box_row "$color" "$line"
    done <<< "$content"
}

# --------------------------------------------------------------
# TÍTULO DEL DASHBOARD
# --------------------------------------------------------------

dashboard_title() {
    local title="ESTADO ACTUAL DE SLOWDNS"
    local title_width script_width spaces content

    title_width="$(visible_width "$title")"

    if [[ -z "$SCRIPT_NAME" ]]; then
        box_row "$BLUE" "${WHITE}${B}${title}${R}"
        return
    fi

    script_width="$(visible_width "$SCRIPT_NAME")"
    spaces=$((PANEL_WIDTH - 2 - title_width - script_width))

    if (( spaces < 1 )); then
        box_row "$BLUE" "${WHITE}${B}${title}${R}"
        return
    fi

    printf -v content '%s%*s%s' \
        "${WHITE}${B}${title}${R}" \
        "$spaces" '' \
        "${CYAN}${B}${SCRIPT_NAME}${R}"

    box_row "$BLUE" "$content"
}

pause_menu() {
    printf '\n%b  Presiona ENTER para regresar al menú...%b' "$GRAY" "$R"
    read -r _ || true
}

# --------------------------------------------------------------
# COMPROBACIONES DEL ENTORNO
# --------------------------------------------------------------

check_environment() {
    local cmd

    if (( EUID != 0 )); then
        printf '%b  ✖ Ejecuta este administrador como root.%b\n' "$RED" "$R"
        return 1
    fi

    for cmd in systemctl python3 awk date mktemp chmod mv mkdir dirname cat rm sleep grep; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            printf '%b  ✖ Falta el comando requerido: %s%b\n' "$RED" "$cmd" "$R"
            return 1
        fi
    done

    return 0
}

# --------------------------------------------------------------
# VALIDAR QUE EXISTA UN SERVICIO
# --------------------------------------------------------------

require_service() {
    if [[ -z "$SERVICE_NAME" ]]; then
        printf '\n%b  ✖ No se detectó un servicio SlowDNS compatible.%b\n' "$RED" "$R"
        printf '%b  No se ejecutará ningún reinicio.%b\n' "$YELLOW" "$R"
        printf '%b  Revisa las unidades con: systemctl list-unit-files --type=service%b\n' "$GRAY" "$R"
        return 1
    fi

    if ! unit_exists "$SERVICE_NAME"; then
        printf '\n%b  ✖ No se encontró la unidad %s.service.%b\n' \
            "$RED" "$SERVICE_NAME" "$R"
        return 1
    fi

    return 0
}

# --------------------------------------------------------------
# ESTADO DE LOS ARCHIVOS
# --------------------------------------------------------------

count_files() {
    local count=0
    local file

    for file in "$@"; do
        [[ -s "$file" ]] && ((count += 1))
    done

    printf '%s\n' "$count"
}

service_status() {
    if [[ -z "$SERVICE_NAME" ]] || ! unit_exists "$SERVICE_NAME"; then
        printf '%bNO DETECTADO%b' "$RED" "$R"
    elif systemctl is-active --quiet "$SERVICE_NAME"; then
        printf '%bACTIVO%b' "$GREEN" "$R"
    elif systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        printf '%bDETENIDO%b' "$YELLOW" "$R"
    else
        printf '%bINACTIVO%b' "$RED" "$R"
    fi
}

get_first_key() {
    local file

    for file in "$@"; do
        if [[ -s "$file" && -r "$file" ]]; then
            cat -- "$file"
            return 0
        fi
    done

    printf '%s' "No disponible"
}

# --------------------------------------------------------------
# ENCABEZADO PRINCIPAL
# --------------------------------------------------------------

header() {
    clear 2>/dev/null || true

    printf '\n'

    box_top "$CYAN"
    box_row "$CYAN" ""
    box_row "$CYAN" "$(center_text "${CYAN}${B}KEY-MANAGER${R}" "$((PANEL_WIDTH - 2))")"
    box_row "$CYAN" "$(center_text "${WHITE}${B}CONFIGURADOR DE CLAVES SLOWDNS${R}" "$((PANEL_WIDTH - 2))")"
    box_row "$CYAN" "$(center_text "${GRAY}Gestión · Validación · Reinicio${R}" "$((PANEL_WIDTH - 2))")"
    box_row "$CYAN" ""
    box_bottom "$CYAN"

    printf '\n'

    box_top "$GRAY"
    box_row "$GRAY" "${GREEN}● Administrador preparado${R}                         ${YELLOW}Versión ${VERSION}${R}"
    box_bottom "$GRAY"
}

# --------------------------------------------------------------
# DASHBOARD
# --------------------------------------------------------------

show_dashboard() {
    local priv_count pub_count
    local privkey pubkey

    priv_count="$(count_files "${PRIVKEY_FILES[@]}")"
    pub_count="$(count_files "${PUBKEY_FILES[@]}")"

    privkey="$(get_first_key "${PRIVKEY_FILES[@]}")"
    pubkey="$(get_first_key "${PUBKEY_FILES[@]}")"

    printf '\n%b  ◈ PANEL DE MONITOREO%b\n' "$BLUE" "$R"

    box_top "$BLUE"
    dashboard_title
    box_separator "$BLUE"
    box_row "$BLUE" "Instalación:       ${INSTALLATION_NAME}"
    box_row "$BLUE" "Servicio:          ${SERVICE_NAME:-No detectado}"
    box_row "$BLUE" "Estado:            $(service_status)"
    box_row "$BLUE" "Claves privadas:   ${priv_count}/${#PRIVKEY_FILES[@]} disponibles"
    box_row "$BLUE" "Claves públicas:   ${pub_count}/${#PUBKEY_FILES[@]} disponibles"

    box_separator "$BLUE"
    box_row "$BLUE" "${MAGENTA}${B}Clave Privada Actual:${R}"
    box_wrapped_row "$BLUE" "$privkey"

    box_separator "$BLUE"
    box_row "$BLUE" "${CYAN}${B}Clave Pública Actual:${R}"
    box_wrapped_row "$BLUE" "$pubkey"

    box_bottom "$BLUE"
}

# --------------------------------------------------------------
# VALIDAR RUTAS DE CLAVES
# --------------------------------------------------------------

check_key_targets() {
    local i
    local private_dir
    local public_dir

    if (( INSTALLATION_OK == 0 )) ||
       (( ${#PRIVKEY_FILES[@]} == 0 )) ||
       (( ${#PUBKEY_FILES[@]} == 0 )); then

        printf '\n%b  ✖ No se detectó una instalación compatible.%b\n' "$RED" "$R"
        return 1
    fi

    if (( ${#PRIVKEY_FILES[@]} != ${#PUBKEY_FILES[@]} )); then
        printf '\n%b  ✖ Las rutas privadas y públicas no coinciden.%b\n' "$RED" "$R"
        return 1
    fi

    for i in "${!PRIVKEY_FILES[@]}"; do
        private_dir="$(dirname "${PRIVKEY_FILES[$i]}")"
        public_dir="$(dirname "${PUBKEY_FILES[$i]}")"

        if [[ ! -d "$private_dir" || ! -d "$public_dir" ]]; then
            printf '\n%b  ✖ No existe el directorio de claves esperado.%b\n' "$RED" "$R"
            return 1
        fi
    done

    return 0
}

# --------------------------------------------------------------
# GUARDAR CLAVES
# --------------------------------------------------------------

ingresar_claves() {
    local private_key=""
    local public_key=""
    local file=""
    local dir=""
    local tmp=""
    local i
    local failed=0

    header

    printf '\n%b  ◈ CONFIGURACIÓN DE CLAVES%b\n' "$CYAN" "$R"

    box_top "$YELLOW"
    box_row "$YELLOW" "${WHITE}${B}INGRESAR NUEVAS CLAVES${R}"
    box_separator "$YELLOW"
    box_row "$YELLOW" "Instalación: ${INSTALLATION_NAME}"
    box_row "$YELLOW" "Las claves se aplicarán a las rutas detectadas."
    box_row "$YELLOW" "Privada: permisos 600 | Pública: permisos 644"
    box_bottom "$YELLOW"

    if ! check_key_targets; then
        pause_menu
        return 0
    fi

    printf '\n%b  ⚠ Cambiar claves puede desconectar clientes.%b\n\n' "$YELLOW" "$R"

    read -r -s -p "  Clave PRIVADA: " private_key || {
        printf '\n'
        pause_menu
        return 0
    }
    printf '\n'

    read -r -s -p "  Clave PÚBLICA: " public_key || {
        printf '\n'
        unset private_key
        pause_menu
        return 0
    }
    printf '\n'

    if [[ -z "$private_key" || -z "$public_key" ]]; then
        printf '\n%b  ✖ Ambas claves son obligatorias.%b\n' "$RED" "$R"
        unset private_key public_key
        pause_menu
        return 0
    fi

    # No se exige que los archivos ya existan.
    # Solo se exige que los directorios de la instalación existan.

    for i in "${!PRIVKEY_FILES[@]}"; do
        file="${PRIVKEY_FILES[$i]}"
        dir="$(dirname "$file")"

        tmp="$(mktemp "$dir/.server.key.XXXXXX")" || {
            printf '%b  ✖ No se pudo crear el archivo temporal privado.%b\n' "$RED" "$R"
            failed=1
            continue
        }

        if printf '%s\n' "$private_key" > "$tmp" &&
           chmod 600 "$tmp" &&
           mv -f -- "$tmp" "$file"; then
            printf '%b  ✔ Clave privada actualizada: %s%b\n' "$GREEN" "$file" "$R"
        else
            rm -f -- "$tmp"
            printf '%b  ✖ Error al guardar la clave privada: %s%b\n' "$RED" "$file" "$R"
            failed=1
        fi
    done

    for i in "${!PUBKEY_FILES[@]}"; do
        file="${PUBKEY_FILES[$i]}"
        dir="$(dirname "$file")"

        tmp="$(mktemp "$dir/.server.pub.XXXXXX")" || {
            printf '%b  ✖ No se pudo crear el archivo temporal público.%b\n' "$RED" "$R"
            failed=1
            continue
        }

        if printf '%s\n' "$public_key" > "$tmp" &&
           chmod 644 "$tmp" &&
           mv -f -- "$tmp" "$file"; then
            printf '%b  ✔ Clave pública actualizada: %s%b\n' "$GREEN" "$file" "$R"
        else
            rm -f -- "$tmp"
            printf '%b  ✖ Error al guardar la clave pública: %s%b\n' "$RED" "$file" "$R"
            failed=1
        fi
    done

    unset private_key public_key

    if (( failed != 0 )); then
        printf '\n%b  ⚠ No se pudieron guardar todas las claves.%b\n' "$YELLOW" "$R"
        printf '%b  No se reiniciará el servicio automáticamente.%b\n' "$YELLOW" "$R"
        pause_menu
        return 0
    fi

    printf '\n%b  ✔ Archivos de claves actualizados.%b\n' "$GREEN" "$R"

    if require_service; then
        printf '\n%b  Reiniciando %s...%b\n' "$CYAN" "$SERVICE_NAME" "$R"

        if systemctl restart "$SERVICE_NAME"; then
            sleep 1

            if systemctl is-active --quiet "$SERVICE_NAME"; then
                printf '%b  ✔ Claves aplicadas y servicio activo.%b\n' "$GREEN" "$R"
            else
                printf '%b  ⚠ El servicio no quedó activo.%b\n' "$YELLOW" "$R"
                printf '%b  Revisa: journalctl -u %s -n 50 --no-pager%b\n' \
                    "$YELLOW" "$SERVICE_NAME" "$R"
            fi
        else
            printf '%b  ✖ Falló el reinicio del servicio.%b\n' "$RED" "$R"
        fi
    else
        printf '%b  ⚠ Las claves se guardaron, pero no se reinició ningún servicio.%b\n' "$YELLOW" "$R"
    fi

    pause_menu
}

# --------------------------------------------------------------
# MOSTRAR CLAVES ACTUALES
# --------------------------------------------------------------

mostrar_claves() {
    local file
    local key

    header

    printf '\n%b  ◈ CLAVES ACTUALES%b\n' "$BLUE" "$R"

    if ! check_key_targets; then
        pause_menu
        return 0
    fi

    box_top "$BLUE"
    box_row "$BLUE" "${WHITE}${B}ARCHIVOS CONFIGURADOS${R}"
    box_separator "$BLUE"

    for file in "${PRIVKEY_FILES[@]}"; do
        box_row "$BLUE" "${MAGENTA}Clave privada:${R}"
        box_wrapped_row "$BLUE" "$file"

        if [[ -s "$file" && -r "$file" ]]; then
            box_row "$BLUE" "${GREEN}Estado: disponible${R}"
            key="$(cat -- "$file")"
            box_wrapped_row "$BLUE" "$key"
        else
            box_row "$BLUE" "${RED}Estado: ausente, vacío o ilegible${R}"
        fi

        box_separator "$BLUE"
    done

    for file in "${PUBKEY_FILES[@]}"; do
        box_row "$BLUE" "${CYAN}Clave pública:${R}"
        box_wrapped_row "$BLUE" "$file"

        if [[ -s "$file" && -r "$file" ]]; then
            box_row "$BLUE" "${GREEN}Estado: disponible${R}"
            key="$(cat -- "$file")"
            box_wrapped_row "$BLUE" "$key"
        else
            box_row "$BLUE" "${RED}Estado: ausente, vacío o ilegible${R}"
        fi

        box_separator "$BLUE"
    done

    box_bottom "$BLUE"

    printf '\n%b  ⚠ La clave privada se muestra en pantalla.%b\n' "$YELLOW" "$R"

    pause_menu
}

# --------------------------------------------------------------
# REINICIAR SERVICIO
# --------------------------------------------------------------

reiniciar_slowdns() {
    header

    printf '\n%b  ◈ REINICIO DEL SERVICIO%b\n' "$CYAN" "$R"

    box_top "$YELLOW"
    box_row "$YELLOW" "${WHITE}${B}SERVICIO SLOWDNS${R}"
    box_separator "$YELLOW"
    box_row "$YELLOW" "Instalación: ${INSTALLATION_NAME}"
    box_row "$YELLOW" "Servicio: ${SERVICE_NAME:-No detectado}"
    box_row "$YELLOW" "Operación: reinicio controlado"
    box_bottom "$YELLOW"

    if ! require_service; then
        pause_menu
        return 0
    fi

    printf '\n%b  Ejecutando reinicio...%b\n' "$CYAN" "$R"

    if systemctl restart "$SERVICE_NAME"; then
        sleep 1

        if systemctl is-active --quiet "$SERVICE_NAME"; then
            printf '\n%b  ✔ El servicio está activo.%b\n' "$GREEN" "$R"
        else
            printf '\n%b  ✖ El servicio no quedó activo.%b\n' "$RED" "$R"
            printf '%b  Consulta: journalctl -u %s -n 50 --no-pager%b\n' \
                "$YELLOW" "$SERVICE_NAME" "$R"
        fi
    else
        printf '\n%b  ✖ No se pudo reiniciar el servicio.%b\n' "$RED" "$R"
    fi

    pause_menu
}

# --------------------------------------------------------------
# MENÚ PRINCIPAL
# --------------------------------------------------------------

menu_principal() {
    local opcion=""

    if ! check_environment; then
        printf '\n'
        pause_menu
        return 1
    fi

    # Detectar la instalación sin cerrar el panel si falla.
    detect_installation || true

    while true; do
        # Volver a detectar el servicio y las rutas en cada vuelta.
        detect_installation || true

        header
        show_dashboard

        printf '\n'

        box_top "$CYAN"
        box_row "$CYAN" "$(center_text "${WHITE}${B}CENTRO DE CONTROL${R}" "$((PANEL_WIDTH - 2))")"
        box_separator "$CYAN"
        box_row "$CYAN" "${GREEN}[1]${R}  Ingresar nuevas claves"
        box_row "$CYAN" "${BLUE}[2]${R}  Consultar archivos de claves"
        box_row "$CYAN" "${YELLOW}[3]${R}  Reiniciar servicio SlowDNS"
        box_row "$CYAN" "${RED}[0]${R}  Salir del administrador"
        box_bottom "$CYAN"

        printf '\n%b  ➤ Selecciona una opción [0-3]: %b' "$CYAN" "$R"

        if ! IFS= read -r opcion; then
            printf '\n%b  Entrada del terminal cerrada.%b\n' "$YELLOW" "$R"
            return 0
        fi

        case "$opcion" in
            1)
                ingresar_claves
                ;;
            2)
                mostrar_claves
                ;;
            3)
                reiniciar_slowdns
                ;;
            0)
                printf '\n%b  Hasta pronto.%b\n' "$GREEN" "$R"
                return 0
                ;;
            *)
                printf '\n%b  ⚠ Opción inválida.%b\n' "$YELLOW" "$R"
                sleep 1
                ;;
        esac
    done
}

# --------------------------------------------------------------
# INICIO
# --------------------------------------------------------------

main() {
    if (( EUID != 0 )); then
        printf '%b  ✖ Ejecuta este administrador como root.%b\n' "$RED" "$R"
        printf '%b  Ejemplo: sudo bash key-manager.sh%b\n' "$GRAY" "$R"
        return 1
    fi

    menu_principal "$@"
}

main "$@"
