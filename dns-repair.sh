#!/usr/bin/env bash
set -Eeuo pipefail

# ================================================================
#                  DNS REPAIR PRO | NETWORK MANAGER
#                    DIAGNOSTICO Y REPARACION DNS
# ================================================================
#
# FUNCIONES:
#   - Dashboard profesional con colores e indicadores.
#   - Deteccion de interfaz, direccion IPv4 y ruta predeterminada.
#   - Inspeccion de systemd-resolved y resolv.conf.
#   - Diagnostico de servidores DNS asociados a la interfaz.
#   - Pruebas de resolucion de dominios y conectividad HTTPS.
#   - Comprobacion directa del DNS interno de Oracle Cloud.
#   - Alternativa automatica con Cloudflare y Google DNS.
#   - Confirmacion antes de realizar cambios.
#   - Respaldo de configuracion persistente antes de reparar.
#   - Aplicacion controlada mediante resolvectl.
#   - Verificacion posterior de la resolucion DNS.
#   - Resumen final con resultados y recomendaciones.
#
# IMPORTANTE:
#   - Ejecutar como root.
#   - Requiere systemd-resolved, resolvectl e ip.
#   - dig y curl son opcionales; Python 3 puede comprobar Oracle DNS.
#   - Los cambios con resolvectl son normalmente temporales.
#   - El script no modifica deliberadamente archivos de configuracion.
#   - El respaldo no convierte los cambios temporales en persistentes.
#
# ================================================================

set -o pipefail

# ------------------------- COLORES -------------------------------

