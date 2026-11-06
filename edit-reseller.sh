#!/bin/bash
# ============================================================
# ADMRufu 2.0 | Gestor de nombre de Reseller
# Autor: ChristopherAGT
# Compatible: ADMRufu 2.0, La Casita MX y ChumoGH Plus
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
ES_CHUMO=0
ARCHIVOS_CHUMO=()

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
    ARCHIVO=""
    INSTALACION=""
    ES_CHUMO=0
    ARCHIVOS_CHUMO=()

    # Prioridad 1: ChumoGH Plus.
    if [[ -f "/etc/adm-lite/menu_credito" ||
          -f "/usr/bin/ejecutar/menu_credito" ||
          -f "/usr/bin/ejecutar/exito" ]]; then

        INSTALACION="CHUMOGH PLUS"
        ES_CHUMO=1

        ARCHIVOS_CHUMO=(
            "/etc/adm-lite/menu_credito"
            "/usr/bin/ejecutar/menu_credito"
            "/usr/bin/ejecutar/exito"
        )

    # Prioridad 2: ADMRufu 2.0.
    elif [[ -d "/etc/ADMRufu2.0" || -d "/etc/ADMRufu" || -f "/etc/reseller" ]]; then
        ARCHIVO="/etc/reseller"
        INSTALACION="ADMRUFU 2.0"

    # Prioridad 3: La Casita MX.
    elif [[ -f "/etc/VPS-MX/message.txt" || -d "/etc/VPS-MX" ]]; then
        ARCHIVO="/etc/VPS-MX/message.txt"
        INSTALACION="LA CASITA MX"

    else
        return 1
    fi

    # Comprobar archivos de ChumoGH Plus.
    if ((ES_CHUMO == 1)); then
        local archivo

        for archivo in "${ARCHIVOS_CHUMO[@]}"; do
            if [[ ! -f "$archivo" || ! -w "$archivo" ]]; then
                return 2
            fi
        done

        return 0
    fi

    # Comprobar que el archivo existente sea escribible.
    if [[ -e "$ARCHIVO" ]]; then
        if [[ ! -f "$ARCHIVO" || ! -w "$ARCHIVO" ]]; then
            return 2
        fi
    else
        # Si no existe, comprobar que el directorio de destino
        # permita crearlo.
        if [[ ! -d "$(dirname "$ARCHIVO")" || ! -w "$(dirname "$ARCHIVO")" ]]; then
            return 2
        fi
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
detectar_instalacion
estado_deteccion=$?

if ((estado_deteccion == 1)); then
    printf '%b\n' "${rojo}${negrita}ERROR:${reset} No se detectó una instalación compatible."
    printf '%b\n' "${gris}Rutas reconocidas:${reset}"
    printf '%b\n' "${gris}ADMRufu 2.0: /etc/ADMRufu2.0 o /etc/reseller${reset}"
    printf '%b\n' "${gris}La Casita MX: /etc/VPS-MX/message.txt${reset}"
    printf '%b\n' "${gris}ChumoGH Plus: /etc/adm-lite/menu_credito${reset}"
    pausa
    exit 1
elif ((estado_deteccion == 2)); then
    printf '%b\n' "${rojo}${negrita}ERROR:${reset} No se puede escribir en los archivos de destino."
    printf '%b\n' "${gris}Instalación: $INSTALACION${reset}"

    if ((ES_CHUMO == 1)); then
        for archivo in "${ARCHIVOS_CHUMO[@]}"; do
            printf '%b\n' "${gris}Archivo: $archivo${reset}"
        done
    else
        printf '%b\n' "${gris}Archivo: $ARCHIVO${reset}"
    fi

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
if ((ES_CHUMO == 1)); then
    if ! actual=$(head -n 1 -- "${ARCHIVOS_CHUMO[0]}"); then
        printf '%b\n' "${rojo}No se pudo leer el nombre actual.${reset}"
        pausa
        exit 1
    fi

    [[ -z "$actual" ]] && actual="(Archivo vacio)"

elif [[ -f "$ARCHIVO" ]]; then
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
if ((ES_CHUMO == 1)); then

    if ! python3 - "$final" "${ARCHIVOS_CHUMO[@]}" <<'PY'
import sys
from pathlib import Path

nuevo = sys.argv[1]
rutas = sys.argv[2:]

menu_credito = Path(rutas[0])
menu_ejecutar = Path(rutas[1])
exito = Path(rutas[2])

