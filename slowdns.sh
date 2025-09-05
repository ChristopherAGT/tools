#!/bin/bash
# ==========================================================
#  KEY-MANAGER - Configurador de Claves SlowDNS (ADMRufu)
#  Autor: Christopher + ChatGPT
#  Interfaz profesional con panel fijo y pasos claros
# ==========================================================

set -euo pipefail

# 🎨 Colores
verde="\e[92m"
rojo="\e[91m"
amarillo="\e[93m"
cyan="\e[96m"
reset="\e[0m"
negrita="\e[1m"

# 📂 Archivos de claves
PRIVKEY_FILES=(
    "/root/ADMRufu/slowdns/server.key"
    "/etc/ADMRufu2.0/etc/slowdns/server.key"
)
PUBKEY_FILES=(
    "/root/ADMRufu/slowdns/server.pub"
    "/etc/ADMRufu2.0/etc/slowdns/server.pub"
)

SERVICE_NAME="slowdns"

# =========================
# Función: Banner Configuración SlowDNS
# =========================
show_slowdns_banner() {
    echo -e "${cyan}┌───────────────────────────────────────────────┐${reset}"
    echo -e "${cyan}│${verde}${negrita}      CONFIGURADOR DE CLAVES SLOWDNS      ${cyan}│${reset}"
    echo -e "${cyan}└───────────────────────────────────────────────┘${reset}\n"
}

# =========================
# Función: Ingresar nuevas claves
# =========================
ingresar_claves() {
    clear
    show_slowdns_banner

    echo -e "${amarillo}🔹 Paso 1: Ingresar nuevas claves${reset}"
    read -p "  👉 Clave PRIVADA: " PRIVKEY
    read -p "  👉 Clave PÚBLICA: " PUBKEY

    if [[ -z "$PRIVKEY" || -z "$PUBKEY" ]]; then
        echo -e "${rojo}❌ Error: Ambas claves son obligatorias.${reset}"
        sleep 2
        return
    fi

    echo -e "\n${amarillo}🔹 Paso 2: Guardando claves...${reset}"
    TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

    for file in "${PRIVKEY_FILES[@]}"; do
        [[ -f "$file" ]] && cp "$file" "$file.bak.$TIMESTAMP"
        echo "$PRIVKEY" > "$file"
        echo -e "  ✅ Privada actualizada en: ${cyan}$file${reset}"
    done

    for file in "${PUBKEY_FILES[@]}"; do
        [[ -f "$file" ]] && cp "$file" "$file.bak.$TIMESTAMP"
        echo "$PUBKEY" > "$file"
        echo -e "  ✅ Pública actualizada en: ${cyan}$file${reset}"
    done

    echo -e "\n${amarillo}🔹 Paso 3: Verificando archivos...${reset}"
    for file in "${PRIVKEY_FILES[@]}" "${PUBKEY_FILES[@]}"; do
        if [[ ! -s "$file" ]]; then
            echo -e "  ${rojo}❌ Error: Falló la escritura en $file${reset}"
            return
        fi
    done
    echo -e "  ${verde}✔ Todos los archivos se escribieron correctamente.${reset}"

    echo -e "\n${amarillo}🔹 Paso 4: Reiniciando servicio SlowDNS...${reset}"
    systemctl daemon-reload
    systemctl restart "$SERVICE_NAME"
    sleep 1

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "  ${verde}✅ SlowDNS reiniciado correctamente.${reset}"
    else
        echo -e "  ${rojo}❌ Error: No se pudo reiniciar SlowDNS.${reset}"
        return
    fi

    echo -e "\n${cyan}┌───────────────────────────────────────────────┐${reset}"
    echo -e "${cyan}│${verde}${negrita}       PROCESO COMPLETADO CON ÉXITO       ${cyan}│${reset}"
    echo -e "${cyan}└───────────────────────────────────────────────┘${reset}\n"
    echo -e "${amarillo}🎉 Tus nuevas claves ya están activas.${reset}"
    echo -e "${amarillo}💡 Recuerda: Los respaldos se encuentran con extensión .bak.${reset}\n"
    read -p "Presiona Enter para regresar al menú..."
}

# =========================
# Función: Mostrar claves actuales
# =========================
mostrar_claves() {
    clear
    echo -e "${cyan}┌───────────────────────────────────────────────┐${reset}"
    echo -e "${verde}${negrita}                 CLAVES ACTUALES                 ${reset}"
    echo -e "${cyan}└───────────────────────────────────────────────┘${reset}\n"

    echo -e "${negrita}Privada:${reset}"
    cat "${PRIVKEY_FILES[0]}"
    echo -e "\n${negrita}Pública:${reset}"
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
        echo -e "  ${verde}✅ Servicio reiniciado correctamente.${reset}"
    else
        echo -e "  ${rojo}❌ Error: No se pudo reiniciar SlowDNS.${reset}"
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
        echo -e "${verde}${negrita}                        KEY-MANAGER                        ${reset}"
        echo -e "${cyan}└───────────────────────────────────────────────┘${reset}\n"

        echo -e "${verde}1${reset} 📝 Ingresar nuevas claves"
        echo -e "${verde}2${reset} 🔍 Mostrar claves actuales"
        echo -e "${verde}3${reset} 🔄 Reiniciar servicio SlowDNS"
        echo -e "${verde}0${reset} ❌ Salir"

        echo -ne "\nSelecciona una opción: "
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