if [[ -t 1 ]]; then
    RESET='\033[0m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RED='\033[1;31m'
    GREEN='\033[1;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;34m'
    CYAN='\033[1;36m'
    MAGENTA='\033[1;35m'
    WHITE='\033[1;37m'
    GRAY='\033[0;90m'
    BG_BLUE='\033[44m'
    BG_GREEN='\033[42m'
    BG_RED='\033[41m'
else
    RESET='' BOLD='' DIM=''
    RED='' GREEN='' YELLOW=''
    BLUE='' CYAN='' MAGENTA=''
    WHITE='' GRAY=''
    BG_BLUE='' BG_GREEN='' BG_RED=''
fi

# ------------------------- CONFIGURACION -------------------------

readonly SCRIPT_NAME="DNS REPAIR PRO"
readonly SCRIPT_VERSION="3.0"
readonly ORACLE_DNS="169.254.169.254"
readonly PUBLIC_DNS=("1.1.1.1" "8.8.8.8")
readonly TEST_DOMAINS=("raw.githubusercontent.com" "google.com")
readonly HTTPS_URL="https://github.com/"

IFACE=""
IP_ADDR=""
DNS_SOURCE=""
BACKUP=""
RESOLV_TARGET=""

CURRENT_DNS=()
DNS_SERVERS=()
ERRORS=()
WARNINGS=()
OK_ITEMS=()

INITIAL_STATUS="NO DIAGNOSTICADO"
FINAL_STATUS="DESCONFIGURADO"

INTERFACE_OK=0
DNS_CONFIG_OK=0
DNS_RESOLUTION_OK=0
HTTPS_OK=0
ORACLE_OK=0
REPAIR_ATTEMPTED=0
REPAIR_SUCCESS=0
APPLY_OK=0

# ------------------------- UTILIDADES ----------------------------

pause_short() {
    sleep 0.15
}

line() {
    printf '%b\n' "${GRAY}----------------------------------------------------------------${RESET}"
}

line_double() {
    printf '%b\n' "${CYAN}${BOLD}================================================================${RESET}"
}

section() {
    printf '\n'
    printf '%b\n' "${CYAN}${BOLD}  $1${RESET}"
    line
}

ok() {
    printf '  %b %s\n' "${GREEN}${BOLD}[OK]${RESET}" "$1"
    OK_ITEMS+=("$1")
}

warn() {
    printf '  %b %s\n' "${YELLOW}${BOLD}[AVISO]${RESET}" "$1"
    WARNINGS+=("$1")
}

fail() {
    printf '  %b %s\n' "${RED}${BOLD}[ERROR]${RESET}" "$1"
    ERRORS+=("$1")
}

info() {
    printf '  %b %s\n' "${CYAN}[INFO]${RESET}" "$1"
}

detail() {
    printf '    %b %s\n' "${BLUE}›${RESET}" "$1"
}

status_good() {
    printf '\n'
    printf '  %b %b\n' \
        "${BG_GREEN}${WHITE}${BOLD}  DNS OPERATIVO  ${RESET}" \
        "${GREEN}${BOLD}Configuracion verificada${RESET}"
}

status_bad() {
    printf '\n'
    printf '  %b %b\n' \
        "${BG_RED}${WHITE}${BOLD}  DNS CON FALLOS  ${RESET}" \
        "${RED}${BOLD}Requiere atencion${RESET}"
}

ask_yes_no() {
    local prompt="$1"
    local answer

    read -r -p "  ${prompt} [S/n]: " answer || answer=""

    answer="${answer:-S}"

    [[ "$answer" =~ ^[sS]([iI])?$ ]]
}

show_value() {
    local label="$1"
    local value="$2"

    printf '  %-25s %b\n' \
        "$label" "${WHITE}${value:-No disponible}${RESET}"
}

# ------------------------- VALIDACIONES --------------------------

if [[ "$EUID" -ne 0 ]]; then
    printf '\n%b\n' "${RED}${BOLD}[ERROR] Ejecuta este script como root.${RESET}"
    printf '  Ejemplo: %s\n\n' "sudo bash dns-repair.sh"
    exit 1
fi

for command_name in resolvectl ip systemctl; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf '\n%b\n' "${RED}[ERROR] No se encontro el comando: $command_name${RESET}"
        exit 1
    fi
done

if ! command -v timeout >/dev/null 2>&1; then
    printf '\n%b\n' "${RED}[ERROR] Se requiere el comando timeout.${RESET}"
    printf '%s\n' "Instalalo con: apt-get update && apt-get install -y coreutils"
    exit 1
fi

# ------------------------- ENCABEZADO ----------------------------

clear 2>/dev/null || true

printf '\n'
printf '%b\n' "${CYAN}${BOLD}+----------------------------------------------------------------+${RESET}"
printf '%b\n' "${CYAN}${BOLD}|                                                                |${RESET}"
printf '%b\n' "${CYAN}${BOLD}|                    DNS REPAIR PRO                              |${RESET}"
printf '%b\n' "${CYAN}${BOLD}|                    NETWORK MANAGER                             |${RESET}"
printf '%b\n' "${CYAN}${BOLD}|                                                                |${RESET}"
printf '%b\n' "${CYAN}${BOLD}+----------------------------------------------------------------+${RESET}"
printf '\n'

printf '  %b %s\n' "${MAGENTA}VERSION${RESET}" "$SCRIPT_VERSION"
printf '  %b %s\n' "${MAGENTA}FECHA  ${RESET}" "$(date '+%d/%m/%Y %H:%M:%S')"
printf '  %b %s\n' "${MAGENTA}EQUIPO ${RESET}" "$(hostname 2>/dev/null || printf 'desconocido')"
printf '  %b %s\n' "${MAGENTA}SERVICIO${RESET}" "systemd-resolved"
printf '\n'

printf '%b\n' "${GRAY}  Diagnostico inteligente de DNS para servidores Linux.${RESET}"
printf '%b\n' "${GRAY}  No se modificara la configuracion sin tu confirmacion.${RESET}"

# ------------------------- SERVICIO DNS --------------------------

section "01  |  SERVICIO DE RESOLUCION DNS"

if systemctl is-active --quiet systemd-resolved; then
    ok "systemd-resolved esta activo."
else
    warn "systemd-resolved no esta activo."

    if ask_yes_no "¿Deseas intentar iniciar el servicio?"; then
        if systemctl start systemd-resolved &&
           systemctl is-active --quiet systemd-resolved; then
            ok "Servicio iniciado correctamente."
        else
            fail "No se pudo iniciar systemd-resolved."
            detail "Revisa: systemctl status systemd-resolved"
            exit 1
        fi
    else
        fail "No se puede continuar sin el servicio activo."
        exit 1
    fi
fi

# ------------------------- INTERFAZ DE RED -----------------------

section "02  |  INTERFAZ Y CONECTIVIDAD LOCAL"

IFACE="$(ip -4 route show default |
    awk 'NR==1 {
        for (i=1; i<=NF; i++) {
            if ($i=="dev") {
                print $(i+1)
                exit
            }
        }
    }')"

