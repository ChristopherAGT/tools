#!/usr/bin/env bash

# ==============================================================
# KEY-MANAGER - CONFIGURADOR DE CLAVES SLOWDNS
# Autor: Christopher + ChatGPT
# Interfaz profesional inspirada en Linux Cleanup Manager v1.0
# Compatible con Debian / Ubuntu
# ==============================================================

set -uo pipefail
export LC_ALL=C.UTF-8
umask 077

VERSION="v2.0"
PANEL_WIDTH=58
SERVICE_NAME="slowdns"
PROFILE_FILE="/etc/key-manager/slowdns-profile"
SCRIPT_NAME=""

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
#
# Las rutas se seleccionan automáticamente según la instalación.
# ADMRufu 2.0 conserva sus dos ubicaciones originales.
# La Casita MX utiliza exclusivamente sus rutas VPS-MX.
# --------------------------------------------------------------

PRIVKEY_FILES=()
PUBKEY_FILES=()

# --------------------------------------------------------------
# DETECCIÓN DE LA INSTALACIÓN
# --------------------------------------------------------------

detect_installation() {
    local detected_name=""

    # ----------------------------------------------------------
    # LA CASITA MX
    # Firma: directorio de claves utilizado por VPS-MX.
    # ----------------------------------------------------------

    if [[ -d "/etc/VPS-MX/Slow/Key" ||
          -f "/etc/VPS-MX/Slow/Key/server.key" ||
          -f "/etc/VPS-MX/Slow/Key/server.pub" ]]; then

        detected_name="La Casita MX"

        PRIVKEY_FILES=(
            "/etc/VPS-MX/Slow/Key/server.key"
        )

        PUBKEY_FILES=(
            "/etc/VPS-MX/Slow/Key/server.pub"
        )

    # ----------------------------------------------------------
    # ADMRufu 2.0
    # Firma: directorios característicos de ADMRufu.
    # ----------------------------------------------------------

    elif [[ -d "/etc/ADMRufu2.0" ||
            -d "/root/ADMRufu/slowdns" ]]; then

        detected_name="ADMRufu 2.0"

        PRIVKEY_FILES=(
            "/root/ADMRufu/slowdns/server.key"
            "/etc/ADMRufu2.0/etc/slowdns/server.key"
        )

        PUBKEY_FILES=(
            "/root/ADMRufu/slowdns/server.pub"
            "/etc/ADMRufu2.0/etc/slowdns/server.pub"
        )

    # ----------------------------------------------------------
    # PERFIL EXPLÍCITO
    # Se utiliza si no se reconoce ninguna de las instalaciones.
    # ----------------------------------------------------------

    elif [[ -f "$PROFILE_FILE" && -r "$PROFILE_FILE" ]]; then
        IFS= read -r detected_name < "$PROFILE_FILE" || true
        detected_name="${detected_name%$'\r'}"

        if [[ ! "$detected_name" =~ ^[[:alnum:]_.[:space:]-]+$ ]]; then
            detected_name=""
        fi
    fi

    SCRIPT_NAME="$detected_name"
}

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

# Calcula el ancho visible sin contar secuencias ANSI.
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
        # Las cadenas largas deben pasar por box_wrapped_row.
        printf '%b  │ %s%b\n' "$color" "$content" "$R"
        return
    fi

    padding=$((max_width - width))

    printf '  %b│%b ' "$color" "$R"
    printf '%b' "$content"
    printf '%*s' "$padding" ''
    printf ' %b│%b\n' "$color" "$R"
}

