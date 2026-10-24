
#!/usr/bin/env bash
set -Eeuo pipefail
set -o pipefail

# ============================================================
#                 DNS REPAIR PRO | NETWORK MANAGER
#                  DIAGNOSTICO Y REPARACION DNS
# ============================================================
#
# FUNCIONES:
#   - Encabezado compacto con colores y datos del servidor.
#   - Deteccion de IP publica, sistema operativo y servicio.
#   - Deteccion de interfaz, IPv4 y ruta predeterminada.
#   - Diagnostico de systemd-resolved y resolv.conf.
#   - Pruebas DNS y conectividad HTTPS.
#   - Prioridad para DNS interno de Oracle Cloud.
#   - Alternativa Cloudflare + Google DNS.
#   - Confirmacion antes de reparar.
#   - Respaldo de archivos antes de aplicar cambios.
#   - Verificacion posterior y resumen detallado.
#
# IMPORTANTE:
#   - Ejecutar como root.
#   - Requiere systemd-resolved, resolvectl, ip y timeout.
#   - curl, wget, python3 y dig son opcionales.
#   - resolvectl aplica cambios normalmente temporales.
#   - No modifica deliberadamente Netplan ni otros gestores.
#
# ============================================================

# ------------------------- COLORES -------------------------

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
    BG_GREEN='\033[42m'
    BG_RED='\033[41m'
    BG_BLUE='\033[44m'
else
    RESET='' BOLD='' DIM=''
    RED='' GREEN='' YELLOW=''
    BLUE='' CYAN='' MAGENTA=''
    WHITE='' GRAY=''
    BG_GREEN='' BG_RED='' BG_BLUE=''
fi

# ------------------------- CONFIGURACION -------------------

readonly VERSION="4.0"
readonly ORACLE_DNS="169.254.169.254"
readonly PUBLIC_DNS=("1.1.1.1" "8.8.8.8")
readonly TEST_DOMAINS=("raw.githubusercontent.com" "google.com")
readonly HTTPS_URL="https://github.com/"
readonly PUBLIC_IP_URL="https://api.ipify.org"
readonly SEPARATOR="  ──────────────────────────────────────────────────"

IFACE=""
IP_ADDR=""
DEFAULT_ROUTE=""
DNS_SOURCE=""
BACKUP=""
RESOLV_TARGET=""
GLOBAL_DNS=""
PUBLIC_IP="No disponible"
OS_NAME="No identificado"
START_TIME="$(date '+%d/%m/%Y %H:%M:%S')"

CURRENT_DNS=()
DNS_SERVERS=()
ERRORS=()
WARNINGS=()

DNS_RESOLUTION_OK=0
HTTPS_OK=0
ORACLE_OK=0
APPLY_OK=0
REPAIR_SUCCESS=0
REPAIR_ATTEMPTED=0
DNS_CONFIG_OK=0
INITIAL_STATUS="NO DIAGNOSTICADO"
FINAL_STATUS="DESCONFIGURADO"

# ------------------------- UTILIDADES ----------------------

section() {
    printf '\n%b\n' "${CYAN}${BOLD}  $1${RESET}"
    printf '%b\n' "${GRAY}${SEPARATOR}${RESET}"
}

ok() {
    printf '  %b %s\n' "${GREEN}${BOLD}✔${RESET}" "$1"
}

warn() {
    printf '  %b %s\n' "${YELLOW}${BOLD}⚠${RESET}" "$1"
    WARNINGS+=("$1")
}

fail() {
    printf '  %b %s\n' "${RED}${BOLD}✖${RESET}" "$1"
    ERRORS+=("$1")
}

info() {
    printf '  %b %s\n' "${CYAN}ℹ${RESET}" "$1"
}

detail() {
    printf '     %b %s\n' "${BLUE}›${RESET}" "$1"
}

ask_yes_no() {
    local prompt="$1"
    local answer

    read -r -p "  ${YELLOW}❯${RESET} ${prompt} [S/n]: " answer || answer=""
    answer="${answer:-S}"

    [[ "$answer" =~ ^[sS]([iI])?$ ]]
}