if [[ -n "$IFACE" ]] && ip link show "$IFACE" >/dev/null 2>&1; then
    INTERFACE_OK=1
    ok "Interfaz predeterminada detectada: $IFACE"
else
    fail "No se detecto una interfaz con ruta IPv4 predeterminada."
    detail "Comprueba: ip -4 route"
    status_bad
    exit 1
fi

IP_ADDR="$(ip -4 -o addr show dev "$IFACE" |
    awk 'NR==1 {print $4}')"

if [[ -n "$IP_ADDR" ]]; then
    ok "Direccion IPv4: $IP_ADDR"
else
    warn "La interfaz no tiene una direccion IPv4 asignada."
fi

LINK_INFO="$(ip -o link show dev "$IFACE" 2>/dev/null || true)"

if [[ "$LINK_INFO" =~ \<[^
]*UP[^
]*\> ]]; then
    ok "Interfaz habilitada administrativamente."
else
    warn "La interfaz no aparece habilitada administrativamente."
fi

DEFAULT_ROUTE="$(ip -4 route show default |
    awk 'NR==1 {print; exit}')"

if [[ -n "$DEFAULT_ROUTE" ]]; then
    detail "Ruta predeterminada: $DEFAULT_ROUTE"
else
    warn "No se encontro una ruta IPv4 predeterminada."
fi

# ------------------------- DNS ACTUAL ----------------------------

section "03  |  CONFIGURACION DNS ACTUAL"

CURRENT_STATUS="$(resolvectl status "$IFACE" 2>/dev/null || true)"

if [[ -n "$CURRENT_STATUS" ]]; then
    printf '%s\n' "$CURRENT_STATUS" |
        grep -E 'Current Scopes:|DefaultRoute setting:|Current DNS Server:|DNS Servers:|DNS Domain:' |
        while IFS= read -r entry; do
            detail "$entry"
        done
else
    warn "No se pudo consultar el estado DNS de $IFACE."
fi

mapfile -t CURRENT_DNS < <(
    resolvectl dns "$IFACE" 2>/dev/null |
        sed 's/^[^:]*://' |
        xargs -n1 2>/dev/null |
        awk 'NF'
)