# Divide textos largos en filas para conservar los bordes.
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

        while (( ${#line} > max_width )); do
            part="${line:0:max_width}"
            box_row "$color" "$part"
            line="${line:max_width}"
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
# COMPROBACIONES
# --------------------------------------------------------------

check_environment() {
    if (( EUID != 0 )); then
        printf '%b  ✖ Ejecuta este administrador como root.%b\n' "$RED" "$R"
        return 1
    fi

    local cmd

    for cmd in systemctl python3 awk date mktemp chmod mv mkdir dirname cat rm sleep; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            printf '%b  ✖ Falta el comando requerido: %s%b\n' "$RED" "$cmd" "$R"
            return 1
        fi
    done

    if [[ ${#PRIVKEY_FILES[@]} -eq 0 || ${#PUBKEY_FILES[@]} -eq 0 ]]; then
        printf '%b  ✖ No se reconoció una instalación compatible de SlowDNS.%b\n' "$RED" "$R"
        printf '%b  No se modificarán archivos de claves.%b\n' "$YELLOW" "$R"
        return 1
    fi

    if ! systemctl cat "$SERVICE_NAME" >/dev/null 2>&1; then
        printf '%b  ⚠ No se encontró la unidad %s.service.%b\n' "$YELLOW" "$SERVICE_NAME" "$R"
        printf '%b  Verifica el nombre del servicio antes de continuar.%b\n' "$YELLOW" "$R"
        return 1
    fi

    return 0
}

# --------------------------------------------------------------
# ESTADO DE LOS ARCHIVOS
# --------------------------------------------------------------

count_files() {
    local files=("$@")
    local count=0
    local file

    for file in "${files[@]}"; do
        [[ -s "$file" ]] && ((count += 1))
    done

    printf '%s\n' "$count"
}

service_status() {
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        printf '%bACTIVO%b' "$GREEN" "$R"
    elif systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        printf '%bDETENIDO%b' "$YELLOW" "$R"
    else
        printf '%bNO DISPONIBLE%b' "$RED" "$R"
    fi
}

# Obtiene la primera clave disponible y legible.
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
    box_row "$BLUE" "Servicio:          $(service_status)"
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
# GUARDAR CLAVES
# --------------------------------------------------------------

ingresar_claves() {
    local PRIVKEY PUBKEY file dir tmp
    local failed=0
    local i

    header

    printf '\n%b  ◈ CONFIGURACIÓN DE CLAVES%b\n' "$CYAN" "$R"

    box_top "$YELLOW"
    box_row "$YELLOW" "${WHITE}${B}INGRESAR NUEVAS CLAVES${R}"
    box_separator "$YELLOW"
    box_row "$YELLOW" "Se actualizarán las rutas de la instalación reconocida."
    box_row "$YELLOW" "La clave privada se guardará con permisos 600."
    box_bottom "$YELLOW"

    printf '\n%b  Paso 1: Ingresar las claves%b\n\n' "$CYAN" "$R"

    read -r -s -p "  Clave PRIVADA: " PRIVKEY || {
        printf '\n'
        return
    }
    printf '\n'

    read -r -s -p "  Clave PÚBLICA: " PUBKEY || {
        printf '\n'
        return
    }
    printf '\n'

    if [[ -z "$PRIVKEY" || -z "$PUBKEY" ]]; then
        printf '\n%b  ✖ Ambas claves son obligatorias.%b\n' "$RED" "$R"
        unset PRIVKEY PUBKEY
        pause_menu
        return
    fi

    # Verificar que las claves configuradas ya existan.
    # Evita crear directorios de claves en rutas equivocadas.
    for file in "${PRIVKEY_FILES[@]}" "${PUBKEY_FILES[@]}"; do
        if [[ ! -f "$file" ]]; then
            printf '\n%b  ✖ No existe el archivo esperado: %s%b\n' "$RED" "$file" "$R"
            printf '%b  No se guardaron las claves.%b\n' "$YELLOW" "$R"
            unset PRIVKEY PUBKEY
            pause_menu
            return
        fi
    done

    printf '\n%b  Paso 2: Guardando archivos...%b\n' "$CYAN" "$R"

    for i in "${!PRIVKEY_FILES[@]}"; do
        file="${PRIVKEY_FILES[$i]}"
        dir="$(dirname "$file")"

        tmp="$(mktemp "$dir/.server.key.XXXXXX")" || {
            printf '%b  ✖ No se pudo crear un archivo temporal.%b\n' "$RED" "$R"
            failed=1
            continue
        }

        if printf '%s\n' "$PRIVKEY" > "$tmp" &&
           chmod 600 "$tmp" &&
           mv -f -- "$tmp" "$file"; then
            printf '%b  ✔ Privada actualizada: %s%b\n' "$GREEN" "$file" "$R"
        else
            rm -f -- "$tmp"
            printf '%b  ✖ Error al guardar: %s%b\n' "$RED" "$file" "$R"
            failed=1
        fi
    done

    for i in "${!PUBKEY_FILES[@]}"; do
        file="${PUBKEY_FILES[$i]}"
        dir="$(dirname "$file")"

        tmp="$(mktemp "$dir/.server.pub.XXXXXX")" || {
            printf '%b  ✖ No se pudo crear un archivo temporal.%b\n' "$RED" "$R"
            failed=1
            continue
        }

        if printf '%s\n' "$PUBKEY" > "$tmp" &&
           chmod 644 "$tmp" &&
           mv -f -- "$tmp" "$file"; then
            printf '%b  ✔ Pública actualizada: %s%b\n' "$GREEN" "$file" "$R"
        else
            rm -f -- "$tmp"
            printf '%b  ✖ Error al guardar: %s%b\n' "$RED" "$file" "$R"
            failed=1
        fi
    done

    unset PRIVKEY PUBKEY

    if (( failed != 0 )); then
        printf '\n%b  ⚠ Algunas claves no pudieron guardarse.%b\n' "$YELLOW" "$R"
        printf '%b  El servicio no se reiniciará automáticamente.%b\n' "$YELLOW" "$R"
        pause_menu
        return
    fi

    printf '\n%b  Paso 3: Reiniciando SlowDNS...%b\n' "$CYAN" "$R"

    if systemctl restart "$SERVICE_NAME"; then
        sleep 1

        if systemctl is-active --quiet "$SERVICE_NAME"; then
            printf '\n%b  ✔ Claves guardadas y servicio activo.%b\n' "$GREEN" "$R"
        else
            printf '\n%b  ✖ El servicio no quedó activo.%b\n' "$RED" "$R"
            printf '%b  Consulta: journalctl -u %s -n 50 --no-pager%b\n' "$YELLOW" "$SERVICE_NAME" "$R"
        fi
    else
        printf '\n%b  ✖ Falló el reinicio de SlowDNS.%b\n' "$RED" "$R"
        printf '%b  Consulta: journalctl -u %s -n 50 --no-pager%b\n' "$YELLOW" "$SERVICE_NAME" "$R"
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
    box_row "$YELLOW" "Servicio: ${SERVICE_NAME}"
    box_row "$YELLOW" "Operación: reinicio controlado"
    box_bottom "$YELLOW"

    printf '\n%b  Ejecutando reinicio...%b\n' "$CYAN" "$R"

    if systemctl restart "$SERVICE_NAME"; then
        sleep 1

        if systemctl is-active --quiet "$SERVICE_NAME"; then
            printf '\n%b  ✔ SlowDNS está activo y funcionando.%b\n' "$GREEN" "$R"
        else
            printf '\n%b  ✖ El servicio no quedó activo.%b\n' "$RED" "$R"
            printf '%b  Consulta: journalctl -u %s -n 50 --no-pager%b\n' "$YELLOW" "$SERVICE_NAME" "$R"
        fi
    else
        printf '\n%b  ✖ No se pudo reiniciar el servicio.%b\n' "$RED" "$R"
        printf '%b  Verifica que exista %s.service.%b\n' "$YELLOW" "$SERVICE_NAME" "$R"
    fi

    pause_menu
}

# --------------------------------------------------------------
# MENÚ PRINCIPAL
# --------------------------------------------------------------

menu_principal() {
    local opcion

    detect_installation

    if ! check_environment; then
        exit 1
    fi

    while true; do
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

        if ! read -r opcion; then
            printf '\n'
            exit 0
        fi

        case "$opcion" in
            1) ingresar_claves ;;
            2) mostrar_claves ;;
            3) reiniciar_slowdns ;;
            0)
                printf '\n%b  Hasta pronto.%b\n' "$GREEN" "$R"
                exit 0
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

menu_principal "$@"
