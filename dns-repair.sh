#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
#             DNS REPAIR PRO | NETWORK MANAGER
#              DIAGNOSTICO Y REPARACION DNS
# ============================================================
#
# FUNCIONES:
#   - Dashboard visual moderno con colores e indicadores.
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
    ORANGE='\033[38;5;208m'
    PURPLE='\033[38;5;141m'
    TEAL='\033[38;5;43m'
else
    RESET='' BOLD='' DIM=''
    RED='' GREEN='' YELLOW=''
    BLUE='' CYAN='' MAGENTA=''
    WHITE='' GRAY='' ORANGE=''
    PURPLE='' TEAL=''
fi

# ---------------------- VARIABLES ---------------------------

ORACLE_DNS="169.254.169.254"
PUBLIC_DNS=("1.1.1.1" "8.8.8.8")
TEST_DOMAINS=("raw.githubusercontent.com" "google.com")

IFACE=""
IP_ADDR=""
DNS_SOURCE=""
DNS_SERVERS=()
CURRENT_DNS=()
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

# Linea continua para separar secciones.
line() {
    printf '  %b\n' "${GRAY}────────────────────────────────────────────────────${RESET}"
}

# Separador secundario.
line_soft() {
    printf '  %b\n' "${BLUE}┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄ ┄${RESET}"
}

# Titulos de seccion con color y numeracion.
title() {
    printf '\n  %b\n' "${CYAN}${BOLD}$1${RESET}"
    line
}

# Mensaje de operacion correcta.
ok() {
    printf '  %b %b%s%b\n' \
        "${GREEN}✔${RESET}" \
        "${GREEN}" "$1" "${RESET}"
    OK_ITEMS+=("$1")
}

# Mensaje de advertencia.
warn() {
    printf '  %b %b%s%b\n' \
        "${YELLOW}⚠${RESET}" \
        "${YELLOW}" "$1" "${RESET}"
    WARNINGS+=("$1")
}

# Mensaje de error.
fail() {
    printf '  %b %b%s%b\n' \
        "${RED}✘${RESET}" \
        "${RED}" "$1" "${RESET}"
    ERRORS+=("$1")
}

# Mensaje informativo.
info() {
    printf '  %b %b%s%b\n' \
        "${CYAN}ℹ${RESET}" \
        "${CYAN}" "$1" "${RESET}"
}

# Detalle tecnico con sangria adicional.
detail() {
    printf '     %b %b%s%b\n' \
        "${BLUE}›${RESET}" \
        "${BLUE}" "$1" "${RESET}"
}

# Etiqueta con valor alineado.
show_value() {
    printf '  %b%-25s%b %b%s%b\n' \
        "${WHITE}${BOLD}" "$1" \
        "${RESET}" \
        "${CYAN}" "$2" "${RESET}"
}

# Estado DNS correcto.
status_good() {
    printf '\n  %b\n' \
        "${GREEN}${BOLD}✔ DNS OPERATIVO${RESET}   ${GREEN}Configuracion verificada${RESET}"
}

# Estado DNS con problemas.
status_bad() {
    printf '\n  %b\n' \
        "${RED}${BOLD}✘ DNS CON PROBLEMAS${RESET}   ${YELLOW}Requiere revision${RESET}"
}

pause_short() {
    sleep 0.2
}

# ---------------------- VALIDACIONES ------------------------

if [[ $EUID -ne 0 ]]; then
    printf '\n%b\n' "${RED}${BOLD}✘ Ejecuta este script como root.${RESET}"
    printf '  %b\n' "${CYAN}Ejemplo: sudo bash dns-repair.sh${RESET}"
    exit 1
fi

if ! command -v resolvectl >/dev/null 2>&1; then
    printf '\n%b\n' "${RED}${BOLD}✘ No se encontro resolvectl.${RESET}"
    printf '  %b\n' "${YELLOW}Este script requiere systemd-resolved.${RESET}"
    exit 1
fi

if ! command -v ip >/dev/null 2>&1; then
    printf '\n%b\n' "${RED}${BOLD}✘ No se encontro el comando ip.${RESET}"
    exit 1
fi

if ! systemctl is-active --quiet systemd-resolved; then
    printf '\n%b\n' "${YELLOW}${BOLD}⚠ systemd-resolved no esta activo.${RESET}"
    printf '  %b\n' "${WHITE}Se necesita revisar el servicio antes de continuar.${RESET}"
    printf '\n'

    read -r -p "  ¿Desea intentar iniciar systemd-resolved? [S/n]: " answer
    answer="${answer:-S}"

    if [[ "$answer" =~ ^[sS]$ ]]; then
        if systemctl start systemd-resolved &&
           systemctl is-active --quiet systemd-resolved; then
            printf '\n%b\n' "${GREEN}${BOLD}✔ Servicio iniciado correctamente.${RESET}"
        else
            printf '\n%b\n' "${RED}${BOLD}✘ No se pudo iniciar systemd-resolved.${RESET}"
            printf '  %b\n' "${YELLOW}Revisa: systemctl status systemd-resolved${RESET}"
            exit 1
        fi
    else
        printf '\n%b\n' "${YELLOW}Operacion cancelada.${RESET}"
        exit 0
    fi
