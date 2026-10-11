#!/usr/bin/env bash
# ============================================================
# ADMRufu 2.0 | Gestor de Firewalld
# Apertura de puertos TCP/UDP
# Autor: ChristopherAGT | Guatemala
# ============================================================

set -o pipefail
export LC_ALL=C

# ── Colores ──────────────────────────────────────────────────
VERDE=$'\033[1;32m'
ROJO=$'\033[1;31m'
AZUL=$'\033[1;34m'
CELESTE=$'\033[1;36m'
AMARILLO=$'\033[1;33m'
BLANCO=$'\033[1;37m'
GRIS=$'\033[0;90m'
NEGRITA=$'\033[1m'
RESET=$'\033[0m'

ANCHO=54
INTERIOR=$((ANCHO - 2))

# ── Utilidades visuales ──────────────────────────────────────
repetir() {
    local caracter="$1" cantidad="$2" i
    for ((i = 0; i < cantidad; i++)); do
        printf '%s' "$caracter"
    done
}

titulo() {
    printf '\n%b' "${AZUL}${NEGRITA}╔"
    repetir '═' "$INTERIOR"
    printf '╗%b\n' "$RESET"

    centrar "ADMRUFU 2.0"
    centrar "GESTOR DE FIREWALLD"

    printf '%b' "${AZUL}${NEGRITA}╠"
    repetir '═' "$INTERIOR"
    printf '╣%b\n' "$RESET"

    centrar "Apertura de puertos TCP / UDP"
    centrar "ChristopherAGT | Guatemala"

    printf '%b' "${AZUL}${NEGRITA}╚"
    repetir '═' "$INTERIOR"
    printf '╝%b\n' "$RESET"
}

