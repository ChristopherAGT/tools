#!/usr/bin/env bash

# ==============================================================
# VPS NETWORK RECOVERY
# Automatic Network Diagnostics & Safe Recovery
# Version: 1.0.0
#
# Compatible con sistemas Linux que utilicen:
#   - Netplan
#   - systemd-networkd
#   - NetworkManager
#   - ifupdown
#
# Funciones:
#   - Diagnóstico de red
#   - Detección de interfaces
#   - Diagnóstico de rutas y DNS
#   - Detección de inconsistencias en Netplan
#   - Reparaciones automáticas conservadoras
#   - Copias de seguridad
#   - Registro de operaciones
#   - Informe final
#
# IMPORTANTE:
# No puede garantizar la recuperación de todos los VPS.
# No inventa IP, gateway ni parámetros del proveedor.
# ==============================================================

set -uo pipefail
umask 077
export LC_ALL=C

VERSION="1.0.0"

BACKUP_ROOT="/var/backups/vps-network-recovery"
LOG_ROOT="/var/log/vps-network-recovery"

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
LOG_FILE="${LOG_ROOT}/recovery-${TIMESTAMP}.log"
REPORT_FILE="${LOG_ROOT}/report-${TIMESTAMP}.txt"

declare -a DIAGNOSTICS=()
declare -a ACTIONS=()
declare -a WARNINGS=()

ERRORS=0
CHANGES=0
REPAIRS=0

mkdir -p "$BACKUP_ROOT" "$LOG_ROOT" || {
    printf 'ERROR: No se pudieron crear los directorios de trabajo.\n'
    exit 1
}

chmod 700 "$BACKUP_ROOT" "$LOG_ROOT" 2>/dev/null || true

# ==============================================================
# COLORES
# ==============================================================

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    WHITE='\033[1;37m'
    DIM='\033[2m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    WHITE=''
    DIM=''
    RESET=''
fi

# ==============================================================
# FUNCIONES GENERALES
# ==============================================================

log() {
    local level="$1"
    shift

    local message="$*"

    printf '[%s] [%s] %s\n' \
        "$(date '+%F %T')" "$level" "$message" >> "$LOG_FILE"

    case "$level" in
        OK)
            printf '%b[OK]%b %s\n' "$GREEN" "$RESET" "$message"
            ;;
        WARN)
            printf '%b[AVISO]%b %s\n' "$YELLOW" "$RESET" "$message"
            ;;
        ERROR)
            printf '%b[ERROR]%b %s\n' "$RED" "$RESET" "$message"
            ;;
        ACTION)
            printf '%b[REPARACIÓN]%b %s\n' "$CYAN" "$RESET" "$message"
            ;;
        INFO)
            printf '%b[INFO]%b %s\n' "$BLUE" "$RESET" "$message"
            ;;
        *)
            printf '%s\n' "$message"
            ;;
    esac
}

add_diagnostic() {
    DIAGNOSTICS+=("$1")
}

add_action() {
    ACTIONS+=("$1")
}

add_warning() {
    WARNINGS+=("$1")
}

has_command() {
    command -v "$1" >/dev/null 2>&1
}

run_capture() {
    "$@" 2>&1
}

# ==============================================================
# COMPROBACIONES INICIALES
# ==============================================================

check_privileges() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        log ERROR "Este script debe ejecutarse como root."
        log INFO "Ejemplo: sudo bash vps-network-recovery.sh"
        exit 1
    fi
}

detect_os() {
    OS_ID="unknown"
    OS_NAME="Linux"
    OS_VERSION="unknown"

    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release

        OS_ID="${ID:-unknown}"
        OS_NAME="${PRETTY_NAME:-Linux}"
        OS_VERSION="${VERSION_ID:-unknown}"
    fi

    add_diagnostic "Sistema operativo: ${OS_NAME}"
    log INFO "Sistema detectado: ${OS_NAME}"
}

detect_virtualization() {
    VIRT="unknown"

    if has_command systemd-detect-virt; then
        VIRT="$(systemd-detect-virt 2>/dev/null || true)"
    fi

    [[ -n "$VIRT" ]] || VIRT="unknown"

    add_diagnostic "Virtualización: ${VIRT}"
    log INFO "Entorno de virtualización: ${VIRT}"
}

