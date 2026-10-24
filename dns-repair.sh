#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
#             DNS REPAIR PRO | NETWORK MANAGER
#              DIAGNOSTICO Y REPARACION DNS
# ============================================================
#
# FUNCIONES:
#   - Dashboard visual con colores e indicadores.
#   - Diagnostico automatico de DNS.
#   - Deteccion de interfaz y servidores DNS.
#   - Pruebas de resolucion de dominios.
#   - Verificacion de conectividad HTTPS.
#   - Confirmacion antes de modificar la configuracion.
#   - Prioridad para el DNS interno de Oracle Cloud.
#   - Alternativa con DNS publicos si Oracle no responde.
#   - Copia de seguridad antes de reparar.
#   - Resumen final con resultados detallados.
#
# IMPORTANTE:
#   - No modifica archivos ajenos a la configuracion DNS.
#   - Los cambios realizados con resolvectl son temporales.
#   - La copia de seguridad protege los archivos persistentes
#     de systemd-resolved, si existen.
#
# ============================================================

# ---------------------- COLORES -----------------------------

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
else
    RESET='' BOLD='' DIM=''
    RED='' GREEN='' YELLOW=''
    BLUE='' CYAN='' MAGENTA=''
    WHITE='' GRAY=''
fi

# ---------------------- VARIABLES ---------------------------

ORACLE_DNS="169.254.169.254"
PUBLIC_DNS=("1.1.1.1" "8.8.8.8")
TEST_DOMAINS=("raw.githubusercontent.com" "google.com")

IFACE=""
DNS_SOURCE=""
DNS_SERVERS=()
BACKUP=""
ERRORS=()
WARNINGS=()
OK_ITEMS=()

INITIAL_STATUS="DESCONFIGURADO"
FINAL_STATUS="DESCONFIGURADO"
REPAIR_ATTEMPTED=0
REPAIR_SUCCESS=0
DNS_RESOLUTION_OK=0
HTTPS_OK=0
ORACLE_OK=0
DNS_CONFIG_OK=0
INTERFACE_OK=0

# ---------------------- UTILIDADES --------------------------

