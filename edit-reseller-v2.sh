#!/bin/bash
# ============================================================
# ADMRufu 2.0 | Gestor de nombre de Reseller
# Autor: ChristopherAGT
# Archivo: /etc/reseller
# ============================================================

# ── Colores ─────────────────────────────────────────────────
verde=$'\033[92m'
rojo=$'\033[91m'
azul=$'\033[94m'
celeste=$'\033[96m'
amarillo=$'\033[93m'
blanco=$'\033[97m'
gris=$'\033[90m'
negrita=$'\033[1m'
reset=$'\033[0m'

# ── Configuración ────────────────────────────────────────────
ARCHIVO=""
INSTALACION=""
ANCHO=48
INTERIOR=$((ANCHO - 2))
ANCHO_PANEL=48
INTERIOR_PANEL=$((ANCHO_PANEL - 2))

# ── Medir columnas visuales ──────────────────────────────────
ancho_visual() {
    local texto="$1"
    local medida

    medida=$(printf '%s' "$texto" | wc -L 2>/dev/null)
    medida=${medida//[!0-9]/}
    printf '%s' "${medida:-0}"
}

# ── Funciones de dibujo ──────────────────────────────────────
repetir() {
    local caracter="$1"
    local cantidad="$2"
    local i

    for ((i = 0; i < cantidad; i++)); do
        printf '%s' "$caracter"
    done
}

borde_superior() {
    printf '%s' "${azul}${negrita}╔"
    repetir '═' "$INTERIOR"
    printf '╗%s\n' "$reset"
}

separador() {
    printf '%s' "${azul}${negrita}╠"
    repetir '═' "$INTERIOR"
    printf '╣%s\n' "$reset"
}

borde_inferior() {
    printf '%s' "${azul}${negrita}╚"
    repetir '═' "$INTERIOR"
    printf '╝%s\n' "$reset"
}

# Fila del marco principal.
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

    printf '%s %s%*s %s\n' \
        "${azul}${negrita}║${reset}" \
        "$texto" "$espacios" "" \
        "${azul}${negrita}║${reset}"
}

centrar() {
    local texto="$1"
    local visible izquierda derecha

    visible=$(ancho_visual "$texto")

    if ((visible > INTERIOR)); then
        texto="${texto:0:INTERIOR}"
        visible=$(ancho_visual "$texto")
    fi

    izquierda=$(( (INTERIOR - visible) / 2 ))
    derecha=$(( INTERIOR - visible - izquierda ))

    ((izquierda < 0)) && izquierda=0
    ((derecha < 0)) && derecha=0

    printf '%s%*s%s%*s%s\n' \
        "${azul}${negrita}║${reset}" \
        "$izquierda" "" "$texto" \
        "$derecha" "" \
        "${azul}${negrita}║${reset}"
}

# ── Paneles secundarios ──────────────────────────────────────
abrir_panel() {
    local titulo="$1"
    local visible guiones

    visible=$(ancho_visual "$titulo")
    guiones=$((ANCHO_PANEL - visible - 5))
    ((guiones < 1)) && guiones=1

    printf '%s' "${celeste}${negrita}┌─ ${titulo} "
    repetir '─' "$guiones"
    printf '┐%s\n' "$reset"
}

panel_fila() {
    local texto="$1"
    local ancho=$((ANCHO_PANEL - 4))
    local visible espacios

    visible=$(ancho_visual "$texto")

    # Recortar contenido que no cabe en el panel.
    if ((visible > ancho)); then
        texto="${texto:0:$((ancho - 3))}..."
        visible=$(ancho_visual "$texto")
    fi

    espacios=$((ancho - visible))
    ((espacios < 0)) && espacios=0

    printf '%s %s%*s %s\n' \
        "${celeste}│${reset}" \
        "$texto" "$espacios" "" \
        "${celeste}│${reset}"
}

cerrar_panel() {
    printf '%s' "${celeste}└"
    repetir '─' "$INTERIOR_PANEL"
    printf '┘%s\n' "$reset"
}

pausa() {
    echo
    read -r -p "Presiona ENTER para salir..." _
}

# ── Detectar instalación y archivo de reseller ───────────────
detectar_instalacion() {
    if [[ -d "/etc/VPS-MX" ]]; then
        ARCHIVO="/etc/VPS-MX/message.txt"
        INSTALACION="LA CASITA MX"
    elif [[ -d "/etc/ADMRufu" || -f "/etc/reseller" ]]; then
        ARCHIVO="/etc/reseller"
        INSTALACION="ADMRUFU 2.0"
    else
        ARCHIVO=""
        INSTALACION=""
        return 1
    fi

    return 0
}

# ── Inicio ───────────────────────────────────────────────────
clear 2>/dev/null || true
printf '\n'

