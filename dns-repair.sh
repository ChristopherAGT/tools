#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
#             DNS REPAIR PRO | NETWORK MANAGER
#              DIAGNOSTICO Y REPARACION DNS
# ============================================================
#
# FUNCIONES:
#   - Dashboard moderno con colores, iconos e indicadores.
#   - Diagnostico automatico de DNS.
#   - Deteccion de interfaz, IPv4 y servidores DNS.
#   - Pruebas de resolucion de dominios.
#   - Verificacion de conectividad HTTPS.
#   - Confirmacion antes de modificar la configuracion.
#   - Prioridad para el DNS interno de Oracle Cloud.
#   - Alternativa con DNS publicos si Oracle no responde.
#   - Copia de seguridad antes de reparar.
#   - Verificacion posterior de la reparacion.
#   - Resumen final con resultados detallados.
#
# IMPORTANTE:
#   - No modifica archivos ajenos a la configuracion DNS.
#   - Los cambios realizados con resolvectl son temporales.
#   - La copia de seguridad protege archivos persistentes
#     de systemd-resolved, si existen.
#   - No cambia reglas de firewall ni rutas de red.
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
    BG_BLUE='\033[44m'
else
    RESET='' BOLD='' DIM=''
    RED='' GREEN='' YELLOW=''
    BLUE='' CYAN='' MAGENTA=''
    WHITE='' GRAY='' BG_BLUE=''
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
DNS_APPLY_OK=0

# ---------------------- UTILIDADES --------------------------

line() {
    printf '%b\n' "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

line_accent() {
    printf '%b\n' "${CYAN}────────────────────────────────────────────────────${RESET}"
}

title() {
    printf '\n%b\n' "${CYAN}${BOLD}  $1${RESET}"
    line_accent
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

detail() {
    printf '  %b %s\n' "${BLUE}›${RESET}" "$1"
}

status_good() {
    printf '\n%b\n' "${GREEN}${BOLD}  🟢 DNS · CONFIGURADO CORRECTAMENTE${RESET}"
}

status_bad() {
    printf '\n%b\n' "${RED}${BOLD}  🔴 DNS · SE DETECTARON PROBLEMAS${RESET}"
}

pause_short() {
    sleep 0.2
}

ask_yes_no() {
    local answer
    read -r -p "  $1 [S/n]: " answer
    answer="${answer:-S}"
    [[ "$answer" =~ ^[sS]$ ]]
}

show_value() {
    local label="$1"
    local value="$2"
    printf '  %b %-25s%b %s\n' \
        "${WHITE}" "$label" "${RESET}" "$value"
}

# ---------------------- VALIDACIONES ------------------------

if [[ $EUID -ne 0 ]]; then
    printf '\n%b\n' "${RED}✘ Ejecuta este script como root.${RESET}"
    printf '%s\n' "  Ejemplo: sudo bash dns-repair.sh"
    exit 1
fi

for cmd in resolvectl ip systemctl timeout awk grep sed date hostname; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        printf '\n%b\n' "${RED}✘ Falta el comando requerido: $cmd${RESET}"
        exit 1
    fi
done

# ---------------------- ENCABEZADO --------------------------

clear 2>/dev/null || true

printf '\n'
printf '%b\n' "${CYAN}${BOLD}╭──────────────────────────────────────────╮${RESET}"
printf '%b\n' "${CYAN}${BOLD}│                                          │${RESET}"
printf '%b\n' "${CYAN}${BOLD}│             DNS REPAIR PRO               │${RESET}"
printf '%b\n' "${CYAN}${BOLD}│           NETWORK MANAGER                │${RESET}"
printf '%b\n' "${CYAN}${BOLD}│                                          │${RESET}"
printf '%b\n' "${CYAN}${BOLD}╰──────────────────────────────────────────╯${RESET}"
printf '\n'
printf '  %b %s\n' "${MAGENTA}✦${RESET}" "DIAGNOSTICO Y REPARACION DNS"
printf '  %b %s\n' "${WHITE}📅${RESET}" "Fecha: $(date '+%d/%m/%Y %H:%M:%S')"
printf '  %b %s\n' "${WHITE}🖥️${RESET}" "Equipo: $(hostname 2>/dev/null || echo desconocido)"
printf '  %b %s\n' "${WHITE}⚙️${RESET}" "Servicio: systemd-resolved"
printf '  %b %s\n' "${WHITE}🛡️${RESET}" "Modo: diagnostico seguro con confirmacion"
printf '\n'
line

# ---------------------- SERVICIO DNS ------------------------

title "⚙️  SERVICIO SYSTEMD-RESOLVED"

if ! systemctl is-active --quiet systemd-resolved; then
    warn "systemd-resolved no esta activo."
    info "El diagnostico necesita que el servicio este funcionando."

    if ask_yes_no "¿Deseas intentar iniciar systemd-resolved?"; then
        if systemctl start systemd-resolved &&
           systemctl is-active --quiet systemd-resolved; then
            ok "Servicio systemd-resolved iniciado correctamente."
        else
            fail "No se pudo iniciar systemd-resolved."
            info "Revisa: systemctl status systemd-resolved"
            exit 1
        fi
    else
        warn "Operacion cancelada por el usuario."
        exit 0
    fi
else
    ok "systemd-resolved esta activo."
fi

# ---------------------- DETECTAR INTERFAZ -------------------

title "🔎 1. ANALISIS DE LA INTERFAZ"

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
    ok "Interfaz detectada: $IFACE"
else
    fail "No se encontro una interfaz con ruta IPv4 predeterminada."
    info "Rutas IPv4 disponibles:"
    ip -4 route show 2>/dev/null || true
    status_bad
    exit 1
fi

IP_ADDR="$(ip -4 -o addr show dev "$IFACE" 2>/dev/null |
    awk 'NR==1 {print $4}')"

if [[ -n "$IP_ADDR" ]]; then
    ok "Direccion IPv4: $IP_ADDR"
else
    warn "La interfaz no tiene una direccion IPv4 asignada."
fi

LINK_INFO="$(ip link show "$IFACE" 2>/dev/null || true)"

if grep -qE '<[^>]*UP[^>]*>' <<< "$LINK_INFO"; then
    ok "Interfaz habilitada."
else
    warn "La interfaz no aparece habilitada."
fi

DEFAULT_ROUTE="$(ip -4 route show default dev "$IFACE" 2>/dev/null |
    head -n 1 || true)"