line() {
    printf '%b\n' "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

title() {
    printf '\n%b\n' "${CYAN}${BOLD}  $1${RESET}"
    line
}

ok() {
    printf '  %b %s\n' "${GREEN}✔${RESET}" "$1"
    OK_ITEMS+=("$1")
}

warn() {
    printf '  %b %s\n' "${YELLOW}⚠${RESET}" "$1"
    WARNINGS+=("$1")
}

fail() {
    printf '  %b %s\n' "${RED}✘${RESET}" "$1"
    ERRORS+=("$1")
}

info() {
    printf '  %b %s\n' "${CYAN}ℹ${RESET}" "$1"
}

status_good() {
    printf '\n%b\n' "${GREEN}${BOLD}  🟢 DNS: CONFIGURADO CORRECTAMENTE${RESET}"
}

status_bad() {
    printf '\n%b\n' "${RED}${BOLD}  🔴 DNS: DESCONFIGURADO${RESET}"
}

pause_short() {
    sleep 0.2
}

# ---------------------- VALIDACIONES ------------------------

if [[ $EUID -ne 0 ]]; then
    printf '\n%b\n' "${RED}✘ Ejecuta este script como root.${RESET}"
    printf '%s\n' "Ejemplo: sudo bash dns-repair.sh"
    exit 1
fi

if ! command -v resolvectl >/dev/null 2>&1; then
    printf '\n%b\n' "${RED}✘ No se encontro resolvectl.${RESET}"
    printf '%s\n' "Este script requiere systemd-resolved."
    exit 1
fi

if ! command -v ip >/dev/null 2>&1; then
    printf '\n%b\n' "${RED}✘ No se encontro el comando ip.${RESET}"
    exit 1
fi

if ! systemctl is-active --quiet systemd-resolved; then
    printf '\n%b\n' "${YELLOW}⚠ systemd-resolved no esta activo.${RESET}"
    printf '%s\n' "Se necesita revisar el servicio antes de continuar."

    read -r -p "¿Desea intentar iniciar systemd-resolved? [S/n]: " answer
    answer="${answer:-S}"

    if [[ "$answer" =~ ^[sS]$ ]]; then
        if systemctl start systemd-resolved &&
           systemctl is-active --quiet systemd-resolved; then
            printf '%b\n' "${GREEN}✔ Servicio iniciado correctamente.${RESET}"
        else
            printf '%b\n' "${RED}✘ No se pudo iniciar systemd-resolved.${RESET}"
            printf '%s\n' "Revisa: systemctl status systemd-resolved"
            exit 1
        fi
    else
        printf '%s\n' "Operacion cancelada."
        exit 0
    fi
fi

# ---------------------- ENCABEZADO --------------------------

clear 2>/dev/null || true

# Ancho interior fijo del encabezado.
# Se conserva el diseño original con bordes dobles.
HEADER_WIDTH=50

draw_header_border() {
    printf '%b' "${CYAN}${BOLD}╔"
    printf '%*s' "$HEADER_WIDTH" '' | tr ' ' '═'
    printf '╗%b\n' "${RESET}"
}

draw_header_bottom() {
    printf '%b' "${CYAN}${BOLD}╚"
    printf '%*s' "$HEADER_WIDTH" '' | tr ' ' '═'
    printf '╝%b\n' "${RESET}"
}

draw_header_blank() {
    printf '%b' "${CYAN}${BOLD}║"
    printf '%*s' "$HEADER_WIDTH" ''
    printf '║%b\n' "${RESET}"
}

draw_header_text() {
    local text="$1"
    local left="$2"
    local right="$3"

    printf '%b' "${CYAN}${BOLD}║"
    printf '%*s' "$left" ''
    printf '%s' "$text"
    printf '%*s' "$right" ''
    printf '║%b\n' "${RESET}"
}

printf '\n'
draw_header_border
draw_header_blank

# Las líneas interiores mantienen un ancho visual de 50 columnas.
draw_header_text "🛡️  DNS REPAIR PRO" 15 16
draw_header_text "DIAGNOSTICO Y REPARACION" 13 13

draw_header_blank
draw_header_bottom

printf '\n'
printf '  %b %s\n' "${WHITE}📅${RESET}" "Fecha: $(date '+%d/%m/%Y %H:%M:%S')"
printf '  %b %s\n' "${WHITE}🖥️${RESET}" "Equipo: $(hostname 2>/dev/null || echo desconocido)"
printf '  %b %s\n' "${WHITE}⚙️${RESET}" "Servicio: systemd-resolved"
printf '\n'

# ---------------------- DETECTAR INTERFAZ -------------------

title "🔎 1. ANALISIS DE LA INTERFAZ"

IFACE="$(ip -4 route show default |
    awk 'NR==1 {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"

if [[ -n "$IFACE" ]] && ip link show "$IFACE" >/dev/null 2>&1; then
    INTERFACE_OK=1
    ok "Interfaz detectada: $IFACE"
else
    fail "No se encontro una interfaz con ruta IPv4 predeterminada."
    status_bad
    printf '\n'
    printf '%b\n' "${YELLOW}No es posible continuar sin una interfaz de red valida.${RESET}"
    exit 1
fi

if ip -4 addr show dev "$IFACE" | grep -q 'inet '; then
    IP_ADDR="$(ip -4 -o addr show dev "$IFACE" |
        awk 'NR==1 {print $4}')"
    ok "Direccion IPv4: ${IP_ADDR:-no disponible}"
else
    warn "La interfaz no tiene una direccion IPv4 asignada."
fi

if ip link show "$IFACE" | grep -q 'UP'; then
    ok "Interfaz habilitada."