# ── Verificar permisos ───────────────────────────────────────
if ((EUID != 0)); then
    printf '%b\n' "${rojo}${negrita}ERROR:${reset} Ejecuta el script como root."
    printf '%b\n' "${gris}Ejemplo: bash edit-reseller.sh${reset}"
    exit 1
fi

# ── Identificar instalación ──────────────────────────────────
if ! detectar_instalacion; then
    printf '%b\n' "${rojo}${negrita}ERROR:${reset} No se detectó una instalación compatible."
    printf '%b\n' "${gris}Instalaciones compatibles: ADMRufu 2.0 y La Casita MX.${reset}"
    pausa
    exit 1
fi

# ── Encabezado dinámico ──────────────────────────────────────
borde_superior
centrar "$INSTALACION"
separador
centrar "GESTOR DE RESELLER"
centrar "Personalizacion del nombre"
borde_inferior

printf '\n'

# ── Leer reseller actual ─────────────────────────────────────
if [[ -f "$ARCHIVO" ]]; then
    if ! actual=$(cat -- "$ARCHIVO"); then
        printf '%b\n' "${rojo}No se pudo leer $ARCHIVO${reset}"
        pausa
        exit 1
    fi

    [[ -z "$actual" ]] && actual="(Archivo vacio)"
else
    actual="(No configurado)"
fi

# ── Panel de información actual ──────────────────────────────
abrir_panel "INFORMACION ACTUAL"
panel_fila ""
panel_fila "👤 Reseller: $actual"
panel_fila ""
cerrar_panel

printf '\n'

# ── Solicitar nuevo nombre ───────────────────────────────────
printf '%b\n' "${azul}${negrita}✎ CONFIGURAR NUEVO NOMBRE${reset}"
printf '%b\n' "${gris}Escribe el nombre que deseas mostrar en $INSTALACION.${reset}"
printf '\n'

printf '%b' "${amarillo}➜ Nombre del Reseller: ${reset}"
IFS= read -r nuevo

# ── Validar entrada ──────────────────────────────────────────
if [[ -z "$nuevo" ]]; then
    printf '\n%b\n' "${rojo}${negrita}ERROR:${reset} No ingresaste un nombre."
    pausa
    exit 1
fi

if [[ "$nuevo" =~ [[:cntrl:]] ]]; then
    printf '\n%b\n' "${rojo}${negrita}ERROR:${reset} El nombre contiene caracteres de control."
    pausa
    exit 1
fi

# ── Preparar nombre final ────────────────────────────────────
final="⚡️${nuevo}⚡️"

# ── Vista previa ─────────────────────────────────────────────
printf '\n'
borde_superior
centrar "VISTA PREVIA"
separador
fila ""
fila "Sistema: $INSTALACION"
fila "Nombre del Reseller: $final"
fila ""
borde_inferior

printf '\n'

# ── Confirmación ─────────────────────────────────────────────
printf '%b' "${amarillo}¿Deseas guardar este nombre? [S/n]: ${reset}"
IFS= read -r confirmar

case "$confirmar" in
    n|N|no|NO|No)
        printf '\n%b\n' "${amarillo}Operacion cancelada. No se realizaron cambios.${reset}"
        pausa
        exit 0
        ;;
esac

# ── Guardar nombre ───────────────────────────────────────────
if ! printf '%s\n' "$final" > "$ARCHIVO"; then
    printf '\n%b\n' "${rojo}${negrita}ERROR:${reset} No se pudo guardar el nombre."
    printf '%b\n' "${gris}Archivo: $ARCHIVO${reset}"
    pausa
    exit 1
fi

# ── Verificar escritura ──────────────────────────────────────
if ! guardado=$(cat -- "$ARCHIVO"); then
    printf '\n%b\n' "${rojo}No se pudo verificar el archivo.${reset}"
    pausa
    exit 1
fi

if [[ "$guardado" != "$final" ]]; then
    printf '\n%b\n' "${rojo}${negrita}ERROR:${reset} El contenido guardado no coincide."
    pausa
    exit 1
fi

# ── Resultado final ──────────────────────────────────────────
printf '\n'
borde_superior
centrar "CAMBIO COMPLETADO"
separador
fila ""
fila "Reseller actualizado correctamente."
fila "Sistema: $INSTALACION"
fila ""
borde_inferior

printf '\n'
printf '%b\n' "  ${verde}${negrita}✔ Nuevo nombre:${reset}"
printf '\n'
printf '  %b\n' "${amarillo}${negrita}${final}${reset}"
printf '\n'
printf '  %b\n' "${verde}✔ Guardado en:${reset} ${blanco}${ARCHIVO}${reset}"
printf '\n'
printf '%b\n' "${gris}${INSTALACION} | Gestor de Reseller${reset}"

pausa
