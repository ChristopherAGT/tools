#!/bin/bash
# ==========================================================
#  KEY-MANAGER TTDNS - Configurador de Claves (ADMRufu)
#  Autor: ChristopherAGT
#  Interfaz profesional con panel fijo y colores intuitivos
# ==========================================================

set -euo pipefail

# 🎨 Colores
verde="\e[92m"        # Éxito / Confirmación
rojo="\e[91m"         # Error
amarillo="\e[93m"     # Advertencia / Acciones
cyan="\e[96m"         # Paneles / títulos
magenta="\e[95m"      # Opciones
azul="\e[94m"         # Separadores
reset="\e[0m"
negrita="\e[1m"

# 📂 Archivos de claves para TTDNS
PRIVKEY_FILES=(
    "/root/ADMRufu/slowdns/server.key"
)
PUBKEY_FILES=(
    "/root/ADMRufu/slowdns/server.pub"
)

SERVICE_NAME="slowdns"  # Mantener el mismo nombre del servicio o cambiar si aplica
PANEL_WIDTH=47

# =========================
# Banner Configuración TTDNS
# =========================
show_ttdns_banner() {
    echo -e "${cyan}┌───────────────────────────────────────────────┐${reset}"
    title="CONFIGURADOR DE CLAVES TTDNS"
    padding_left=$(( (PANEL_WIDTH - 2 - ${#title}) / 2 ))
    padding_right=$(( PANEL_WIDTH - 2 - padding_left - ${#title} ))
    printf "${cyan}│%*s${negrita}${verde}%s${cyan}%*s│${reset}\n" $padding_left "" "$title" $padding_right ""
    echo -e "${cyan}└───────────────────────────────────────────────┘${reset}\n"
}

# =========================
# Función: Ingresar nuevas claves
# =========================
ingresar_claves() {
    clear
    show_ttdns_banner

    echo -e "${amarillo}🔹 Paso 1: Ingresar nuevas claves${reset}"
    read -p "  👉 Clave PRIVADA: " PRIVKEY
    read -p "  👉 Clave PÚBLICA: " PUBKEY

    if [[ -z "$PRIVKEY" || -z "$PUBKEY" ]]; then
        echo -e "${rojo}❌ Error: Ambas claves son obligatorias.${reset}"
        sleep 2
        return
    fi

    echo -e "\n${amarillo}🔹 Paso 2: Guardando claves...${reset}"

    for file in "${PRIVKEY_FILES[@]}"; do
        echo "$PRIVKEY" > "$file"
        echo -e "  ${verde}✅ Privada actualizada en: ${cyan}$file${reset}"
    done

    for file in "${PUBKEY_FILES[@]}"; do
        echo "$PUBKEY" > "$file"
        echo -e "  ${verde}✅ Pública actualizada en: ${cyan}$file${reset}"
    done

    echo -e "\n${amarillo}🔹 Paso 3: Reiniciando servicio SlowDNS...${reset}"
    systemctl daemon-reload
    systemctl restart "$SERVICE_NAME"
    sleep 1

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${verde}✅ Claves aplicadas y SlowDNS reiniciado correctamente.${reset}"
        echo -e "${amarillo}🎉 Tus nuevas claves ya están activas.${reset}"
    else
        echo -e "${rojo}❌ Error: No se pudo reiniciar SlowDNS.${reset}"
    fi

    read -p "Presiona Enter para regresar al menú..."
}

# =========================
# Función: Mostrar claves actuales
# =========================
mostrar_claves() {
    clear
    echo -e "${cyan}┌───────────────────────────────────────────────┐${reset}"
    title="CLAVES ACTUALES TTDNS"
    padding_left=$(( (PANEL_WIDTH - 2 - ${#title}) / 2 ))
    padding_right=$(( PANEL_WIDTH - 2 - padding_left - ${#title} ))
    printf "${cyan}│%*s${negrita}${azul}%s${cyan}%*s│${reset}\n" $padding_left "" "$title" $padding_right ""
    echo -e "${cyan}└───────────────────────────────────────────────┘${reset}\n"

    echo -e "${magenta}${negrita}Privada:${reset}"
    cat "${PRIVKEY_FILES[0]}"
    echo -e "\n${magenta}${negrita}Pública:${reset}"
    cat "${PUBKEY_FILES[0]}"
    echo ""
    read -p "Presiona Enter para regresar al menú..."
}

# =========================
# Función: Reiniciar SlowDNS
# =========================
reiniciar_slowdns() {
    clear
    echo -e "${amarillo}🔹 Reiniciando servicio SlowDNS...${reset}"
    systemctl daemon-reload
    systemctl restart "$SERVICE_NAME"
    sleep 1

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${verde}✅ Servicio reiniciado correctamente.${reset}"
        echo -e "${amarillo}🎉 SlowDNS está activo y funcionando.${reset}"
    else
        echo -e "${rojo}❌ Error: No se pudo reiniciar SlowDNS.${reset}"
    fi

    echo -e "\nPresiona Enter para regresar al menú..."
    read -r
}

# =========================
# Función: Menú principal
# =========================
menu_principal() {
    while true; do
        clear
        echo -e "${cyan}┌───────────────────────────────────────────────┐${reset}"
        title="KEY-MANAGER TTDNS"
        padding_left=$(( (PANEL_WIDTH - 2 - ${#title}) / 2 ))
        padding_right=$(( PANEL_WIDTH - 2 - padding_left - ${#title} ))
        printf "${cyan}│%*s${negrita}${verde}%s${cyan}%*s│${reset}\n" $padding_left "" "$title" $padding_right ""
        echo -e "${cyan}└───────────────────────────────────────────────┘${reset}\n"

        # Opciones
        echo -e "${magenta}1${reset} 📝 Ingresar nuevas claves"
        echo -e "${magenta}2${reset} 🔍 Mostrar claves actuales"
        echo -e "${magenta}3${reset} 🔄 Reiniciar servicio SlowDNS"
        echo -e "${magenta}0${reset} ❌ Salir"

        # Línea separadora
        echo -e "${azul}───────────────────────────────────────────────${reset}"
        echo -ne "Selecciona una opción: "
        read opcion

        case $opcion in
            1) ingresar_claves ;;
            2) mostrar_claves ;;
            3) reiniciar_slowdns ;;
            0) echo -e "${cyan}Saliendo...${reset}"; exit 0 ;;
            *) echo -e "${rojo}Opción inválida, intenta de nuevo.${reset}"; sleep 1 ;;
        esac
    done
}

# =========================
# Inicio del script
# =========================
menu_principal