show_value() {
    local label="$1"
    local value="${2:-No disponible}"

    printf '  %b %-22s%b %b%s%b\n' \
        "${BLUE}›${RESET}" \
        "$label" \
        "${RESET}" \
        "${WHITE}" \
        "$value" \
        "${RESET}"
}

status_good() {
    printf '\n  %b  %b\n' \
        "${BG_GREEN}${WHITE}${BOLD} ✔ DNS OPERATIVO ${RESET}" \
        "${GREEN}${BOLD}Configuracion verificada${RESET}"
}

status_bad() {
    printf '\n  %b  %b\n' \
        "${BG_RED}${WHITE}${BOLD} ✖ DNS CON FALLOS ${RESET}" \
        "${RED}${BOLD}Requiere atencion${RESET}"
}

# ------------------------- VALIDACIONES --------------------

if [[ "$EUID" -ne 0 ]]; then
    printf '\n%b\n' "${RED}✖ Ejecuta el script como root.${RESET}"
    printf '%s\n' "  Ejemplo: sudo bash dns-repair.sh"
    exit 1
fi

for cmd in resolvectl ip systemctl timeout; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        printf '\n%b\n' "${RED}✖ Falta el comando requerido: $cmd${RESET}"
        exit 1
    fi
done

# ------------------------- ENCABEZADO ----------------------

clear 2>/dev/null || true

# Obtener la IP publica sin detener el diagnostico si falla.
if command -v curl >/dev/null 2>&1; then
    PUBLIC_IP="$(
        timeout 4 curl -4 -fsS \
            --connect-timeout 2 \
            --max-time 3 \
            "$PUBLIC_IP_URL" 2>/dev/null || true
    )"
elif command -v wget >/dev/null 2>&1; then
    PUBLIC_IP="$(
        timeout 4 wget -qO- \
            --timeout=3 \
            "$PUBLIC_IP_URL" 2>/dev/null || true
    )"
fi