if [[ -n "$DEFAULT_ROUTE" ]]; then
    detail "Ruta predeterminada: $DEFAULT_ROUTE"
else
    warn "No se encontro una ruta predeterminada para $IFACE."
fi

# ---------------------- ESTADO ACTUAL -----------------------

title "📡 2. CONFIGURACION DNS ACTUAL"

CURRENT_STATUS="$(resolvectl status "$IFACE" 2>/dev/null || true)"

if [[ -n "$CURRENT_STATUS" ]]; then
    printf '%s\n' "$CURRENT_STATUS" |
        grep -E 'Current Scopes:|DefaultRoute setting:|Current DNS Server:|DNS Servers:|DNS Domain:' |
        while IFS= read -r entry; do
            detail "$entry"
        done
else
    warn "No se pudo obtener el estado DNS de $IFACE."
fi

# Obtener los DNS asociados a la interfaz.
mapfile -t CURRENT_DNS < <(
    resolvectl dns "$IFACE" 2>/dev/null |
        sed 's/^[^:]*://' |
        xargs -n1 2>/dev/null |
        awk 'NF'
)

# Si no hay DNS asociados a la interfaz, revisar los DNS globales.
if [[ ${#CURRENT_DNS[@]} -eq 0 ]]; then
    mapfile -t CURRENT_DNS < <(
        resolvectl dns 2>/dev/null |
            sed 's/^[^:]*://' |
            xargs -n1 2>/dev/null |
            awk 'NF'
    )

    if [[ ${#CURRENT_DNS[@]} -gt 0 ]]; then
        info "Se encontraron servidores DNS globales."
    fi
fi

# Mostrar los servidores detectados sin duplicarlos.
if [[ ${#CURRENT_DNS[@]} -gt 0 ]]; then
    mapfile -t CURRENT_DNS < <(
        printf '%s\n' "${CURRENT_DNS[@]}" | awk '!seen[$0]++'
    )

    ok "Servidores DNS detectados: ${CURRENT_DNS[*]}"
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
        # Consulta DNS UDP directa al servidor interno de Oracle.
        # Se valida el identificador, la respuesta y el codigo DNS.
        if timeout 4 python3 -c '
import random
import socket
import struct

server = "169.254.169.254"
name = "raw.githubusercontent.com"
ident = random.randrange(65536)

qname = b"".join(
    bytes([len(label)]) + label.encode()
    for label in name.split(".")
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

finally:
    sock.close()
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

info "Probando resolucion de dominios..."
test_all_domains

printf '\n'
info "Comprobando conectividad HTTPS..."
test_https

# Considerar correcto el DNS si:
#   - hay servidores DNS configurados,
#   - todos los dominios de prueba resuelven,
#   - y systemd-resolved esta activo.
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

title "📋 4. RESULTADO DEL DIAGNOSTICO"

if [[ "$DNS_CONFIG_OK" -eq 1 ]]; then
    status_good

    printf '\n'
    ok "systemd-resolved esta activo."
    ok "Existen servidores DNS detectados."
    ok "Los dominios de prueba resuelven correctamente."

    if [[ "$HTTPS_OK" -eq 1 ]]; then
        ok "La conectividad HTTPS funciona."
    else
        warn "HTTPS no pudo verificarse; esto no demuestra por si solo un fallo DNS."
    fi

    printf '\n'
    line
    printf '\n%b\n' "${GREEN}${BOLD}  ✨ No se requieren reparaciones DNS.${RESET}"
    printf '%b\n' "${WHITE}  La configuracion actual se conserva sin cambios.${RESET}"
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

if ! ask_yes_no "¿Deseas reparar los DNS?"; then
    printf '\n'
    warn "Reparacion cancelada por el usuario."
    info "No se aplicaron cambios DNS."
    exit 0
fi

# ---------------------- RESPALDO -----------------------------

title "💾 5. COPIA DE SEGURIDAD"

BACKUP="/root/dns-backup-$(date +%Y%m%d-%H%M%S)"

if ! mkdir -p "$BACKUP"; then
    fail "No se pudo crear la carpeta de respaldo."
    exit 1
fi

BACKUP_COUNT=0
BACKUP_ERRORS=0

if [[ -f /etc/systemd/resolved.conf ]]; then
    if cp -a /etc/systemd/resolved.conf "$BACKUP/"; then
        ok "Respaldo creado: resolved.conf"
        ((BACKUP_COUNT+=1))
    else
        warn "No se pudo copiar resolved.conf."
        ((BACKUP_ERRORS+=1))
    fi
fi

if [[ -d /etc/systemd/resolved.conf.d ]]; then
    if cp -a /etc/systemd/resolved.conf.d "$BACKUP/"; then
        ok "Respaldo creado: resolved.conf.d"
        ((BACKUP_COUNT+=1))
    else
        warn "No se pudo copiar resolved.conf.d."
        ((BACKUP_ERRORS+=1))
    fi
fi

if [[ -e /etc/resolv.conf || -L /etc/resolv.conf ]]; then
    if cp -a /etc/resolv.conf "$BACKUP/"; then
        ok "Respaldo creado: resolv.conf del sistema"
        ((BACKUP_COUNT+=1))
    else
        warn "No se pudo copiar /etc/resolv.conf."
        ((BACKUP_ERRORS+=1))
    fi
fi

if [[ "$BACKUP_COUNT" -gt 0 ]]; then
    ok "Copia de seguridad guardada en: $BACKUP"
else
    warn "No se encontraron archivos persistentes para respaldar."
    info "La carpeta de respaldo es: $BACKUP"
fi

if [[ "$BACKUP_ERRORS" -gt 0 ]]; then
    warn "Uno o mas archivos no pudieron respaldarse."
    if ! ask_yes_no "¿Deseas continuar de todos modos?"; then
        warn "Reparacion cancelada porque el respaldo fue incompleto."
        exit 1
    fi
fi

# ---------------------- SELECCION DNS -----------------------

title "🌐 6. SELECCION DEL SERVIDOR DNS"

DNS_SERVERS=()

test_oracle_dns

if [[ "$ORACLE_OK" -eq 1 ]]; then
    DNS_SERVERS=("$ORACLE_DNS")
    DNS_SOURCE="Oracle Cloud"
    ok "Se utilizara el DNS interno de Oracle Cloud."
    detail "Servidor: $ORACLE_DNS"
else
    DNS_SERVERS=("${PUBLIC_DNS[@]}")
    DNS_SOURCE="DNS publicos Cloudflare y Google"
    warn "El DNS interno de Oracle no pudo verificarse."
    info "Se utilizara una alternativa publica."
    detail "Cloudflare: ${PUBLIC_DNS[0]}"
    detail "Google:     ${PUBLIC_DNS[1]}"
fi

# ---------------------- APLICAR REPARACION ------------------

title "🔧 7. APLICANDO CONFIGURACION"

REPAIR_ATTEMPTED=1
DNS_APPLY_OK=0

if ! systemctl is-active --quiet systemd-resolved; then
    if systemctl start systemd-resolved &&
       systemctl is-active --quiet systemd-resolved; then
        ok "Servicio systemd-resolved iniciado."
    else
        fail "No se pudo iniciar systemd-resolved."
    fi
fi

if systemctl is-active --quiet systemd-resolved; then
    if resolvectl dns "$IFACE" "${DNS_SERVERS[@]}"; then
        ok "Servidores DNS aplicados a $IFACE."

        if resolvectl default-route "$IFACE" yes; then
            ok "Ruta DNS predeterminada habilitada para la interfaz."
            DNS_APPLY_OK=1
        else
            fail "No se pudo habilitar la ruta DNS predeterminada."
        fi

        if resolvectl flush-caches; then
            ok "Cache DNS vaciada."
        else
            warn "No se pudo vaciar la cache DNS."
        fi
    else
        fail "No se pudieron aplicar los servidores DNS a $IFACE."
    fi
else
    fail "systemd-resolved no esta activo; no se aplicaron los DNS."
fi

if [[ "$DNS_APPLY_OK" -eq 0 ]]; then
    warn "La aplicacion de la configuracion DNS no se completo correctamente."
fi

# ---------------------- VERIFICACION FINAL ------------------

title "🔬 8. VERIFICACION POSTERIOR"

DNS_RESOLUTION_OK=0
HTTPS_OK=0

if systemctl is-active --quiet systemd-resolved; then
    ok "systemd-resolved permanece activo."
else
    fail "systemd-resolved no esta activo tras la reparacion."
fi

printf '\n'
info "Volviendo a probar la resolucion de dominios..."
test_all_domains

printf '\n'
info "Volviendo a comprobar HTTPS..."
test_https

# Verificar que los servidores seleccionados aparecen en la
# configuracion de la interfaz despues de aplicar los cambios.
POST_DNS="$(resolvectl dns "$IFACE" 2>/dev/null || true)"

if [[ -n "$POST_DNS" ]]; then
    detail "Configuracion DNS actualizada: $POST_DNS"
else
    warn "No se pudo leer la configuracion DNS posterior."
fi

if [[ "$DNS_APPLY_OK" -eq 1 ]] &&
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

printf '\n'
show_value "🖧 Interfaz:" "${IFACE:-No detectada}"
show_value "🌐 DNS seleccionado:" "${DNS_SOURCE:-No determinado}"
show_value "📡 Servidores DNS:" "${DNS_SERVERS[*]:-Ninguno}"
show_value "💾 Copia de seguridad:" "${BACKUP:-No creada}"

printf '\n'
line_accent
printf '%b\n' "${WHITE}${BOLD}  ESTADO DE LAS COMPROBACIONES${RESET}"
line_accent

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

printf '  %-25s ' "Interfaz:"
if [[ "$INTERFACE_OK" -eq 1 ]]; then
    printf '%b\n' "${GREEN}Detectada${RESET}"
else
    printf '%b\n' "${RED}No detectada${RESET}"
fi

printf '  %-25s ' "Aplicacion DNS:"
if [[ "$DNS_APPLY_OK" -eq 1 ]]; then
    printf '%b\n' "${GREEN}Completada${RESET}"
else
    printf '%b\n' "${RED}Incompleta${RESET}"
fi

printf '\n'
line

if [[ "$FINAL_STATUS" == "CONFIGURADO CORRECTAMENTE" ]]; then
    status_good

    printf '\n'
    printf '%b\n' "${GREEN}  ✔ La resolucion DNS funciona despues de la reparacion.${RESET}"
    printf '%b\n' "${GREEN}  ✔ systemd-resolved esta activo.${RESET}"
    printf '%b\n' "${GREEN}  ✔ No se requiere otra modificacion DNS inmediata.${RESET}"
else
    status_bad

    printf '\n'
    printf '%b\n' "${RED}  ✘ No se pudo confirmar una reparacion DNS completa.${RESET}"
    printf '%b\n' "${YELLOW}  ⚠ Revisa la conectividad, las rutas y el firewall.${RESET}"
    printf '%b\n' "${YELLOW}  ⚠ Comprueba tambien systemd-resolved y los DNS del proveedor.${RESET}"
fi

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    printf '\n'
    line_accent
    printf '%b\n' "${YELLOW}${BOLD}  ⚠ ADVERTENCIAS: ${#WARNINGS[@]}${RESET}"

    for item in "${WARNINGS[@]}"; do
        printf '  %b %s\n' "${YELLOW}›${RESET}" "$item"
    done
fi

if [[ ${#ERRORS[@]} -gt 0 ]]; then
    printf '\n'
    line_accent
    printf '%b\n' "${RED}${BOLD}  ✘ ERRORES REGISTRADOS: ${#ERRORS[@]}${RESET}"

    for item in "${ERRORS[@]}"; do
        printf '  %b %s\n' "${RED}›${RESET}" "$item"
    done
fi

printf '\n'
line
printf '%b\n' "${CYAN}${BOLD}  🛡️ DNS REPAIR PRO${RESET}"
printf '%b\n' "${GRAY}  Network Manager · Diagnostico finalizado${RESET}"
printf '\n'

if [[ "$FINAL_STATUS" == "CONFIGURADO CORRECTAMENTE" ]]; then
    exit 0
else
    exit 1
fi