fi

# ---------------------- ENCABEZADO --------------------------

clear 2>/dev/null || true

printf '\n'
printf '  %b\n' "${CYAN}${BOLD}╭────────────────────────────────────────────────────╮${RESET}"
printf '  %b\n' "${CYAN}${BOLD}│                                                    │${RESET}"
printf '  %b\n' "${CYAN}${BOLD}│                                                    │${RESET}"
printf '  %b\n' "${CYAN}${BOLD}│               🛡️  DNS REPAIR PRO                   │${RESET}"
printf '  %b\n' "${CYAN}${BOLD}│              NETWORK MANAGER                       │${RESET}"
printf '  %b\n' "${CYAN}${BOLD}│                                                    │${RESET}"
printf '  %b\n' "${CYAN}${BOLD}│          DIAGNOSTICO Y REPARACION DNS              │${RESET}"
printf '  %b\n' "${CYAN}${BOLD}│                                                    │${RESET}"
printf '  %b\n' "${CYAN}${BOLD}╰────────────────────────────────────────────────────╯${RESET}"

printf '\n'
show_value "🛠️  Version:" "4.0"
show_value "📅 Fecha:" "$(date '+%d/%m/%Y %H:%M:%S')"
show_value "🖥️  Equipo:" "$(hostname 2>/dev/null || echo desconocido)"
show_value "⚙️  Servicio:" "systemd-resolved"

printf '\n'
printf '  %b\n' "${WHITE}Diagnostico inteligente de conectividad DNS.${RESET}"
printf '  %b\n' "${GRAY}Los cambios requieren tu confirmacion.${RESET}"
printf '\n'
line

# ---------------------- DETECTAR INTERFAZ -------------------

title "🌐 01 · ANALISIS DE LA INTERFAZ"

IFACE="$(ip -4 route show default |
    awk 'NR==1 {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"

if [[ -n "$IFACE" ]] && ip link show "$IFACE" >/dev/null 2>&1; then
    INTERFACE_OK=1
    ok "Interfaz detectada: $IFACE"
else
    fail "No se encontro una interfaz con ruta IPv4 predeterminada."
    status_bad
    printf '\n'
    info "No es posible continuar sin una interfaz de red valida."
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

DEFAULT_ROUTE="$(ip -4 route show default dev "$IFACE" 2>/dev/null |
    head -n 1 || true)"

if [[ -n "$DEFAULT_ROUTE" ]]; then
    detail "Ruta: $DEFAULT_ROUTE"
else
    warn "No se encontro una ruta predeterminada para la interfaz."
fi

# ---------------------- ESTADO ACTUAL -----------------------

title "📡 02 · CONFIGURACION DNS ACTUAL"

CURRENT_STATUS="$(resolvectl status "$IFACE" 2>/dev/null || true)"

if [[ -n "$CURRENT_STATUS" ]]; then
    printf '%s\n' "$CURRENT_STATUS" |
        grep -E 'Current Scopes:|DefaultRoute setting:|Current DNS Server:|DNS Servers:|DNS Domain:' |
        while IFS= read -r entry; do
            detail "$entry"
        done
else
    warn "No se pudo obtener el estado DNS de la interfaz."
fi

mapfile -t CURRENT_DNS < <(
    resolvectl dns "$IFACE" 2>/dev/null |
        sed 's/^[^:]*://' |
        xargs -n1 2>/dev/null |
        awk 'NF'
)

# Si no hay DNS asociados a la interfaz, comprobar los DNS globales.
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

    for dns in "${CURRENT_DNS[@]}"; do
        detail "🌐 $dns"
    done
else
    fail "No se detectaron servidores DNS asociados a la interfaz ni globalmente."
fi

if [[ -e /etc/resolv.conf ]]; then
    RESOLV_TARGET="$(readlink -f /etc/resolv.conf 2>/dev/null || true)"
    ok "/etc/resolv.conf existe."
    detail "Destino: ${RESOLV_TARGET:-archivo presente}"

    if [[ -r /etc/resolv.conf ]]; then
        while IFS= read -r dns_line; do
            [[ "$dns_line" == nameserver* ]] && detail "$dns_line"
        done < /etc/resolv.conf
    fi
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

qname = b"".join(
    bytes([len(x)]) + x.encode()
    for x in name.split(".")
) + b"\0"

packet = (
    struct.pack("!HHHHHH", ident, 0x0100, 1, 0, 0, 0)
    + qname
    + struct.pack("!HH", 1, 1)
)

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(2)

try:
    s.sendto(packet, (server, 53))
    data, _ = s.recvfrom(4096)

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

finally:
    s.close()
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

title "🧪 03 · PRUEBAS DE FUNCIONAMIENTO"

info "Probando resolucion de dominios..."
test_all_domains

printf '\n'
info "Probando conectividad HTTPS..."
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