if [[ ${#CURRENT_DNS[@]} -eq 0 ]]; then
    GLOBAL_DNS="$(resolvectl dns 2>/dev/null || true)"

    if [[ -n "$GLOBAL_DNS" ]]; then
        detail "No se detectaron DNS propios de la interfaz."
        detail "Configuracion DNS general disponible:"
        printf '%s\n' "$GLOBAL_DNS" |
            while IFS= read -r entry; do
                [[ -n "$entry" ]] && detail "$entry"
            done
    fi
fi

if [[ ${#CURRENT_DNS[@]} -gt 0 ]]; then
    ok "Se detectaron servidores DNS en la interfaz."

    for dns_server in "${CURRENT_DNS[@]}"; do
        detail "Servidor DNS: $dns_server"
    done
else
    warn "No se detectaron servidores DNS asociados directamente a $IFACE."
fi

if [[ -e /etc/resolv.conf ]]; then
    RESOLV_TARGET="$(readlink -f /etc/resolv.conf 2>/dev/null || true)"
    ok "/etc/resolv.conf existe."
    detail "Destino: ${RESOLV_TARGET:-no identificado}"

    if grep -q 'nameserver' /etc/resolv.conf 2>/dev/null; then
        while IFS= read -r resolver_line; do
            detail "$resolver_line"
        done < <(grep 'nameserver' /etc/resolv.conf 2>/dev/null || true)
    else
        warn "/etc/resolv.conf no contiene entradas nameserver."
    fi
else
    fail "No existe /etc/resolv.conf."
fi

# ------------------------- FUNCIONES DE PRUEBA ------------------

test_domain_resolution() {
    local domain="$1"

    timeout 7 getent ahostsv4 "$domain" >/dev/null 2>&1
}

test_all_domains() {
    local all_ok=1
    local domain

    for domain in "${TEST_DOMAINS[@]}"; do
        if test_domain_resolution "$domain"; then
            ok "Resolucion correcta: $domain"
        else
            fail "No se pudo resolver: $domain"
            all_ok=0
        fi
    done

    DNS_RESOLUTION_OK="$all_ok"
}

test_https() {
    HTTPS_OK=0

    if ! command -v curl >/dev/null 2>&1; then
        warn "curl no esta instalado; no se puede verificar HTTPS."
        return
    fi

    if curl -fsSI \
        --connect-timeout 5 \
        --max-time 10 \
        "$HTTPS_URL" >/dev/null 2>&1; then
        HTTPS_OK=1
        ok "Conexion HTTPS verificada correctamente."
    else
        warn "No se pudo verificar HTTPS hacia github.com."
        detail "Puede deberse a DNS, rutas, firewall, TLS o conectividad."
    fi
}

test_oracle_dns() {
    ORACLE_OK=0

    if command -v dig >/dev/null 2>&1; then
        if timeout 5 dig +time=2 +tries=1 +short \
            @"$ORACLE_DNS" raw.githubusercontent.com A 2>/dev/null |
            grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
            ORACLE_OK=1
        fi

    elif command -v python3 >/dev/null 2>&1; then
        if timeout 5 python3 -c '
import random
import socket
import struct

server = "169.254.169.254"
name = "raw.githubusercontent.com"
ident = random.randrange(65536)

qname = b"".join(
    bytes([len(part)]) + part.encode("ascii")
    for part in name.split(".")
) + b"\0"

packet = (
    struct.pack("!HHHHHH", ident, 0x0100, 1, 0, 0, 0)
    + qname
    + struct.pack("!HH", 1, 1)
)

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(2)

try:
    sock.sendto(packet, (server, 53))
    data, _ = sock.recvfrom(4096)

    if len(data) < 12:
        raise SystemExit(1)

    response_id, flags, questions, answers, _, _ = struct.unpack(
        "!HHHHHH", data[:12]
    )

    if response_id != ident:
        raise SystemExit(1)

    if not (flags & 0x8000):
        raise SystemExit(1)

    if flags & 0x000F:
        raise SystemExit(1)

    if answers < 1:
        raise SystemExit(1)

    # Recorrer las preguntas para localizar la seccion de respuestas.
    offset = 12

    for _ in range(questions):
        while offset < len(data) and data[offset] != 0:
            length = data[offset]

            if length & 0xC0 == 0xC0:
                offset += 2
                break

            offset += length + 1
        else:
            offset += 1

        offset += 4

    # Comprobar que existe al menos un registro A con IPv4 valida.
    found_a = False

    for _ in range(answers):
        if offset + 2 > len(data):
            break

        if data[offset] & 0xC0 == 0xC0:
            offset += 2
        else:
            while offset < len(data) and data[offset] != 0:
                offset += data[offset] + 1
            offset += 1

        if offset + 10 > len(data):
            break

        rtype, rclass, ttl, rdlength = struct.unpack(
            "!HHIH", data[offset:offset + 10]
        )
        offset += 10

        if offset + rdlength > len(data):
            break

        if rtype == 1 and rclass == 1 and rdlength == 4:
            found_a = True

        offset += rdlength

    if not found_a:
        raise SystemExit(1)

except (OSError, struct.error, IndexError):
    raise SystemExit(1)
finally:
    sock.close()
' >/dev/null 2>&1; then
            ORACLE_OK=1
        fi
    else
        warn "No se encontro dig ni python3 para comprobar Oracle DNS."
        return
    fi

    if [[ "$ORACLE_OK" -eq 1 ]]; then
        ok "El DNS interno de Oracle Cloud responde con una direccion IPv4."
    else
        warn "No se confirmo una respuesta DNS valida de Oracle Cloud."
    fi
}

# ------------------------- DIAGNOSTICO INICIAL ------------------

section "04  |  PRUEBAS DE FUNCIONAMIENTO"

info "Comprobando resolucion de dominios..."

test_all_domains

printf '\n'
info "Comprobando conectividad HTTPS..."

test_https

# La resolucion correcta requiere servidores DNS detectables,
# dominios de prueba resolubles y systemd-resolved activo.
# HTTPS se informa de forma independiente.

if [[ ${#CURRENT_DNS[@]} -gt 0 ]] &&
   [[ "$DNS_RESOLUTION_OK" -eq 1 ]] &&
   systemctl is-active --quiet systemd-resolved; then
    DNS_CONFIG_OK=1
    INITIAL_STATUS="CONFIGURADO CORRECTAMENTE"
    FINAL_STATUS="$INITIAL_STATUS"
else
    DNS_CONFIG_OK=0
    INITIAL_STATUS="DESCONFIGURADO"
    FINAL_STATUS="$INITIAL_STATUS"
fi

# ------------------------- RESULTADO DEL DIAGNOSTICO -------------

section "05  |  RESULTADO DEL DIAGNOSTICO"

if [[ "$DNS_CONFIG_OK" -eq 1 ]]; then
    status_good

    printf '\n'
    ok "systemd-resolved esta activo."
    ok "Hay servidores DNS asociados a la interfaz."
    ok "Los dominios de prueba se resuelven correctamente."

    if [[ "$HTTPS_OK" -eq 1 ]]; then
        ok "La conectividad HTTPS funciona."
    else
        warn "HTTPS no pudo verificarse; no demuestra por si solo un fallo DNS."
    fi

    printf '\n'
    line_double
    printf '%b\n' "${GREEN}${BOLD}  DIAGNOSTICO COMPLETADO SIN CAMBIOS${RESET}"
    printf '%s\n' "  La configuracion DNS actual se conserva."
    line_double
    printf '\n'

    exit 0
fi

status_bad

printf '\n'
printf '%b\n' "${RED}${BOLD}  Se detectaron posibles problemas DNS.${RESET}"
printf '\n'

if [[ ${#CURRENT_DNS[@]} -eq 0 ]]; then
    info "No hay servidores DNS detectables en la interfaz."
fi

if [[ "$DNS_RESOLUTION_OK" -eq 0 ]]; then
    info "Uno o mas dominios de prueba no pudieron resolverse."
fi

if ! systemctl is-active --quiet systemd-resolved; then
    info "systemd-resolved no esta activo."
fi

printf '\n'
warn "La reparacion cambiara los DNS asociados a $IFACE."
info "Se priorizara Oracle Cloud; si no responde, se usaran DNS publicos."
printf '\n'

if ! ask_yes_no "¿Deseas continuar con la reparacion DNS?"; then
    printf '\n'
    warn "Reparacion cancelada por el usuario."
    info "No se aplicaron cambios DNS."
    exit 0
fi

# ------------------------- RESPALDO ------------------------------

section "06  |  COPIA DE SEGURIDAD"

BACKUP="/root/dns-backup-$(date +%Y%m%d-%H%M%S)"

if ! mkdir -p "$BACKUP"; then
    fail "No se pudo crear el directorio de respaldo."
    exit 1
fi

BACKUP_COUNT=0

if [[ -f /etc/systemd/resolved.conf ]]; then
    if cp -a /etc/systemd/resolved.conf "$BACKUP/"; then
        ok "Respaldado: /etc/systemd/resolved.conf"
        ((BACKUP_COUNT+=1))
    else
        warn "No se pudo respaldar resolved.conf."
    fi
fi

if [[ -d /etc/systemd/resolved.conf.d ]]; then
    if cp -a /etc/systemd/resolved.conf.d "$BACKUP/"; then
        ok "Respaldado: /etc/systemd/resolved.conf.d"
        ((BACKUP_COUNT+=1))
    else
        warn "No se pudo respaldar resolved.conf.d."
    fi
fi

if [[ -e /etc/resolv.conf || -L /etc/resolv.conf ]]; then
    if cp -a /etc/resolv.conf "$BACKUP/resolv.conf"; then
        ok "Respaldada la referencia /etc/resolv.conf"
        ((BACKUP_COUNT+=1))
    else
        warn "No se pudo respaldar /etc/resolv.conf."
    fi
fi

if [[ "$BACKUP_COUNT" -gt 0 ]]; then
    ok "Copia de seguridad creada en: $BACKUP"
else
    warn "No se encontraron archivos de configuracion para respaldar."
    info "Directorio de respaldo: $BACKUP"
fi

# ------------------------- SELECCION DNS -------------------------

section "07  |  SELECCION INTELIGENTE DE DNS"

DNS_SERVERS=()
DNS_SOURCE=""

test_oracle_dns

if [[ "$ORACLE_OK" -eq 1 ]]; then
    DNS_SERVERS=("$ORACLE_DNS")
    DNS_SOURCE="Oracle Cloud"
    ok "Oracle Cloud esta disponible."
    detail "Se priorizara el DNS interno: $ORACLE_DNS"
else
    DNS_SERVERS=("${PUBLIC_DNS[@]}")
    DNS_SOURCE="Cloudflare + Google"
    warn "No se pudo validar el DNS interno de Oracle Cloud."
    info "Se seleccionaron servidores DNS publicos."
    detail "Cloudflare: ${PUBLIC_DNS[0]}"
    detail "Google:     ${PUBLIC_DNS[1]}"
fi

# ------------------------- APLICAR REPARACION -------------------

section "08  |  APLICANDO CONFIGURACION"

REPAIR_ATTEMPTED=1
APPLY_OK=0

if ! systemctl is-active --quiet systemd-resolved; then
    info "Intentando iniciar systemd-resolved..."

    if ! systemctl start systemd-resolved; then
        fail "No se pudo iniciar systemd-resolved."
    fi
fi

if systemctl is-active --quiet systemd-resolved; then
    if resolvectl dns "$IFACE" "${DNS_SERVERS[@]}"; then
        ok "Servidores DNS asignados a $IFACE."

        if resolvectl default-route "$IFACE" yes; then
            ok "Ruta DNS predeterminada habilitada."
        else
            warn "No se pudo establecer la ruta DNS predeterminada."
        fi

        if resolvectl flush-caches; then
            ok "Cache DNS vaciada."
        else
            warn "No se pudo vaciar la cache DNS."
        fi

        APPLY_OK=1
    else
        fail "No se pudieron asignar los servidores DNS."
    fi
else
    fail "systemd-resolved continua inactivo."
fi

# ------------------------- VERIFICACION POSTERIOR ----------------

section "09  |  VERIFICACION POSTERIOR"

DNS_RESOLUTION_OK=0
HTTPS_OK=0
REPAIR_SUCCESS=0

if [[ "$APPLY_OK" -eq 1 ]]; then
    info "Esperando la actualizacion de la resolucion DNS..."
    sleep 1

    test_all_domains

    printf '\n'
    test_https
else
    warn "Se omiten las pruebas posteriores porque no se aplico la configuracion."
fi

if [[ "$APPLY_OK" -eq 1 ]] &&
   [[ "$DNS_RESOLUTION_OK" -eq 1 ]] &&
   systemctl is-active --quiet systemd-resolved; then
    REPAIR_SUCCESS=1
    FINAL_STATUS="CONFIGURADO CORRECTAMENTE"
else
    REPAIR_SUCCESS=0
    FINAL_STATUS="DESCONFIGURADO"
fi

# ------------------------- RESUMEN FINAL -------------------------

section "10  |  RESUMEN GENERAL"

show_value "Interfaz:" "${IFACE:-No detectada}"
show_value "Direccion IPv4:" "${IP_ADDR:-No disponible}"
show_value "DNS seleccionado:" "${DNS_SOURCE:-No determinado}"
show_value "Servidores DNS:" "${DNS_SERVERS[*]:-Ninguno}"
show_value "Respaldo:" "${BACKUP:-No creado}"

printf '\n'
printf '  %-25s ' "Diagnostico inicial:"

if [[ "$INITIAL_STATUS" == "CONFIGURADO CORRECTAMENTE" ]]; then
    printf '%b\n' "${GREEN}${INITIAL_STATUS}${RESET}"
else
    printf '%b\n' "${RED}${INITIAL_STATUS}${RESET}"
fi

printf '  %-25s ' "Aplicacion de cambios:"

if [[ "$APPLY_OK" -eq 1 ]]; then
    printf '%b\n' "${GREEN}Comandos aplicados${RESET}"
else
    printf '%b\n' "${RED}Aplicacion incompleta${RESET}"
fi

printf '  %-25s ' "Reparacion verificada:"

if [[ "$REPAIR_SUCCESS" -eq 1 ]]; then
    printf '%b\n' "${GREEN}${BOLD}SI${RESET}"
else
    printf '%b\n' "${RED}${BOLD}NO${RESET}"
fi

printf '  %-25s ' "Resolucion DNS:"

if [[ "$DNS_RESOLUTION_OK" -eq 1 ]]; then
    printf '%b\n' "${GREEN}Correcta${RESET}"
else
    printf '%b\n' "${RED}Con fallos${RESET}"
fi

printf '  %-25s ' "Conectividad HTTPS:"

if [[ "$HTTPS_OK" -eq 1 ]]; then
    printf '%b\n' "${GREEN}Correcta${RESET}"
else
    printf '%b\n' "${YELLOW}No verificada o con fallos${RESET}"
fi

printf '\n'
line_double

if [[ "$FINAL_STATUS" == "CONFIGURADO CORRECTAMENTE" ]]; then
    status_good

    printf '\n'
    printf '%b\n' "${GREEN}  [OK] La resolucion DNS funciona despues de la reparacion.${RESET}"
    printf '%b\n' "${GREEN}  [OK] systemd-resolved esta activo.${RESET}"

    if [[ "$HTTPS_OK" -eq 1 ]]; then
        printf '%b\n' "${GREEN}  [OK] La conectividad HTTPS tambien funciona.${RESET}"
    else
        printf '%b\n' "${YELLOW}  [AVISO] DNS funciona, pero HTTPS necesita revision.${RESET}"
    fi

    printf '\n'
    printf '%b\n' "${GRAY}  Los cambios aplicados con resolvectl pueden ser temporales.${RESET}"
else
    status_bad

    printf '\n'
    printf '%b\n' "${RED}  [ERROR] No se pudo verificar una reparacion DNS completa.${RESET}"
    printf '%b\n' "${YELLOW}  Revisa las rutas, el firewall y la conectividad del servidor.${RESET}"
    printf '%b\n' "${YELLOW}  Tambien comprueba: resolvectl status ${IFACE}${RESET}"
fi

printf '\n'

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    printf '%b\n' "${YELLOW}${BOLD}  AVISOS REGISTRADOS: ${#WARNINGS[@]}${RESET}"
fi

if [[ ${#ERRORS[@]} -gt 0 ]]; then
    printf '%b\n' "${RED}${BOLD}  ERRORES REGISTRADOS: ${#ERRORS[@]}${RESET}"
fi

line_double
printf '%b\n' "${CYAN}${BOLD}  DNS REPAIR PRO | DIAGNOSTICO FINALIZADO${RESET}"
printf '%b\n' "${GRAY}  Version ${SCRIPT_VERSION} | Network Manager${RESET}"
printf '\n'

if [[ "$REPAIR_SUCCESS" -eq 1 ]]; then
    exit 0
else
    exit 1
fi
