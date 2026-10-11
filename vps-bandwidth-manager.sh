#!/bin/bash
# ============================================================
# ADMRufu 2.0 | Gestor de Ancho de Banda
# Autor: ChristopherAGT
# Descripcion: Administrar limites de velocidad con tc
# ============================================================

# ── Colores ─────────────────────────────────────────────────
verde=$'\033[1;32m'
rojo=$'\033[1;31m'
amarillo=$'\033[1;33m'
cyan=$'\033[1;36m'
azul=$'\033[1;34m'
blanco=$'\033[1;37m'
gris=$'\033[0;90m'
negrita=$'\033[1m'
neutro=$'\033[0m'

# ── Configuracion ────────────────────────────────────────────
CONFIG="/etc/limitador-banda.conf"
STATUS="/etc/limitador-banda.status.json"
SCRIPT_APLICADOR="/usr/local/bin/limitar-banda.sh"
LOG="/var/log/limitador-banda.log"

ANCHO=48
INTERIOR=$((ANCHO - 2))

# ── Funciones visuales ──────────────────────────────────────
repetir() {
    local caracter="$1"
    local cantidad="$2"
    local i

    for ((i = 0; i < cantidad; i++)); do
        printf '%s' "$caracter"
    done
}

ancho_visual() {
    local texto="$1"
    local medida

    # Retirar colores ANSI antes de medir.
    texto=$(printf '%s' "$texto" |
        sed -E 's/\x1B\[[0-9;]*[[:alpha:]]//g')

    # wc -L calcula el ancho de la linea segun la configuracion
    # regional disponible en el sistema.
    medida=$(printf '%s' "$texto" | wc -L 2>/dev/null)
    medida=${medida//[!0-9]/}

    printf '%s' "${medida:-0}"
}

borde_superior() {
    printf '%b' "${azul}${negrita}╔"
    repetir '═' "$INTERIOR"
    printf '╗%b\n' "$neutro"
}

separador() {
    printf '%b' "${azul}${negrita}╠"
    repetir '═' "$INTERIOR"
    printf '╣%b\n' "$neutro"
}

borde_inferior() {
    printf '%b' "${azul}${negrita}╚"
    repetir '═' "$INTERIOR"
    printf '╝%b\n' "$neutro"
}

fila() {
    local texto="$1"
    local max=$((INTERIOR - 2))
    local visible espacios

    visible=$(ancho_visual "$texto")

    if ((visible > max)); then
        texto="${texto:0:$((max - 3))}..."
        visible=$(ancho_visual "$texto")
    fi

    espacios=$((max - visible))
    ((espacios < 0)) && espacios=0

    printf '%b %s%*s %b\n' \
        "${azul}${negrita}║${neutro}" \
        "$texto" "$espacios" "" \
        "${azul}${negrita}║${neutro}"
}

centrar() {
    local texto="$1"
    local visible izquierda derecha

    visible=$(ancho_visual "$texto")

    if ((visible > INTERIOR)); then
        texto="${texto:0:INTERIOR}"
        visible=$(ancho_visual "$texto")
    fi

    izquierda=$(((INTERIOR - visible) / 2))
    derecha=$((INTERIOR - visible - izquierda))

    ((izquierda < 0)) && izquierda=0
    ((derecha < 0)) && derecha=0

    printf '%b%*s%s%*s%b\n' \
        "${azul}${negrita}║${neutro}" \
        "$izquierda" "" "$texto" \
        "$derecha" "" \
        "${azul}${negrita}║${neutro}"
}

panel_abrir() {
    local titulo="$1"
    local visible guiones

    visible=$(ancho_visual "$titulo")

    # Ancho total: esquina + prefijo + titulo + espacio +
    # guiones + esquina final.
    guiones=$((ANCHO - visible - 5))

    ((guiones < 1)) && guiones=1

    printf '%b' "${cyan}${negrita}┌─ ${titulo} "
    repetir '─' "$guiones"
    printf '┐%b\n' "$neutro"
}

panel_fila() {
    local texto="$1"
    local max=$((ANCHO - 4))
    local visible espacios

    visible=$(ancho_visual "$texto")

    if ((visible > max)); then
        texto="${texto:0:$((max - 3))}..."
        visible=$(ancho_visual "$texto")
    fi

    espacios=$((max - visible))
    ((espacios < 0)) && espacios=0

    printf '%b %s%*s %b\n' \
        "${cyan}│${neutro}" \
        "$texto" "$espacios" "" \
        "${cyan}│${neutro}"
}

# Fila de estado: solo colorea el estado.
# Se mantienen etiquetas sin emojis dentro del marco para
# evitar diferencias de ancho entre terminales.
panel_fila_estado() {
    local etiqueta="$1"
    local estado="$2"
    local color="$3"
    local max=$((ANCHO - 4))
    local texto visible espacios

    texto="${etiqueta}${estado}"
    visible=$(ancho_visual "$texto")

    if ((visible > max)); then
        estado="${estado:0:$((max - ${#etiqueta} - 3))}..."
        texto="${etiqueta}${estado}"
        visible=$(ancho_visual "$texto")
    fi

    espacios=$((max - visible))
    ((espacios < 0)) && espacios=0

    printf '%b %s%b%s%b%*s %b\n' \
        "${cyan}│${neutro}" \
        "$etiqueta" \
        "$color" "$estado" "${neutro}" \
        "$espacios" "" \
        "${cyan}│${neutro}"
}

panel_cerrar() {
    printf '%b' "${cyan}└"
    repetir '─' "$INTERIOR"
    printf '┘%b\n' "$neutro"
}

titulo_seccion() {
    printf '\n%b\n' "${cyan}${negrita}$1${neutro}"
}

mensaje_error() {
    printf '\n%b\n' "${rojo}${negrita}✘ ERROR:${neutro} $1"
}

mensaje_ok() {
    printf '\n%b\n' "${verde}✔ $1${neutro}"
}

pausa() {
    echo
    read -r -p "Presiona ENTER para continuar..." _
}

banner() {
    clear 2>/dev/null || true
    printf '\n'

    borde_superior
    centrar "Bandwidth Manager"
    separador
    centrar "GESTOR DE ANCHO DE BANDA"
    centrar "Control de velocidad de red"
    borde_inferior

    printf '\n'
}

# ── Validar permisos ────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    printf '%b\n' "${rojo}${negrita}✘ ERROR:${neutro} Ejecuta este script como root."
    printf '%b\n' "${gris}Ejemplo: sudo bash /ruta/al/script.sh${neutro}"
    exit 1
fi

# ── Instalar dependencias ───────────────────────────────────
instalar_dependencias() {
    local faltantes=()
    local paquetes=()
    local p

    titulo_seccion "🔍 VERIFICACION DE DEPENDENCIAS"
    printf '%b\n' "${gris}Comprobando herramientas necesarias...${neutro}"

    for p in jq tc ip; do
        if ! command -v "$p" >/dev/null 2>&1; then
            faltantes+=("$p")
        fi
    done

    if ((${#faltantes[@]} == 0)); then
        mensaje_ok "jq, tc e ip ya estan disponibles."
        return 0
    fi

    for p in "${faltantes[@]}"; do
        case "$p" in
            tc|ip)
                [[ " ${paquetes[*]} " == *" iproute2 "* ]] ||
                    paquetes+=("iproute2")
                ;;
            jq)
                paquetes+=("jq")
                ;;
        esac
    done

    printf '%b\n' "${amarillo}Instalando: ${paquetes[*]}${neutro}"

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update || return 1
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${paquetes[@]}" || return 1
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y "${paquetes[@]}" || return 1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y "${paquetes[@]}" || return 1
    elif command -v apk >/dev/null 2>&1; then
        apk add "${paquetes[@]}" || return 1
    else
        mensaje_error "No se encontro un gestor de paquetes compatible."
        return 1
    fi

    for p in jq tc ip; do
        if ! command -v "$p" >/dev/null 2>&1; then
            mensaje_error "La herramienta '$p' sigue sin estar disponible."
            return 1
        fi
    done

    mensaje_ok "Dependencias instaladas correctamente."
}

# ── Detectar interfaz de red ────────────────────────────────
detectar_interfaz() {
    INTERFAZ=$(ip route show default 2>/dev/null |
        awk '/default/ {print $5; exit}')

    if [[ -z "$INTERFAZ" ]]; then
        mensaje_error "No se pudo detectar la interfaz de red activa."
        return 1
    fi

    printf '\n%b\n' "${verde}✔ Interfaz detectada: ${blanco}${INTERFAZ}${neutro}"
}

# ── Solicitar limite de Mbps ────────────────────────────────
solicitar_limite() {
    local entrada

    while true; do
        printf '\n%b' "${amarillo}➜ ¿Cuantos Mbps deseas permitir?: ${neutro}"
        read -r entrada || return 1

        if [[ "$entrada" =~ ^[0-9]+$ ]] &&
            ((10#$entrada > 0)); then
            LIMITE=$((10#$entrada))
            return 0
        fi

        mensaje_error "Ingresa un numero entero positivo."
    done
}

# ── Aplicar limite con tc ───────────────────────────────────
aplicar_limite() {
    if [[ -z "${INTERFAZ:-}" ]] ||
        ! ip link show "$INTERFAZ" >/dev/null 2>&1; then
        mensaje_error "La interfaz de red no es valida."
        return 1
    fi

    if [[ ! "${LIMITE:-}" =~ ^[0-9]+$ ]] ||
        ((LIMITE <= 0)); then
        mensaje_error "El limite debe ser un entero positivo."
        return 1
    fi

    # Esta operacion reemplaza la qdisc root existente.
    tc qdisc del dev "$INTERFAZ" root 2>/dev/null || true

    if ! tc qdisc add dev "$INTERFAZ" root handle 1: htb default 30 r2q 5; then
        mensaje_error "No se pudo crear la disciplina HTB en $INTERFAZ."
        return 1
    fi

    if ! tc class add dev "$INTERFAZ" parent 1: \
        classid 1:1 htb rate "${LIMITE}mbit" ceil "${LIMITE}mbit"; then
        tc qdisc del dev "$INTERFAZ" root 2>/dev/null || true
        mensaje_error "No se pudo crear la clase principal."
        return 1
    fi

    if ! tc class add dev "$INTERFAZ" parent 1:1 \
        classid 1:30 htb rate "${LIMITE}mbit" ceil "${LIMITE}mbit"; then
        tc qdisc del dev "$INTERFAZ" root 2>/dev/null || true
        mensaje_error "No se pudo crear la clase de limitacion."
        return 1
    fi

    return 0
}

# ── Guardar configuracion ───────────────────────────────────
guardar_config() {
    if ! printf 'INTERFAZ=%q\nLIMITE=%q\n' \
        "$INTERFAZ" "$LIMITE" > "$CONFIG"; then
        mensaje_error "No se pudo guardar la configuracion."
        return 1
    fi

    if ! printf '{"interfaz":"%s","limite_mbps":%s,"aplicado":true,"ultima_aplicacion":"%s"}\n' \
        "$INTERFAZ" "$LIMITE" \
        "$(date -u +"%Y-%m-%d %H:%M:%S UTC")" > "$STATUS"; then
        mensaje_error "No se pudo guardar el estado."
        return 1
    fi

    printf '%s - Aplicado %s Mbps en %s\n' \
        "$(date)" "$LIMITE" "$INTERFAZ" >> "$LOG"

    return 0
}

# ── Crear aplicador permanente ──────────────────────────────
crear_script_aplicador() {
    if ! cat <<EOF > "$SCRIPT_APLICADOR"
#!/bin/bash
set -u

CONFIG="/etc/limitador-banda.conf"

if [[ ! -r "\$CONFIG" ]]; then
    exit 1
fi

source "\$CONFIG"

if [[ -z "\${INTERFAZ:-}" ]] || [[ ! "\${LIMITE:-}" =~ ^[0-9]+$ ]] || ((LIMITE <= 0)); then
    exit 1
fi

ip link show "\$INTERFAZ" >/dev/null 2>&1 || exit 1

tc qdisc del dev "\$INTERFAZ" root 2>/dev/null || true
tc qdisc add dev "\$INTERFAZ" root handle 1: htb default 30 r2q 5 || exit 1
tc class add dev "\$INTERFAZ" parent 1: classid 1:1 htb rate "\${LIMITE}mbit" ceil "\${LIMITE}mbit" || exit 1
tc class add dev "\$INTERFAZ" parent 1:1 classid 1:30 htb rate "\${LIMITE}mbit" ceil "\${LIMITE}mbit" || exit 1
EOF
    then
        mensaje_error "No se pudo crear el aplicador permanente."
        return 1
    fi

    chmod 700 "$SCRIPT_APLICADOR"
}

# ── Agregar aplicador al crontab ────────────────────────────
agregar_crontab() {
    local temporal

    temporal=$(mktemp) || return 1

    crontab -l 2>/dev/null |
        grep -Fv -- "$SCRIPT_APLICADOR" > "$temporal" || true

    printf '@reboot %s\n' "$SCRIPT_APLICADOR" >> "$temporal"

    if ! crontab "$temporal"; then
        rm -f "$temporal"
        mensaje_error "No se pudo actualizar el crontab de root."
        return 1
    fi

    rm -f "$temporal"
    return 0
}

# ── Eliminar limitacion ─────────────────────────────────────
eliminar_limite() {
    local interfaz_guardada=""

    if [[ -f "$CONFIG" ]]; then
        interfaz_guardada=$(sed -n 's/^INTERFAZ=//p' "$CONFIG" | head -n1)
        interfaz_guardada=${interfaz_guardada#\"}
        interfaz_guardada=${interfaz_guardada%\"}
    fi

    if [[ -n "$interfaz_guardada" ]]; then
        tc qdisc del dev "$interfaz_guardada" root 2>/dev/null || true
    fi

    rm -f "$CONFIG" "$STATUS" "$SCRIPT_APLICADOR"

    local temporal
    temporal=$(mktemp) || {
        mensaje_error "No se pudo preparar la limpieza del crontab."
        return 1
    }

    crontab -l 2>/dev/null |
        grep -Fv -- "$SCRIPT_APLICADOR" > "$temporal" || true

    if ! crontab "$temporal"; then
        rm -f "$temporal"
        mensaje_error "No se pudo limpiar la tarea de cron."
        return 1
    fi

    rm -f "$temporal"
    mensaje_ok "Limitacion y aplicacion automatica eliminadas."
}

# ── Aplicar limite temporal ─────────────────────────────────
aplicar_temporal() {
    local MIN entrada

    while true; do
        printf '\n%b' "${amarillo}⏳ ¿Cuantos minutos deseas aplicar el limite?: ${neutro}"
        read -r entrada || return 1

        if [[ "$entrada" =~ ^[0-9]+$ ]] &&
            ((10#$entrada > 0)); then
            MIN=$((10#$entrada))
            break
        fi

        mensaje_error "Ingresa un numero entero positivo."
    done

    solicitar_limite || return 1

    if ! aplicar_limite; then
        return 1
    fi

    printf '%s - Aplicado temporalmente %s Mbps por %s minutos en %s\n' \
        "$(date)" "$LIMITE" "$MIN" "$INTERFAZ" >> "$LOG"

    mensaje_ok "Limite aplicado por $MIN minutos."
    printf '%b\n' "${gris}No cierres el proceso durante la espera.${neutro}"

    sleep "$((MIN * 60))"

    tc qdisc del dev "$INTERFAZ" root 2>/dev/null || true

    printf '%s - Limite temporal eliminado\n' "$(date)" >> "$LOG"
    mensaje_ok "Limite temporal finalizado."
}

# ── Prueba de red con resumen visual ────────────────────────
prueba_red() {
    local salida codigo
    local enviados recibidos perdidos
    local latencia_min latencia_avg latencia_max latencia_mdev
    local host="google.com"

    titulo_seccion "📡 PRUEBA DE CONECTIVIDAD"
    printf '%b\n' "${gris}Destino: ${blanco}${host}${neutro}"
    printf '%b\n' "${gris}Enviando 4 paquetes ICMP...${neutro}"

    if ! command -v ping >/dev/null 2>&1; then
        mensaje_error "El comando ping no esta instalado."
        printf '%b\n' "${gris}Instala iputils-ping o el paquete equivalente de tu sistema.${neutro}"
        return 1
    fi

    salida=$(ping -c 4 -W 3 "$host" 2>&1)
    codigo=$?

    enviados=$(printf '%s\n' "$salida" |
        sed -nE 's/.* ([0-9]+) packets transmitted.*/\1/p')
    recibidos=$(printf '%s\n' "$salida" |
        sed -nE 's/.* ([0-9]+) received.*/\1/p')
    perdidos=$(printf '%s\n' "$salida" |
        sed -nE 's/.* ([0-9]+)% packet loss.*/\1/p')

    latencia_min=$(printf '%s\n' "$salida" |
        sed -nE 's/.* = ([0-9.]+)\/([0-9.]+)\/([0-9.]+)\/([0-9.]+) ms/\1/p')
    latencia_avg=$(printf '%s\n' "$salida" |
        sed -nE 's/.* = ([0-9.]+)\/([0-9.]+)\/([0-9.]+)\/([0-9.]+) ms/\2/p')
    latencia_max=$(printf '%s\n' "$salida" |
        sed -nE 's/.* = ([0-9.]+)\/([0-9.]+)\/([0-9.]+)\/([0-9.]+) ms/\3/p')
    latencia_mdev=$(printf '%s\n' "$salida" |
        sed -nE 's/.* = ([0-9.]+)\/([0-9.]+)\/([0-9.]+)\/([0-9.]+) ms/\4/p')

    enviados=${enviados:-0}
    recibidos=${recibidos:-0}
    perdidos=${perdidos:-100}

    printf '\n'
    panel_abrir "RESUMEN DE CONECTIVIDAD"

    if ((recibidos > 0)); then
        panel_fila "Estado: Conexion disponible"
    else
        panel_fila "Estado: Sin respuesta"
    fi

    panel_fila "Destino: $host"
    panel_fila "Paquetes enviados: $enviados"
    panel_fila "Paquetes recibidos: $recibidos"
    panel_fila "Perdida de paquetes: ${perdidos}%"

    if [[ -n "$latencia_avg" ]]; then
        panel_fila "Latencia promedio: ${latencia_avg} ms"
        panel_fila "Latencia minima: ${latencia_min} ms"
        panel_fila "Latencia maxima: ${latencia_max} ms"
        panel_fila "Variacion (mdev): ${latencia_mdev} ms"
    else
        panel_fila "Latencia: No disponible"
    fi

    panel_cerrar
    printf '\n'

    if ((recibidos == 0)); then
        printf '%b\n' "${rojo}✘ No se recibieron respuestas. Revisa la conectividad o el filtrado ICMP.${neutro}"
    elif ((perdidos > 0)); then
        printf '%b\n' "${amarillo}⚠ Hay perdida de paquetes. Conviene repetir la prueba.${neutro}"
    else
        printf '%b\n' "${verde}✔ Conexion estable durante esta prueba.${neutro}"
    fi

    if ((codigo != 0)); then
        printf '%b\n' "${gris}Nota: ping termino con codigo $codigo.${neutro}"
    fi
}

# ── Ver estado actual ───────────────────────────────────────
ver_estado() {
    titulo_seccion "📊 ESTADO ACTUAL"

    if [[ -f "$STATUS" ]]; then
        if command -v jq >/dev/null 2>&1; then
            jq . "$STATUS"
        else
            cat "$STATUS"
        fi
    else
        printf '%b\n' "${rojo}Estado: No Configurado${neutro}"
    fi

    if [[ -f "$CONFIG" ]]; then
        printf '\n%b\n' "${cyan}Configuracion guardada:${neutro}"
        cat "$CONFIG"

        INTERFAZ=$(sed -n 's/^INTERFAZ=//p' "$CONFIG" | head -n1)
        INTERFAZ=${INTERFAZ#\"}
        INTERFAZ=${INTERFAZ%\"}

        if [[ -n "$INTERFAZ" ]] &&
            ip link show "$INTERFAZ" >/dev/null 2>&1; then
            printf '\n%b\n' "${cyan}Disciplinas de trafico actuales:${neutro}"
            tc -s qdisc show dev "$INTERFAZ" 2>/dev/null
            tc -s class show dev "$INTERFAZ" 2>/dev/null
        fi
    fi
}

# ── Ver registro de actividad ───────────────────────────────
ver_log() {
    titulo_seccion "📜 REGISTRO DE ACTIVIDAD"

    if [[ -f "$LOG" ]]; then
        cat "$LOG"
    else
        printf '%b\n' "${amarillo}📂 Todavia no hay registros.${neutro}"
    fi
}

# ── Mostrar menu principal ──────────────────────────────────
menu() {
    local OPCION
    local interfaz_actual limite_actual

    while true; do
        banner

        panel_abrir "INFORMACION DEL SISTEMA"

        if [[ -f "$CONFIG" ]]; then
            interfaz_actual=$(sed -n 's/^INTERFAZ=//p' "$CONFIG" | head -n1)
            limite_actual=$(sed -n 's/^LIMITE=//p' "$CONFIG" | head -n1)

            interfaz_actual=${interfaz_actual#\"}
            interfaz_actual=${interfaz_actual%\"}
            limite_actual=${limite_actual#\"}
            limite_actual=${limite_actual%\"}

            if [[ "$limite_actual" =~ ^[0-9]+$ ]] &&
                ((10#$limite_actual > 0)) &&
                [[ -n "$interfaz_actual" ]] &&
                ip link show "$interfaz_actual" >/dev/null 2>&1; then

                panel_fila_estado "Estado: " "Configurado" "$verde"
                panel_fila "Interfaz: ${interfaz_actual}"
                panel_fila "Limite: ${limite_actual} Mbps"
            else
                panel_fila_estado "Estado: " "No Configurado" "$rojo"
                panel_fila "Interfaz: No disponible"
                panel_fila "Limite: No establecido"
            fi
        else
            panel_fila_estado "Estado: " "No Configurado" "$rojo"
            panel_fila "Interfaz: Pendiente"
            panel_fila "Limite: No establecido"
        fi

        panel_cerrar

        printf '\n'
        printf '%b\n' "${cyan}${negrita}╭─ MENU PRINCIPAL${neutro}"
        printf '%b\n' "${gris}Selecciona una operacion para continuar.${neutro}"
        printf '\n'

        printf '  %b  %s\n' "${amarillo}1)${neutro}" "🚀 Establecer limite de banda"
        printf '  %b  %s\n' "${amarillo}2)${neutro}" "📊 Ver configuracion actual"
        printf '  %b  %s\n' "${amarillo}3)${neutro}" "⚙️ Cambiar limite actual"
        printf '  %b  %s\n' "${amarillo}4)${neutro}" "⏳ Aplicar limite temporal"
        printf '  %b  %s\n' "${amarillo}5)${neutro}" "🗑️ Eliminar limitacion"
        printf '  %b  %s\n' "${amarillo}6)${neutro}" "📜 Ver registro de actividad"
        printf '  %b  %s\n' "${amarillo}7)${neutro}" "📡 Probar conectividad"
        printf '  %b  %s\n' "${rojo}8)${neutro}" "🔥 Desinstalar configuracion"
        printf '  %b  %s\n' "${amarillo}0)${neutro}" "🚪 Salir"

        printf '\n'
        repetir '─' "$ANCHO"
        printf '\n%b' "${amarillo}➜ Selecciona una opcion: ${neutro}"
        read -r OPCION || exit 0

        case "$OPCION" in
            1)
                if instalar_dependencias &&
                    detectar_interfaz &&
                    solicitar_limite &&
                    aplicar_limite &&
                    guardar_config &&
                    crear_script_aplicador &&
                    agregar_crontab; then
                    mensaje_ok "Limite de ${LIMITE} Mbps aplicado correctamente."
                    mensaje_ok "La configuracion se aplicara automaticamente al reiniciar."
                else
                    mensaje_error "No se pudo completar la operacion."
                fi
                pausa
                ;;

            2)
                ver_estado
                pausa
                ;;

            3)
                if [[ ! -f "$CONFIG" ]]; then
                    mensaje_error "No hay configuracion previa."
                else
                    INTERFAZ=$(sed -n 's/^INTERFAZ=//p' "$CONFIG" | head -n1)
                    INTERFAZ=${INTERFAZ#\"}
                    INTERFAZ=${INTERFAZ%\"}

                    if solicitar_limite &&
                        aplicar_limite &&
                        guardar_config &&
                        crear_script_aplicador &&
                        agregar_crontab; then
                        mensaje_ok "Limite actualizado a ${LIMITE} Mbps."
                    else
                        mensaje_error "No se pudo actualizar el limite."
                    fi
                fi
                pausa
                ;;

            4)
                if detectar_interfaz; then
                    aplicar_temporal
                fi
                pausa
                ;;

            5)
                eliminar_limite
                pausa
                ;;

            6)
                ver_log
                pausa
                ;;

            7)
                prueba_red
                pausa
                ;;

            8)
                printf '\n%b' "${rojo}${negrita}⚠ ADVERTENCIA${neutro}"
                printf '\n%b\n' "${amarillo}Se eliminaran la configuracion del limitador, el aplicador y la tarea automatica de cron.${neutro}"
                printf '%b\n' "${gris}El archivo de este gestor no se eliminara.${neutro}"
                printf '%b' "${amarillo}¿Deseas continuar? [s/N]: ${neutro}"
                read -r CONFIRMAR

                case "$CONFIRMAR" in
                    s|S|si|SI|Si|sí|Sí)
                        eliminar_limite
                        printf '\n%b\n' "${verde}✔ Configuracion del limitador eliminada.${neutro}"
                        printf '%b\n' "${gris}Puedes volver a ejecutar este mismo archivo cuando lo necesites.${neutro}"
                        pausa
                        ;;
                    *)
                        printf '\n%b\n' "${amarillo}Operacion cancelada.${neutro}"
                        pausa
                        ;;
                esac
                ;;

            0)
                printf '\n%b\n' "${verde}✔ Saliendo del gestor.${neutro}"
                exit 0
                ;;

            *)
                mensaje_error "Opcion invalida. Selecciona del 0 al 8."
                pausa
                ;;
        esac
    done
}

# ── Inicio directo: sin instalar comando global ─────────────
if ! instalar_dependencias; then
    mensaje_error "No se pudieron instalar las dependencias."
    exit 1
fi

menu