# Validar formato y rango de la direccion IPv4 publica.
if [[ "$PUBLIC_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    IFS='.' read -r oct1 oct2 oct3 oct4 <<< "$PUBLIC_IP"

    for octet in "$oct1" "$oct2" "$oct3" "$oct4"; do
        if (( 10#$octet > 255 )); then
            PUBLIC_IP="No disponible"
            break
        fi
    done
else
    PUBLIC_IP="No disponible"
fi

# Detectar el sistema operativo SIN cargar /etc/os-release.
# Esto evita conflictos con la variable readonly VERSION.
if [[ -r /etc/os-release ]]; then
    OS_NAME="$(
        awk -F= '
            $1 == "PRETTY_NAME" {
                value = substr($0, index($0, "=") + 1)
                if (value ~ /^".*"$/ || value ~ /^'\''.*'\''$/) {
                    value = substr(value, 2, length(value) - 2)
                }
                print value
                exit
            }
        ' /etc/os-release
    )"

    if [[ -z "$OS_NAME" ]]; then
        OS_NAME="$(
            awk -F= '
                $1 == "NAME" {
                    value = substr($0, index($0, "=") + 1)
                    gsub(/^"/, "", value)
                    gsub(/"$/, "", value)
                    print value
                    exit
                }
            ' /etc/os-release
        )"
    fi

    OS_NAME="${OS_NAME:-Linux}"
else
    OS_NAME="$(uname -s 2>/dev/null || echo Linux)"
fi

printf '\n'
printf '%b\n' "${CYAN}${BOLD}  ╭──────────────────────────────────────────────────╮${RESET}"
printf '%b\n' "${CYAN}${BOLD}  │                                                  │${RESET}"
printf '%b\n' "${CYAN}${BOLD}  │                 DNS REPAIR PRO                  │${RESET}"
printf '%b\n' "${CYAN}${BOLD}  │                NETWORK MANAGER                  │${RESET}"
printf '%b\n' "${CYAN}${BOLD}  │          DIAGNOSTICO Y REPARACION DNS           │${RESET}"
printf '%b\n' "${CYAN}${BOLD}  │                                                  │${RESET}"
printf '%b\n' "${CYAN}${BOLD}  ╰──────────────────────────────────────────────────╯${RESET}"
printf '\n'

printf '  %b %-10s %b %s\n' \
    "${BLUE}›${RESET}" "IP:" "${WHITE}" "$PUBLIC_IP"

printf '  %b %-10s %b %s\n' \
    "${MAGENTA}›${RESET}" "UPTIME:" "${WHITE}" "$START_TIME"

printf '  %b %-10s %b %s\n' \
    "${CYAN}🖥️${RESET}" "SISTEMA:" "${WHITE}" "$OS_NAME"

printf '  %b %-10s %b %s\n' \
    "${YELLOW}⚙️${RESET}" "Servicio:" "${WHITE}" "systemd-resolved"

printf '\n'
printf '  %b\n' "${GRAY}Diagnostico inteligente de conectividad DNS.${RESET}"
printf '  %b\n' "${GRAY}Los cambios requieren tu confirmacion.${RESET}"

# ------------------------- SERVICIO DNS --------------------

section "🔧 01 · SERVICIO DE RESOLUCION"

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
            detail "Consulta: systemctl status systemd-resolved"
            exit 1
        fi
    else
        fail "Operacion cancelada: el servicio es necesario."
        exit 1
    fi
fi

# ------------------------- INTERFAZ -------------------------

section "🌐 02 · RED Y CONECTIVIDAD"

IFACE="$(ip -4 route show default |
    awk 'NR==1 {
        for (i=1; i<=NF; i++) {
            if ($i=="dev") {
                print $(i+1)
                exit
            }
        }
    }')"

if [[ -z "$IFACE" ]] || ! ip link show "$IFACE" >/dev/null 2>&1; then
    fail "No se detecto una interfaz con ruta IPv4 predeterminada."
    detail "Comprueba: ip -4 route"
    status_bad
    exit 1
fi

ok "Interfaz detectada: $IFACE"

IP_ADDR="$(ip -4 -o addr show dev "$IFACE" |
    awk 'NR==1 {print $4}')"

if [[ -n "$IP_ADDR" ]]; then
    ok "Direccion IPv4: $IP_ADDR"
else
    warn "La interfaz no tiene una direccion IPv4."
fi

LINK_INFO="$(ip -o link show dev "$IFACE" 2>/dev/null || true)"

if [[ "$LINK_INFO" == *"<"*UP*">"* ]]; then
    ok "Interfaz habilitada."
else
    warn "La interfaz no aparece habilitada."
fi

DEFAULT_ROUTE="$(ip -4 route show default |
    awk 'NR==1 {print; exit}')"

if [[ -n "$DEFAULT_ROUTE" ]]; then
    detail "Ruta predeterminada:"
    detail "$DEFAULT_ROUTE"
else
    warn "No se encontro una ruta IPv4 predeterminada."
fi

# ------------------------- DNS ACTUAL ----------------------

section "📡 03 · CONFIGURACION DNS ACTUAL"

CURRENT_STATUS="$(resolvectl status "$IFACE" 2>/dev/null || true)"

if [[ -n "$CURRENT_STATUS" ]]; then
    while IFS= read -r entry; do
        detail "$entry"
    done < <(
        printf '%s\n' "$CURRENT_STATUS" |
            grep -E 'Current Scopes:|DefaultRoute setting:|Current DNS Server:|DNS Servers:|DNS Domain:' ||
            true
    )
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
    info "No hay DNS asociados directamente a la interfaz."
    GLOBAL_DNS="$(resolvectl dns 2>/dev/null || true)"

    if [[ -n "$GLOBAL_DNS" ]]; then
        detail "Configuracion global detectada:"
        while IFS= read -r entry; do
            [[ -n "$entry" ]] && detail "$entry"
        done <<< "$GLOBAL_DNS"
    fi
else
    ok "Servidores DNS asociados a la interfaz:"
    for dns in "${CURRENT_DNS[@]}"; do
        detail "🌐 $dns"
    done
fi

if [[ -e /etc/resolv.conf || -L /etc/resolv.conf ]]; then
    RESOLV_TARGET="$(readlink -f /etc/resolv.conf 2>/dev/null || true)"
    ok "/etc/resolv.conf existe."
    detail "Destino: ${RESOLV_TARGET:-no identificado}"

    if grep -q 'nameserver' /etc/resolv.conf 2>/dev/null; then
        while IFS= read -r entry; do
            detail "$entry"
        done < <(grep 'nameserver' /etc/resolv.conf 2>/dev/null || true)
    else
        warn "/etc/resolv.conf no contiene entradas nameserver."
    fi
else
    fail "No existe /etc/resolv.conf."
fi

# ------------------------- PRUEBAS DNS ----------------------

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
        warn "curl no esta instalado; HTTPS no se puede comprobar."
        return
    fi

    if curl -fsSI --connect-timeout 5 --max-time 10 \
        "$HTTPS_URL" >/dev/null 2>&1; then
        HTTPS_OK=1
        ok "Conectividad HTTPS verificada."
    else
        warn "No se pudo verificar HTTPS hacia github.com."
        detail "Revisa DNS, rutas, firewall y certificados TLS."
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
        # Consulta DNS A directa al servidor interno de Oracle.
        if timeout 5 python3 -c '
import random, socket, struct

server = "169.254.169.254"
name = "raw.githubusercontent.com"
ident = random.randrange(65536)

qname = b"".join(
    bytes([len(part)]) + part.encode("ascii")
    for part in name.split(".")
) + b"\0"

packet = (
    struct.pack("!HHHHHH", ident, 0x0100, 1, 0, 0, 0)
    + qname + struct.pack("!HH", 1, 1)
)

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(2)

try:
    sock.sendto(packet, (server, 53))
    data, _ = sock.recvfrom(4096)

    if len(data) < 12:
        raise SystemExit(1)

    rid, flags, questions, answers, _, _ = struct.unpack(
        "!HHHHHH", data[:12]
    )

    if rid != ident or not (flags & 0x8000) or (flags & 15) != 0:
        raise SystemExit(1)

    offset = 12

    for _ in range(questions):
        while offset < len(data):
            length = data[offset]

            if length == 0:
                offset += 1
                break

            if length & 0xC0 == 0xC0:
                offset += 2
                break

            offset += length + 1

        offset += 4

    found = False

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

        rtype, rclass, ttl, size = struct.unpack(
            "!HHIH", data[offset:offset + 10]
        )
        offset += 10

        if offset + size > len(data):
            break

        if rtype == 1 and rclass == 1 and size == 4:
            found = True

        offset += size

    if not found:
        raise SystemExit(1)

except (OSError, struct.error, IndexError):
    raise SystemExit(1)
finally:
    sock.close()
' >/dev/null 2>&1; then
            ORACLE_OK=1
        fi
    else
        warn "No esta instalado dig ni python3 para probar Oracle DNS."
        return
    fi

    if [[ "$ORACLE_OK" -eq 1 ]]; then
        ok "Oracle DNS responde con una direccion IPv4."
    else
        warn "No se pudo validar una respuesta DNS de Oracle."
    fi
}