# ---------------------- RESULTADO DEL DIAGNOSTICO -----------

title "📋 04 · RESULTADO DEL DIAGNOSTICO"

if [[ "$DNS_CONFIG_OK" -eq 1 ]]; then
    status_good

    printf '\n'
    ok "El servicio DNS esta activo."
    ok "Se detectaron servidores DNS configurados."
    ok "Los dominios de prueba resuelven correctamente."

    if [[ "$HTTPS_OK" -eq 1 ]]; then
        ok "HTTPS funciona correctamente."
    else
        warn "HTTPS no pudo verificarse; esto no demuestra por si solo un fallo DNS."
    fi

    printf '\n'
    line
    printf '\n  %b\n' "${GREEN}${BOLD}✨ No se requieren reparaciones DNS.${RESET}"
    printf '  %b\n' "${CYAN}ℹ La configuracion actual se conserva sin cambios.${RESET}"
    printf '\n'
    exit 0
fi

status_bad

printf '\n'
printf '  %b\n' "${RED}${BOLD}Se detectaron problemas en la configuracion DNS.${RESET}"
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
    info "No se aplicaron cambios DNS."
    exit 0
fi

# ---------------------- RESPALDO -----------------------------

title "💾 05 · COPIA DE SEGURIDAD"

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

ok "Copia de seguridad guardada."
detail "$BACKUP"

# ---------------------- SELECCION DNS -----------------------

title "🌐 06 · SELECCION DEL SERVIDOR DNS"

DNS_SERVERS=()

test_oracle_dns

if [[ "$ORACLE_OK" -eq 1 ]]; then
    DNS_SERVERS=("$ORACLE_DNS")
    DNS_SOURCE="Oracle Cloud"

    ok "Se utilizara el DNS interno de Oracle Cloud."
    detail "Servidor seleccionado: $ORACLE_DNS"
else
    DNS_SERVERS=("${PUBLIC_DNS[@]}")
    DNS_SOURCE="DNS publicos Cloudflare y Google"

    warn "Se utilizara una alternativa publica."
    detail "Cloudflare: ${PUBLIC_DNS[0]}"
    detail "Google: ${PUBLIC_DNS[1]}"
fi

# ---------------------- APLICAR REPARACION ------------------

title "🔧 07 · APLICANDO CONFIGURACION"

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

title "🔬 08 · VERIFICACION POSTERIOR"

DNS_RESOLUTION_OK=0
HTTPS_OK=0

info "Verificando resolucion de dominios..."
test_all_domains

printf '\n'
info "Verificando conectividad HTTPS..."
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

title "📊 09 · RESUMEN GENERAL"

printf '\n'
show_value "🖧 Interfaz:" "${IFACE:-No detectada}"
show_value "🌐 DNS seleccionado:" "${DNS_SOURCE:-No determinado}"
show_value "📡 Servidores aplicados:" "${DNS_SERVERS[*]:-Ninguno}"
show_value "💾 Copia de seguridad:" "${BACKUP:-No necesaria}"

printf '\n'
line
printf '\n  %b\n' "${WHITE}${BOLD}ESTADO DE LAS COMPROBACIONES${RESET}"
line_soft

printf '  %-25s ' "Diagnostico inicial:"
if [[ "$INITIAL_STATUS" == "CONFIGURADO CORRECTAMENTE" ]]; then
    printf '%b\n' "${GREEN}${BOLD}${INITIAL_STATUS}${RESET}"
else
    printf '%b\n' "${RED}${BOLD}${INITIAL_STATUS}${RESET}"
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
    ok "La resolucion DNS funciona despues de la reparacion."
    ok "No se requiere otra modificacion DNS inmediata."
else
    status_bad

    printf '\n'
    fail "La reparacion no logro restablecer la resolucion DNS."
    info "Comprueba conectividad de red, rutas, firewall y servicio DNS."
fi

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    printf '\n'
    line
    printf '\n  %b\n' "${YELLOW}${BOLD}⚠ ADVERTENCIAS REGISTRADAS: ${#WARNINGS[@]}${RESET}"
    line_soft

    for item in "${WARNINGS[@]}"; do
        printf '  %b %s\n' "${YELLOW}›${RESET}" "$item"
    done
fi

if [[ ${#ERRORS[@]} -gt 0 ]]; then
    printf '\n'
    line
    printf '\n  %b\n' "${RED}${BOLD}✘ ERRORES REGISTRADOS: ${#ERRORS[@]}${RESET}"
    line_soft

    for item in "${ERRORS[@]}"; do
        printf '  %b %s\n' "${RED}›${RESET}" "$item"
    done
fi

printf '\n'
line
printf '\n'
printf '  %b\n' "${CYAN}${BOLD}🛡️ DNS REPAIR PRO | NETWORK MANAGER${RESET}"
printf '  %b\n' "${GRAY}Diagnostico finalizado.${RESET}"
printf '\n'

if [[ "$FINAL_STATUS" == "CONFIGURADO CORRECTAMENTE" ]]; then
    exit 0
else
    exit 1
fi