else
    warn "La interfaz no aparece habilitada."
fi

# ---------------------- ESTADO ACTUAL -----------------------

title "📡 2. CONFIGURACION DNS ACTUAL"

CURRENT_STATUS="$(resolvectl status "$IFACE" 2>/dev/null || true)"
printf '%s\n' "$CURRENT_STATUS" |
    grep -E 'Current Scopes:|DefaultRoute setting:|Current DNS Server:|DNS Servers:|DNS Domain:' |
    while IFS= read -r entry; do
        printf '  %b %s\n' "${BLUE}›${RESET}" "$entry"
    done

mapfile -t CURRENT_DNS < <(
    resolvectl dns "$IFACE" 2>/dev/null |
        sed 's/^[^:]*://' |
        xargs -n1 2>/dev/null |
        awk 'NF'
)

# Si no hay DNS asociado a la interfaz, comprobar los DNS globales.
if [[ ${#CURRENT_DNS[@]} -eq 0 ]]; then
    mapfile -t CURRENT_DNS < <(
        resolvectl dns 2>/dev/null |
            sed 's/^[^:]*://' |
            xargs -n1 2>/dev/null |
            awk 'NF'
    )
fi

if [[ ${#CURRENT_DNS[@]} -gt 0 ]]; then
    ok "Se detectaron servidores DNS configurados."
else
    fail "No se detectaron servidores DNS asociados a la interfaz ni globalmente."
fi

if [[ -e /etc/resolv.conf ]]; then
    RESOLV_TARGET="$(readlink -f /etc/resolv.conf 2>/dev/null || true)"
    info "/etc/resolv.conf: ${RESOLV_TARGET:-archivo presente}"
else
    fail "No existe /etc/resolv.conf."
fi

# ---------------------- FUNCIONES DE PRUEBA -----------------

test_domain_resolution() {
    local domain="$1"

    if timeout 7 getent ahostsv4 "$domain" >/dev/null 2>&1; then
        return 0
    fi

    return 1
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
    if ! command -v curl >/dev/null 2>&1; then
        warn "curl no esta instalado; no se puede comprobar HTTPS."
        HTTPS_OK=0
        return
    fi

    if curl -fsSI --connect-timeout 5 --max-time 10 \
        https://github.com/ >/dev/null 2>&1; then
        HTTPS_OK=1
        ok "Conectividad HTTPS verificada."
    else
        HTTPS_OK=0
        warn "No se pudo verificar HTTPS hacia github.com."
    fi
}

test_oracle_dns() {
    ORACLE_OK=0

    if command -v dig >/dev/null 2>&1; then
        if dig +time=2 +tries=1 +short \
            @"$ORACLE_DNS" raw.githubusercontent.com A 2>/dev/null |
            grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
            ORACLE_OK=1
        fi
    elif command -v python3 >/dev/null 2>&1; then
        if timeout 4 python3 -c '
import random, socket, struct
server = "169.254.169.254"
name = "raw.githubusercontent.com"
ident = random.randrange(65536)
qname = b"".join(bytes([len(x)]) + x.encode() for x in name.split(".")) + b"\0"
packet = struct.pack("!HHHHHH", ident, 0x0100, 1, 0, 0, 0) + qname + struct.pack("!HH", 1, 1)
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(2)
s.sendto(packet, (server, 53))
data, _ = s.recvfrom(4096)
if len(data) < 12 or struct.unpack("!H", data[:2])[0] != ident or not (struct.unpack("!H", data[2:4])[0] & 0x8000):
    raise SystemExit(1)
answers = struct.unpack("!H", data[6:8])[0]
if answers < 1 or not (struct.unpack("!H", data[2:4])[0] & 0x000F) == 0:
    raise SystemExit(1)
' >/dev/null 2>&1; then
            ORACLE_OK=1
        fi
    else
        warn "No esta instalado dig ni python3; no se puede probar directamente el DNS de Oracle."
    fi

    if [[ "$ORACLE_OK" -eq 1 ]]; then
        ok "El servidor DNS de Oracle responde correctamente."
    else
        warn "No se pudo confirmar una respuesta DNS valida de Oracle."
    fi
}

# ---------------------- DIAGNOSTICO INICIAL -----------------

title "🧪 3. PRUEBAS DE FUNCIONAMIENTO"

test_all_domains
test_https

# Considerar correcto el DNS si:
#   - hay servidores DNS configurados,
#   - todos los dominios de prueba resuelven,
#   - y el servicio systemd-resolved esta activo.
#
# HTTPS se informa por separado porque tambien depende de
# rutas, firewall, TLS y conectividad general.

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

title "📋 4. RESULTADO DEL DIAGNOSTICO"

if [[ "$DNS_CONFIG_OK" -eq 1 ]]; then
    status_good
    printf '\n'
    ok "systemd-resolved esta activo."
    ok "Existen servidores DNS configurados."
    ok "Los dominios de prueba resuelven correctamente."

    if [[ "$HTTPS_OK" -eq 1 ]]; then
        ok "La conectividad HTTPS funciona."
    else
        warn "HTTPS no pudo verificarse; esto no demuestra por si solo un fallo DNS."
    fi

    printf '\n'
    line
    printf '%b\n' "${GREEN}${BOLD}  No se requieren reparaciones DNS.${RESET}"
    printf '%s\n' "  La configuracion actual se conserva sin cambios."
    line
    printf '\n'
    exit 0
fi

status_bad
printf '\n'
printf '%b\n' "${RED}${BOLD}  Se detectaron problemas en la configuracion DNS.${RESET}"
printf '\n'

if [[ ${#CURRENT_DNS[@]} -eq 0 ]]; then
    info "Diagnostico: no hay servidores DNS detectables."
fi

if [[ "$DNS_RESOLUTION_OK" -eq 0 ]]; then
    info "Diagnostico: falla la resolucion de uno o mas dominios."
fi

if ! systemctl is-active --quiet systemd-resolved; then
    info "Diagnostico: systemd-resolved no esta activo."
fi

printf '\n'
line
printf '\n'
read -r -p "  ¿Desea reparar los DNS? [S/n]: " ANSWER
ANSWER="${ANSWER:-S}"

if [[ ! "$ANSWER" =~ ^[sS]$ ]]; then
    printf '\n'
    warn "Reparacion cancelada por el usuario."
    printf '%s\n' "No se aplicaron cambios DNS."
    exit 0
fi

# ---------------------- RESPALDO -----------------------------

title "💾 5. COPIA DE SEGURIDAD"

BACKUP="/root/dns-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"

if [[ -f /etc/systemd/resolved.conf ]]; then
    cp -a /etc/systemd/resolved.conf "$BACKUP/" ||
        warn "No se pudo copiar resolved.conf."
fi

if [[ -d /etc/systemd/resolved.conf.d ]]; then
    cp -a /etc/systemd/resolved.conf.d "$BACKUP/" ||
        warn "No se pudo copiar resolved.conf.d."
fi

ok "Copia de seguridad guardada en: $BACKUP"

# ---------------------- SELECCION DNS -----------------------

title "🌐 6. SELECCION DEL SERVIDOR DNS"

DNS_SERVERS=()

test_oracle_dns

if [[ "$ORACLE_OK" -eq 1 ]]; then
    DNS_SERVERS=("$ORACLE_DNS")
    DNS_SOURCE="Oracle Cloud"
    ok "Se utilizara el DNS interno de Oracle Cloud."
else
    DNS_SERVERS=("${PUBLIC_DNS[@]}")
    DNS_SOURCE="DNS publicos Cloudflare y Google"
    warn "Se utilizara una alternativa publica."
    info "Servidores: ${DNS_SERVERS[*]}"
fi

# ---------------------- APLICAR REPARACION ------------------

title "🔧 7. APLICANDO CONFIGURACION"

REPAIR_ATTEMPTED=1

if ! systemctl is-active --quiet systemd-resolved; then
    if ! systemctl start systemd-resolved; then
        fail "No se pudo iniciar systemd-resolved."
        FINAL_STATUS="DESCONFIGURADO"
    fi
fi

if systemctl is-active --quiet systemd-resolved; then
    if resolvectl dns "$IFACE" "${DNS_SERVERS[@]}" &&
       resolvectl default-route "$IFACE" yes &&
       resolvectl flush-caches; then
        ok "Servidores DNS aplicados a $IFACE."
        ok "Ruta DNS predeterminada habilitada para la interfaz."
        ok "Cache DNS vaciada."
    else
        fail "No se pudo aplicar completamente la configuracion DNS."
    fi
fi

# ---------------------- VERIFICACION FINAL ------------------

title "🔬 8. VERIFICACION POSTERIOR"

DNS_RESOLUTION_OK=0
HTTPS_OK=0

test_all_domains
test_https

if [[ ${#DNS_SERVERS[@]} -gt 0 ]] &&
   [[ "$DNS_RESOLUTION_OK" -eq 1 ]] &&
   systemctl is-active --quiet systemd-resolved; then
    REPAIR_SUCCESS=1
    FINAL_STATUS="CONFIGURADO CORRECTAMENTE"
else
    REPAIR_SUCCESS=0
    FINAL_STATUS="DESCONFIGURADO"
fi

# ---------------------- RESUMEN FINAL -----------------------

title "📊 9. RESUMEN GENERAL"

printf '  %-25s ' "Interfaz:"
printf '%b\n' "${CYAN}${IFACE}${RESET}"

printf '  %-25s ' "DNS seleccionado:"
printf '%b\n' "${CYAN}${DNS_SOURCE:-No determinado}${RESET}"

printf '  %-25s ' "Servidores aplicados:"
printf '%b\n' "${CYAN}${DNS_SERVERS[*]:-Ninguno}${RESET}"

printf '  %-25s ' "Diagnostico inicial:"
if [[ "$INITIAL_STATUS" == "CONFIGURADO CORRECTAMENTE" ]]; then
    printf '%b\n' "${GREEN}${INITIAL_STATUS}${RESET}"
else
    printf '%b\n' "${RED}${INITIAL_STATUS}${RESET}"
fi

printf '  %-25s ' "Reparacion:"
if [[ "$REPAIR_ATTEMPTED" -eq 1 && "$REPAIR_SUCCESS" -eq 1 ]]; then
    printf '%b\n' "${GREEN}Aplicada y verificada${RESET}"
elif [[ "$REPAIR_ATTEMPTED" -eq 1 ]]; then
    printf '%b\n' "${RED}No se pudo verificar${RESET}"
else
    printf '%b\n' "${YELLOW}No realizada${RESET}"
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

printf '  %-25s ' "Copia de seguridad:"
printf '%b\n' "${CYAN}${BACKUP:-No necesaria}${RESET}"

printf '\n'
line

if [[ "$FINAL_STATUS" == "CONFIGURADO CORRECTAMENTE" ]]; then
    status_good
    printf '\n'
    printf '%b\n' "${GREEN}  ✔ La resolucion DNS funciona despues de la reparacion.${RESET}"
    printf '%b\n' "${GREEN}  ✔ No se requiere otra modificacion DNS inmediata.${RESET}"
else
    status_bad
    printf '\n'
    printf '%b\n' "${RED}  ✘ La reparacion no logro restablecer la resolucion DNS.${RESET}"
    printf '%s\n' "  Comprueba conectividad de red, rutas, firewall y el servicio DNS."
fi

printf '\n'
line
printf '%b\n' "${GRAY}  DNS REPAIR PRO | Diagnostico finalizado.${RESET}"
printf '\n'