# ------------------------- DIAGNOSTICO ---------------------

section "🧪 04 · PRUEBAS DE FUNCIONAMIENTO"

info "Probando resolucion de dominios..."
test_all_domains

printf '\n'
info "Probando conectividad HTTPS..."
test_https

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

# ------------------------- RESULTADO INICIAL ----------------

section "📋 05 · RESULTADO DEL DIAGNOSTICO"

if [[ "$DNS_CONFIG_OK" -eq 1 ]]; then
    status_good
    printf '\n'
    ok "El servicio DNS esta activo."
    ok "Se detectaron DNS en la interfaz."
    ok "Los dominios de prueba resuelven correctamente."

    if [[ "$HTTPS_OK" -eq 1 ]]; then
        ok "HTTPS funciona correctamente."
    else
        warn "HTTPS no se verifico; esto no implica necesariamente un fallo DNS."
    fi

    printf '\n'
    printf '  %b\n' "${GREEN}${BOLD}✨ No se requieren reparaciones DNS.${RESET}"
    info "La configuracion actual se conserva sin cambios."
    printf '\n'
    exit 0
fi

status_bad
printf '\n'
warn "Se detectaron posibles problemas de resolucion DNS."

if [[ ${#CURRENT_DNS[@]} -eq 0 ]]; then
    info "No se detectaron servidores DNS en la interfaz."
fi

if [[ "$DNS_RESOLUTION_OK" -eq 0 ]]; then
    info "Uno o mas dominios no pudieron resolverse."
fi

printf '\n'
warn "La reparacion modificara los DNS temporales de $IFACE."
info "Se intentara utilizar Oracle Cloud o DNS publicos."
printf '\n'

if ! ask_yes_no "¿Deseas continuar con la reparacion?"; then
    warn "Reparacion cancelada. No se aplicaron cambios DNS."
    exit 0
fi

# ------------------------- RESPALDO -------------------------

section "💾 06 · COPIA DE SEGURIDAD"

BACKUP="/root/dns-backup-$(date +%Y%m%d-%H%M%S)"

if ! mkdir -p "$BACKUP"; then
    fail "No se pudo crear el directorio de respaldo."
    exit 1
fi

BACKUP_COUNT=0

if [[ -f /etc/systemd/resolved.conf ]]; then
    if cp -a /etc/systemd/resolved.conf "$BACKUP/"; then
        ok "Respaldado resolved.conf."
        ((BACKUP_COUNT+=1))
    else
        warn "No se pudo respaldar resolved.conf."
    fi
fi

if [[ -d /etc/systemd/resolved.conf.d ]]; then
    if cp -a /etc/systemd/resolved.conf.d "$BACKUP/"; then
        ok "Respaldado resolved.conf.d."
        ((BACKUP_COUNT+=1))
    else
        warn "No se pudo respaldar resolved.conf.d."
    fi
fi

if [[ -e /etc/resolv.conf || -L /etc/resolv.conf ]]; then
    if cp -a /etc/resolv.conf "$BACKUP/resolv.conf"; then
        ok "Respaldado /etc/resolv.conf."
        ((BACKUP_COUNT+=1))
    else
        warn "No se pudo respaldar /etc/resolv.conf."
    fi
fi

ok "Directorio de respaldo: $BACKUP"

if [[ "$BACKUP_COUNT" -eq 0 ]]; then
    warn "No se encontraron archivos persistentes para respaldar."
fi

# ------------------------- SELECCION DNS -------------------

section "🌎 07 · SELECCION INTELIGENTE DE DNS"

DNS_SERVERS=()
DNS_SOURCE=""

test_oracle_dns

if [[ "$ORACLE_OK" -eq 1 ]]; then
    DNS_SERVERS=("$ORACLE_DNS")
    DNS_SOURCE="Oracle Cloud"
    ok "Se selecciono el DNS interno de Oracle Cloud."
    detail "Servidor: $ORACLE_DNS"
else
    DNS_SERVERS=("${PUBLIC_DNS[@]}")
    DNS_SOURCE="Cloudflare + Google"
    warn "Oracle DNS no pudo validarse."
    info "Se utilizaran servidores publicos alternativos."
    detail "Cloudflare: ${PUBLIC_DNS[0]}"
    detail "Google: ${PUBLIC_DNS[1]}"
fi

# ------------------------- APLICACION ----------------------

section "🔧 08 · APLICANDO CONFIGURACION"

REPAIR_ATTEMPTED=1
APPLY_OK=1

if ! systemctl is-active --quiet systemd-resolved; then
    if systemctl start systemd-resolved; then
        ok "Servicio DNS iniciado."
    else
        fail "No se pudo iniciar systemd-resolved."
        APPLY_OK=0
    fi
fi

if systemctl is-active --quiet systemd-resolved; then
    if resolvectl dns "$IFACE" "${DNS_SERVERS[@]}"; then
        ok "Servidores DNS asignados a $IFACE."
    else
        fail "No se pudieron asignar los servidores DNS."
        APPLY_OK=0
    fi

    if resolvectl default-route "$IFACE" yes; then
        ok "Ruta DNS predeterminada habilitada."
    else
        fail "No se pudo establecer la ruta DNS predeterminada."
        APPLY_OK=0
    fi

    if resolvectl flush-caches; then
        ok "Cache DNS vaciada."
    else
        warn "No se pudo vaciar la cache DNS."
    fi
else
    fail "systemd-resolved continua inactivo."
    APPLY_OK=0
fi

# ------------------------- VERIFICACION FINAL ----------------

section "🔬 09 · VERIFICACION POSTERIOR"

DNS_RESOLUTION_OK=0
HTTPS_OK=0
REPAIR_SUCCESS=0

if [[ "$APPLY_OK" -eq 1 ]]; then
    info "Esperando la actualizacion de DNS..."
    sleep 1

    test_all_domains

    printf '\n'
    test_https
else
    warn "No se ejecutan las pruebas: la aplicacion no se completo."
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

# ------------------------- RESUMEN -------------------------

section "📊 10 · RESUMEN GENERAL"

show_value "🖥️ Interfaz:" "${IFACE:-No detectada}"
show_value "🌐 IPv4:" "${IP_ADDR:-No disponible}"
show_value "🛡️ DNS elegido:" "${DNS_SOURCE:-No determinado}"
show_value "📡 Servidores:" "${DNS_SERVERS[*]:-Ninguno}"
show_value "💾 Respaldo:" "${BACKUP:-No creado}"

printf '\n'
printf '  %b %-22s%b ' "${BLUE}›${RESET}" "Estado inicial:" "${RESET}"

if [[ "$INITIAL_STATUS" == "CONFIGURADO CORRECTAMENTE" ]]; then
    printf '%b\n' "${GREEN}${INITIAL_STATUS}${RESET}"
else
    printf '%b\n' "${RED}${INITIAL_STATUS}${RESET}"
fi

printf '  %b %-22s%b ' "${BLUE}›${RESET}" "Aplicacion:" "${RESET}"

if [[ "$APPLY_OK" -eq 1 ]]; then
    printf '%b\n' "${GREEN}Comandos aplicados${RESET}"
else
    printf '%b\n' "${RED}Aplicacion incompleta${RESET}"
fi

printf '  %b %-22s%b ' "${BLUE}›${RESET}" "Resolucion DNS:" "${RESET}"

if [[ "$DNS_RESOLUTION_OK" -eq 1 ]]; then
    printf '%b\n' "${GREEN}Correcta${RESET}"
else
    printf '%b\n' "${RED}Con fallos${RESET}"
fi

printf '  %b %-22s%b ' "${BLUE}›${RESET}" "Conectividad HTTPS:" "${RESET}"

if [[ "$HTTPS_OK" -eq 1 ]]; then
    printf '%b\n' "${GREEN}Correcta${RESET}"
else
    printf '%b\n' "${YELLOW}No verificada o con fallos${RESET}"
fi

printf '  %b %-22s%b ' "${BLUE}›${RESET}" "Reparacion verificada:" "${RESET}"

if [[ "$REPAIR_SUCCESS" -eq 1 ]]; then
    printf '%b\n' "${GREEN}${BOLD}SI${RESET}"
else
    printf '%b\n' "${RED}${BOLD}NO${RESET}"
fi

printf '\n'

if [[ "$FINAL_STATUS" == "CONFIGURADO CORRECTAMENTE" ]]; then
    status_good
    printf '\n'
    ok "La resolucion DNS funciona despues de la reparacion."

    if [[ "$HTTPS_OK" -eq 1 ]]; then
        ok "La conectividad HTTPS tambien funciona."
    else
        warn "DNS funciona, pero HTTPS necesita revision."
    fi

    info "Los cambios con resolvectl pueden ser temporales."
else
    status_bad
    printf '\n'
    fail "No se pudo verificar una reparacion DNS completa."
    detail "Comprueba las rutas, firewall y conectividad."
    detail "Ejecuta: resolvectl status $IFACE"
fi

printf '\n'

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    printf '  %b\n' "${YELLOW}⚠ Avisos registrados: ${#WARNINGS[@]}${RESET}"
fi

if [[ ${#ERRORS[@]} -gt 0 ]]; then
    printf '  %b\n' "${RED}✖ Errores registrados: ${#ERRORS[@]}${RESET}"
fi

printf '\n'
printf '  %b\n' "${CYAN}${BOLD}✨ DNS REPAIR PRO · Diagnostico finalizado${RESET}"
printf '  %b\n\n' "${GRAY}Network Manager · Version $VERSION${RESET}"

if [[ "$REPAIR_SUCCESS" -eq 1 ]]; then
    exit 0
else
    exit 1
fi