# ==============================================================
# DETECCIÓN DE GESTORES DE RED
# ==============================================================

detect_network_managers() {
    NETWORK_MANAGERS=()

    if has_command netplan; then
        NETWORK_MANAGERS+=("netplan")
    fi

    if systemctl is-active --quiet systemd-networkd 2>/dev/null; then
        NETWORK_MANAGERS+=("systemd-networkd")
    fi

    if systemctl is-active --quiet NetworkManager 2>/dev/null; then
        NETWORK_MANAGERS+=("NetworkManager")
    fi

    if [[ -f /etc/network/interfaces ]]; then
        NETWORK_MANAGERS+=("ifupdown-config")
    fi

    if [[ ${#NETWORK_MANAGERS[@]} -eq 0 ]]; then
        NETWORK_MANAGERS+=("desconocido")
    fi

    add_diagnostic \
        "Gestores o configuraciones detectados: ${NETWORK_MANAGERS[*]}"

    log INFO "Configuración de red: ${NETWORK_MANAGERS[*]}"
}

# ==============================================================
# DETECCIÓN DE INTERFACES
# ==============================================================

collect_interfaces() {
    INTERFACES=()
    PHYSICAL_INTERFACES=()

    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        [[ "$name" == "lo" ]] && continue

        INTERFACES+=("$name")

        if [[ -e "/sys/class/net/${name}/device" ]]; then
            PHYSICAL_INTERFACES+=("$name")
        fi
    done < <(ip -o link show 2>/dev/null |
        awk -F ': ' '{print $2}' |
        cut -d '@' -f 1)

    if [[ ${#INTERFACES[@]} -eq 0 ]]; then
        log ERROR "No se detectaron interfaces distintas de loopback."
        ERRORS=$((ERRORS + 1))
        add_diagnostic "No se detectaron interfaces de red."
    else
        log OK "Interfaces detectadas: ${INTERFACES[*]}"
        add_diagnostic "Interfaces: ${INTERFACES[*]}"
    fi
}

show_interface_details() {
    log INFO "Estado de las interfaces:"

    ip -br addr 2>&1 | tee -a "$LOG_FILE" || true

    log INFO "Direcciones IPv4:"

    ip -4 addr show 2>&1 | tee -a "$LOG_FILE" || true

    log INFO "Direcciones IPv6:"

    ip -6 addr show 2>&1 | tee -a "$LOG_FILE" || true
}

# ==============================================================
# DIAGNÓSTICO DE RUTAS
# ==============================================================

check_routes() {
    ROUTES="$(ip -4 route show 2>/dev/null || true)"

    log INFO "Tabla de rutas IPv4:"

    printf '%s\n' "${ROUTES:-Sin rutas IPv4}" |
        tee -a "$LOG_FILE"

    if ! printf '%s\n' "$ROUTES" |
        grep -qE '^default([[:space:]]|$)'; then

        log WARN "No se detectó una ruta IPv4 predeterminada."

        add_diagnostic \
            "No existe una ruta IPv4 predeterminada detectable."

        add_warning \
            "Sin gateway conocido no se intentará inventar una ruta."

        ERRORS=$((ERRORS + 1))
    else
        log OK "Existe una ruta IPv4 predeterminada."
        add_diagnostic "Existe una ruta IPv4 predeterminada."
    fi
}

# ==============================================================
# DIAGNÓSTICO DE CONECTIVIDAD
# ==============================================================

check_connectivity() {
    IPV4_CONNECTIVITY="NO"
    DNS_CONNECTIVITY="NO"

    if has_command ping; then
        if ping -4 -c 2 -W 3 1.1.1.1 >/dev/null 2>&1; then
            IPV4_CONNECTIVITY="SI"
            log OK "Conectividad IPv4 hacia 1.1.1.1."
        else
            log WARN "No se pudo verificar conectividad IPv4 por ICMP."
            add_warning \
                "El ping puede estar bloqueado aunque exista conectividad."
        fi
    else
        add_warning "El comando ping no está instalado."
    fi

    if has_command getent; then
        if getent ahostsv4 example.com >/dev/null 2>&1; then
            DNS_CONNECTIVITY="SI"
            log OK "La resolución DNS funciona."
        else
            log WARN "No se pudo resolver example.com."
        fi
    else
        add_warning "El comando getent no está disponible."
    fi

    add_diagnostic "Conectividad IPv4 por ICMP: ${IPV4_CONNECTIVITY}"
    add_diagnostic "Resolución DNS: ${DNS_CONNECTIVITY}"
}

# ==============================================================
# DIAGNÓSTICO SSH
# ==============================================================

check_ssh() {
    SSH_STATE="DESCONOCIDO"

    if systemctl is-active --quiet ssh 2>/dev/null; then
        SSH_STATE="ACTIVO"
    elif systemctl is-active --quiet sshd 2>/dev/null; then
        SSH_STATE="ACTIVO"
    else
        SSH_STATE="INACTIVO_O_NO_DETECTADO"
    fi

    add_diagnostic "Estado del servicio SSH: ${SSH_STATE}"

    if [[ "$SSH_STATE" == "ACTIVO" ]]; then
        log OK "El servicio SSH está activo."
    else
        log WARN "El servicio SSH no aparece activo."
    fi

    if has_command sshd; then
        if sshd -t 2>/dev/null; then
            log OK "La configuración de sshd supera la validación."
        else
            log WARN "La configuración de sshd presenta errores."
            add_warning \
                "Revisar sshd_config antes de reiniciar el servicio."
        fi
    fi
}

# ==============================================================
# COPIAS DE SEGURIDAD
# ==============================================================

backup_file() {
    local file="$1"

    [[ -f "$file" ]] || return 0

    local destination="${BACKUP_DIR}${file}"

    mkdir -p "$(dirname "$destination")" || return 1

    cp -a -- "$file" "$destination" || return 1
}

create_backup() {
    mkdir -p "$BACKUP_DIR" || {
        log ERROR "No se pudo crear la copia de seguridad."
        return 1
    }

    chmod 700 "$BACKUP_DIR" 2>/dev/null || true

    local paths=(
        /etc/netplan
        /etc/network/interfaces
        /etc/NetworkManager
        /etc/systemd/network
        /etc/resolv.conf
        /etc/hosts
    )

    for path in "${paths[@]}"; do
        if [[ -e "$path" ]]; then
            local destination="${BACKUP_DIR}${path}"

            mkdir -p "$(dirname "$destination")" || continue

            cp -a -- "$path" "$destination" 2>/dev/null || true
        fi
    done

    ip addr show > "${BACKUP_DIR}/ip-addresses.txt" 2>/dev/null || true
    ip route show table all > "${BACKUP_DIR}/routes.txt" 2>/dev/null || true

    log OK "Copia de seguridad: ${BACKUP_DIR}"

    add_diagnostic "Copia de seguridad: ${BACKUP_DIR}"
}

# ==============================================================
# NETPLAN: DIAGNÓSTICO DE INTERFACES
# ==============================================================

diagnose_netplan() {
    NETPLAN_DIR="/etc/netplan"

    [[ -d "$NETPLAN_DIR" ]] || {
        log INFO "Netplan no está configurado en este sistema."
        return 0
    }

    if ! has_command netplan; then
        log WARN "Existe /etc/netplan, pero no se encuentra el comando netplan."
        return 0
    fi

    log INFO "Validando configuración de Netplan..."

    if netplan generate >/dev/null 2>&1; then
        log OK "Netplan puede generar su configuración."
        add_diagnostic "Validación sintáctica de Netplan: correcta."
    else
        log WARN "Netplan no pudo generar su configuración."
        add_diagnostic "Netplan presenta un error de generación."
        add_warning \
            "La configuración Netplan requiere inspección antes de aplicarse."
        ERRORS=$((ERRORS + 1))
        return 0
    fi

    local file

    while IFS= read -r -d '' file; do
        [[ -f "$file" ]] || continue

        log INFO "Archivo Netplan: $file"

        # Se busca el nombre de la interfaz en las claves principales.
        # No se modifica automáticamente una configuración ambigua.
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]{4,}[[:alnum:]_.:-]+:[[:space:]]*$ ]] ||
                continue

            local candidate

            candidate="$(printf '%s\n' "$line" |
                sed -E 's/^[[:space:]]*([^:]+):[[:space:]]*$/\1/')"

            case "$candidate" in
                version|renderer|ethernets|wifis|bridges|bonds|vlans|tunnels|routes|nameservers|match|dhcp4|dhcp6|addresses|gateway4|optional|set-name|mtu|accept-ra|link-local|macaddress|wakeonlan|critical)
                    continue
                    ;;
            esac

            # Solo se considera una interfaz si aparece en el sistema.
            if ip link show dev "$candidate" >/dev/null 2>&1; then
                log OK "Netplan contiene una referencia a la interfaz existente: $candidate"
            else
                log WARN "Posible referencia a interfaz inexistente: $candidate"

                add_diagnostic \
                    "Referencia potencialmente obsoleta en Netplan: ${candidate}"
            fi

        done < "$file"

    done < <(find "$NETPLAN_DIR" -maxdepth 1 -type f \
        \( -name '*.yaml' -o -name '*.yml' \) -print0 2>/dev/null)
}

# ==============================================================
# REPARACIÓN CONSERVADORA DE NETPLAN
# ==============================================================

repair_netplan() {
    local netplan_dir="/etc/netplan"

    [[ -d "$netplan_dir" ]] || return 0
    has_command netplan || return 0

    log INFO "Evaluando posibles reparaciones de Netplan..."

    # Si la configuración ya es válida, no se modifica.
    if netplan generate >/dev/null 2>&1; then
        log OK "Netplan es sintácticamente válido; no se modificará."
        return 0
    fi

    # No se reescribe una configuración YAML arbitraria.
    # Se conservan los archivos y se informa del problema.
    log WARN "No se puede reparar Netplan con seguridad automáticamente."

    add_warning \
        "Netplan falla al generar la configuración. Se conserva el original."

    return 0
}

# ==============================================================
# DIAGNÓSTICO DEL SERVICIO DE RED
# ==============================================================

check_network_services() {
    local services=(
        systemd-networkd
        NetworkManager
        networking
        systemd-resolved
    )

    for service in "${services[@]}"; do
        if systemctl list-unit-files "${service}.service" \
            --no-legend 2>/dev/null | grep -q "${service}.service"; then

            local state

            state="$(systemctl is-active "$service" 2>/dev/null || true)"

            log INFO "${service}: ${state:-desconocido}"

            add_diagnostic "Servicio ${service}: ${state:-desconocido}"
        fi
    done
}

# ==============================================================
# VERIFICACIÓN FINAL
# ==============================================================

final_checks() {
    log INFO "Ejecutando comprobaciones finales..."

    ip -br addr 2>&1 | tee -a "$LOG_FILE" || true
    ip route 2>&1 | tee -a "$LOG_FILE" || true

    if has_command netplan && [[ -d /etc/netplan ]]; then
        if netplan generate >/dev/null 2>&1; then
            log OK "Netplan continúa siendo válido."
        else
            log WARN "Netplan sigue presentando errores."
        fi
    fi

    if has_command ping &&
        ping -4 -c 2 -W 3 1.1.1.1 >/dev/null 2>&1; then
        log OK "Prueba final de conectividad IPv4 satisfactoria."
    else
        log WARN "No se pudo confirmar la conectividad IPv4."
    fi

    if has_command getent &&
        getent ahostsv4 example.com >/dev/null 2>&1; then
        log OK "Prueba final de DNS satisfactoria."
    else
        log WARN "No se pudo confirmar la resolución DNS."
    fi
}

# ==============================================================
# INFORME FINAL
# ==============================================================

generate_report() {
    {
        printf '%s\n' \
            "============================================================" \
            " VPS NETWORK RECOVERY - INFORME DE DIAGNÓSTICO" \
            "============================================================" \
            "" \
            "Fecha: $(date '+%F %T')" \
            "Versión: ${VERSION}" \
            "Sistema: ${OS_NAME}" \
            "Virtualización: ${VIRT}" \
            "Conectividad IPv4 por ICMP: ${IPV4_CONNECTIVITY:-NO VERIFICADA}" \
            "Resolución DNS: ${DNS_CONNECTIVITY:-NO VERIFICADA}" \
            "SSH: ${SSH_STATE:-NO VERIFICADO}" \
            "Errores detectados: ${ERRORS}" \
            "Cambios realizados: ${CHANGES}" \
            "Reparaciones completadas: ${REPAIRS}" \
            "Copia de seguridad: ${BACKUP_DIR}" \
            "Registro: ${LOG_FILE}" \
            ""

        printf '%s\n' "DIAGNÓSTICO"

        local item

        for item in "${DIAGNOSTICS[@]}"; do
            printf ' - %s\n' "$item"
        done

        printf '\n%s\n' "ACCIONES"

        if [[ ${#ACTIONS[@]} -eq 0 ]]; then
            printf '%s\n' " - No se realizaron cambios."
        else
            for item in "${ACTIONS[@]}"; do
                printf ' - %s\n' "$item"
            done
        fi

        printf '\n%s\n' "ADVERTENCIAS"

        if [[ ${#WARNINGS[@]} -eq 0 ]]; then
            printf '%s\n' " - Ninguna."
        else
            for item in "${WARNINGS[@]}"; do
                printf ' - %s\n' "$item"
            done
        fi

        printf '\n%s\n' "============================================================"

    } > "$REPORT_FILE"

    log OK "Informe generado: ${REPORT_FILE}"
}

# ==============================================================
# EJECUCIÓN PRINCIPAL
# ==============================================================

main() {
    check_privileges

    printf '\n'
    printf '%b╔══════════════════════════════════════════════════╗%b\n' "$CYAN" "$RESET"
    printf '%b║          VPS NETWORK RECOVERY v%s             ║%b\n' "$WHITE" "$RESET" "$VERSION"
    printf '%b║       Diagnóstico y recuperación automática      ║%b\n' "$CYAN" "$RESET"
    printf '%b╚══════════════════════════════════════════════════╝%b\n' "$CYAN" "$RESET"
    printf '\n'

    log INFO "Iniciando diagnóstico automático."

    detect_os
    detect_virtualization
    detect_network_managers

    collect_interfaces
    show_interface_details

    check_routes
    check_connectivity
    check_ssh
    check_network_services

    create_backup || {
        log ERROR "No se pudo asegurar una copia de seguridad."
        log ERROR "Se cancela cualquier reparación."
        exit 1
    }

    diagnose_netplan
    repair_netplan

    final_checks
    generate_report

    printf '\n'
    printf '%b══════════════ RESUMEN FINAL ══════════════%b\n' "$CYAN" "$RESET"
    printf ' Sistema:       %s\n' "$OS_NAME"
    printf ' IPv4:          %s\n' "${IPV4_CONNECTIVITY:-DESCONOCIDA}"
    printf ' DNS:           %s\n' "${DNS_CONNECTIVITY:-DESCONOCIDO}"
    printf ' SSH:           %s\n' "${SSH_STATE:-DESCONOCIDO}"
    printf ' Errores:       %s\n' "$ERRORS"
    printf ' Reparaciones:  %s\n' "$REPAIRS"
    printf ' Cambios:       %s\n' "$CHANGES"
    printf '\n'
    printf ' Informe: %s\n' "$REPORT_FILE"
    printf ' Log:     %s\n' "$LOG_FILE"
    printf ' Backup:  %s\n' "$BACKUP_DIR"
    printf '\n'

    if [[ "$IPV4_CONNECTIVITY" == "SI" &&
          "$DNS_CONNECTIVITY" == "SI" ]]; then
        log OK "Las pruebas básicas de conectividad han sido satisfactorias."
    else
        log WARN "La red necesita una revisión adicional."
        log WARN "Consulta el informe y el registro para conocer los detalles."
    fi
}

main "$@"