centrar() {
    local texto="$1"
    local longitud=${#1}
    local izquierda derecha

    ((longitud > INTERIOR)) && texto="${texto:0:$INTERIOR}" &&
        longitud=$INTERIOR

    izquierda=$(((INTERIOR - longitud) / 2))
    derecha=$((INTERIOR - longitud - izquierda))

    printf '%b%*s%b%*s%b\n' \
        "${AZUL}${NEGRITA}║${RESET}" \
        "$izquierda" "" "$texto" \
        "$derecha" "" \
        "${AZUL}${NEGRITA}║${RESET}"
}

separador() {
    printf '\n%b' "${CELESTE}${NEGRITA}┌─ $1 "
    local usados=$((${#1} + 4))
    local faltan=$((ANCHO - usados - 1))
    ((faltan < 1)) && faltan=1
    repetir '─' "$faltan"
    printf '┐%b\n' "$RESET"
}

mensaje() {
    local color="$1" icono="$2" texto="$3"
    printf '  %b%s%b %s\n' "$color" "$icono" "$RESET" "$texto"
}

pausa() {
    printf '\n'
    read -r -p "  Presiona ENTER para salir..." _
}

# ── Spinner con estado real del proceso ──────────────────────
ejecutar() {
    local descripcion="$1"
    shift

    local temporal="/tmp/adm-firewalld-$$.log"
    local pid estado
    local simbolos='|/-\'
    local i=0

    printf '\n  %b%s%b %s' "$CELESTE" "◌" "$RESET" "$descripcion"

    "$@" >"$temporal" 2>&1 &
    pid=$!

    while kill -0 "$pid" 2>/dev/null; do
        printf '\r  %b[%c]%b %s...' \
            "$CELESTE" "${simbolos:i++%4:1}" "$RESET" "$descripcion"
        sleep 0.15
    done

    wait "$pid"
    estado=$?

    if ((estado == 0)); then
        printf '\r  %b✔%b %s%*s\n' \
            "$VERDE" "$RESET" "$descripcion" 8 ""
    else
        printf '\r  %b✘%b %s (código %s)\n' \
            "$ROJO" "$RESET" "$descripcion" "$estado"

        if [[ -s "$temporal" ]]; then
            printf '\n%b' "${GRIS}"
            tail -n 8 "$temporal"
            printf '%b\n' "$RESET"
        fi
    fi

    rm -f -- "$temporal"
    return "$estado"
}

# ── Comprobar root ───────────────────────────────────────────
if ((EUID != 0)); then
    printf '\n%b\n' "${ROJO}${NEGRITA}ERROR: debes ejecutar este script como root.${RESET}"
    printf 'Ejemplo: sudo bash %s\n\n' "${0##*/}"
    exit 1
fi

# ── Inicio ───────────────────────────────────────────────────
clear 2>/dev/null || true
titulo

# ── Advertencia previa ──────────────────────────────────────
separador "ANTES DE CONTINUAR"

mensaje "$AMARILLO" "!" "Esta operación abrirá TODOS los puertos:"
mensaje "$BLANCO" "›" "TCP: 1-65535"
mensaje "$BLANCO" "›" "UDP: 1-65535"
mensaje "$BLANCO" "›" "Zona: public"
mensaje "$GRIS" "i" "La regla quedará guardada permanentemente."

printf '\n'
printf '%b\n' "${ROJO}${NEGRITA}  ADVERTENCIA DE SEGURIDAD${RESET}"
printf '  Abrir todos los puertos aumenta la exposición del VPS.\n'
printf '  Firewalld no sustituye las reglas del proveedor ni los\n'
printf '  controles de acceso de los servicios que escuchan.\n'
printf '\n'
printf '  Asegúrate de tener acceso a la consola del proveedor\n'
printf '  antes de cambiar el estado del firewall.\n\n'

read -r -p "  ¿Deseas continuar? [s/N]: " confirmar
case "$confirmar" in
    s|S|si|SI|Si|sí|Sí) ;;
    *)
        mensaje "$AMARILLO" "!" "Operación cancelada. No se realizaron cambios."
        exit 0
        ;;
esac

# ── Verificar sistema ────────────────────────────────────────
separador "VERIFICACIÓN DEL SISTEMA"

if ! command -v apt-get >/dev/null 2>&1; then
    mensaje "$ROJO" "✘" "Este instalador requiere apt-get (Ubuntu/Debian)."
    exit 1
fi

# ── Actualizar paquetes ─────────────────────────────────────
if ! ejecutar "Actualizando lista de paquetes" apt-get update; then
    mensaje "$ROJO" "✘" "No se pudo actualizar la lista de paquetes."
    exit 1
fi

# ── Instalar Firewalld si es necesario ───────────────────────
separador "INSTALACIÓN DE FIREWALLD"

if ! command -v firewall-cmd >/dev/null 2>&1; then
    mensaje "$AMARILLO" "!" "Firewalld no está instalado."

    if ! ejecutar "Instalando Firewalld" apt-get install -y firewalld; then
        mensaje "$ROJO" "✘" "Falló la instalación de Firewalld."
        exit 1
    fi
else
    mensaje "$VERDE" "✔" "Firewalld ya está instalado."
fi

# ── Habilitar e iniciar servicio ─────────────────────────────
separador "ACTIVACIÓN DEL SERVICIO"

if ! ejecutar "Habilitando Firewalld al iniciar" systemctl enable firewalld; then
    mensaje "$ROJO" "✘" "No se pudo habilitar el servicio."
    exit 1
fi

if ! ejecutar "Iniciando Firewalld" systemctl start firewalld; then
    mensaje "$ROJO" "✘" "No se pudo iniciar Firewalld."
    systemctl status firewalld --no-pager -l 2>/dev/null || true
    exit 1
fi

if ! firewall-cmd --state >/dev/null 2>&1; then
    mensaje "$ROJO" "✘" "Firewalld no está respondiendo."
    exit 1
fi

mensaje "$VERDE" "✔" "El servicio está activo."

# ── Configurar reglas permanentes ────────────────────────────
separador "CONFIGURACIÓN DE PUERTOS"

for protocolo in tcp udp; do
    regla="1-65535/$protocolo"

    if firewall-cmd --permanent --zone=public --query-port="$regla" \
        >/dev/null 2>&1; then
        mensaje "$AMARILLO" "•" "Regla $protocolo ya configurada."
    else
        if ! ejecutar "Configurando puertos $protocolo" \
            firewall-cmd --permanent --zone=public --add-port="$regla"; then
            mensaje "$ROJO" "✘" "No se pudo configurar $regla."
            mensaje "$AMARILLO" "!" "Revisa el estado del firewall antes de continuar."
            exit 1
        fi
    fi
done

# ── Aplicar reglas ───────────────────────────────────────────
separador "APLICANDO CONFIGURACIÓN"

if ! ejecutar "Recargando las reglas de Firewalld" firewall-cmd --reload; then
    mensaje "$ROJO" "✘" "No se pudo recargar la configuración."
    exit 1
fi

# ── Verificación final ───────────────────────────────────────
separador "VERIFICACIÓN FINAL"

fallos=0

for protocolo in tcp udp; do
    regla="1-65535/$protocolo"

    if firewall-cmd --permanent --zone=public --query-port="$regla" \
        >/dev/null 2>&1 &&
       firewall-cmd --zone=public --query-port="$regla" \
        >/dev/null 2>&1; then
        mensaje "$VERDE" "✔" "Regla $regla activa y permanente."
    else
        mensaje "$ROJO" "✘" "No se pudo verificar $regla."
        ((fallos++))
    fi
done

if ((fallos > 0)); then
    mensaje "$ROJO" "✘" "La configuración no pudo verificarse por completo."
    exit 1
fi

if systemctl is-active --quiet firewalld; then
    mensaje "$VERDE" "✔" "Servicio: activo."
else
    mensaje "$ROJO" "✘" "Servicio: inactivo."
    exit 1
fi

# ── Resumen ──────────────────────────────────────────────────
separador "RESUMEN DE CONFIGURACIÓN"

printf '\n'
printf '  %bZona:%b                 public\n' "$BLANCO" "$RESET"
printf '  %bPuertos TCP:%b          1-65535\n' "$BLANCO" "$RESET"
printf '  %bPuertos UDP:%b          1-65535\n' "$BLANCO" "$RESET"
printf '  %bPersistencia:%b         habilitada\n' "$BLANCO" "$RESET"
printf '  %bServicio:%b             activo\n' "$BLANCO" "$RESET"

printf '\n%b' "${VERDE}${NEGRITA}"
repetir '═' "$ANCHO"
printf '\n'
centrar "CONFIGURACIÓN COMPLETADA"
printf '%b' "${VERDE}${NEGRITA}"
repetir '═' "$ANCHO"
printf '%b\n' "$RESET"

printf '\n'
mensaje "$AMARILLO" "!" "Las reglas del proveedor VPS pueden seguir bloqueando tráfico."
mensaje "$AMARILLO" "!" "Los servicios deben estar escuchando en sus puertos."
printf '\n'

pausa