# Leer los tres archivos antes de realizar modificaciones.
try:
    contenidos = {
        ruta: Path(ruta).read_text(encoding="utf-8")
        for ruta in rutas
    }
except Exception as error:
    print(f"ERROR: No se pudieron leer los archivos: {error}")
    sys.exit(1)

# Separar líneas conservando sus terminaciones.
lineas = {}

for ruta, contenido in contenidos.items():
    lineas[ruta] = contenido.splitlines(keepends=True)

# Validar estructura de los archivos.
for ruta in rutas:
    if not lineas[ruta]:
        print(f"ERROR: El archivo está vacío: {ruta}")
        sys.exit(1)

# Actualizar primera línea de menu_credito.
ruta = str(menu_credito)
linea = lineas[ruta][0]

if linea.endswith("\r\n"):
    terminacion = "\r\n"
elif linea.endswith("\n"):
    terminacion = "\n"
else:
    terminacion = ""

lineas[ruta][0] = nuevo + terminacion

# Actualizar primera línea del menú de ejecución.
ruta = str(menu_ejecutar)
linea = lineas[ruta][0]

if linea.endswith("\r\n"):
    terminacion = "\r\n"
elif linea.endswith("\n"):
    terminacion = "\n"
else:
    terminacion = ""

lineas[ruta][0] = nuevo + terminacion

# Actualizar nombre de exito conservando Verified【 .
ruta = str(exito)
linea = lineas[ruta][0]

if linea.endswith("\r\n"):
    terminacion = "\r\n"
elif linea.endswith("\n"):
    terminacion = "\n"
else:
    terminacion = ""

contenido_linea = linea.rstrip("\r\n")
prefijo = "Verified【 "

if not contenido_linea.startswith(prefijo):
    print(
        "ERROR: El formato de exito no coincide con el esperado. "
        "Se esperaba el prefijo Verified【 "
    )
    sys.exit(1)

lineas[ruta][0] = prefijo + nuevo + terminacion

# Preparar todos los contenidos antes de escribir.
actualizados = {
    ruta: "".join(lineas[ruta])
    for ruta in rutas
}

# Guardar los cambios.
try:
    for ruta, contenido in actualizados.items():
        Path(ruta).write_text(contenido, encoding="utf-8")
except Exception as error:
    print(f"ERROR: No se pudieron guardar todos los archivos: {error}")
    sys.exit(1)

print("OK")
PY
    then
        printf '\n%b\n' "${rojo}${negrita}ERROR:${reset} No se pudo actualizar ChumoGH Plus."
        pausa
        exit 1
    fi

else
    if ! printf '%s\n' "$final" > "$ARCHIVO"; then
        printf '\n%b\n' "${rojo}${negrita}ERROR:${reset} No se pudo guardar el nombre."
        printf '%b\n' "${gris}Archivo: $ARCHIVO${reset}"
        pausa
        exit 1
    fi
fi

# ── Verificar escritura ───────────────────────────────────────
if ((ES_CHUMO == 1)); then

    guardado=$(head -n 1 -- "${ARCHIVOS_CHUMO[0]}") || {
        printf '\n%b\n' "${rojo}No se pudo verificar el archivo.${reset}"
        pausa
        exit 1
    }

    if [[ "$guardado" != "$final" ]]; then
        printf '\n%b\n' "${rojo}${negrita}ERROR:${reset} El contenido guardado no coincide."
        pausa
        exit 1
    fi

else
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
fi

# ── Resultado final ──────────────────────────────────────────
printf '\n'
borde_superior
centrar "CAMBIO COMPLETADO"
separador
fila ""
fila "Reseller actualizado correctamente."
fila ""
borde_inferior

printf '\n'
printf '%b\n' "  ${verde}${negrita}✔ Nuevo nombre:${reset}"
printf '\n'
printf '  %b\n' "${amarillo}${negrita}${final}${reset}"
printf '\n'

if ((ES_CHUMO == 1)); then
    printf '%b\n' "  ${verde}✔ Guardado en:${reset}"

    for archivo in "${ARCHIVOS_CHUMO[@]}"; do
        printf '  %b\n' "${blanco}${archivo}${reset}"
    done
else
    printf '%b\n' "  ${verde}✔ Guardado en:${reset} ${blanco}${ARCHIVO}${reset}"
fi

printf '\n'
printf '%b\n' "${gris}${INSTALACION} | Gestor de Reseller${reset}"

pausa
