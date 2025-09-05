#!/bin/bash
# ==========================================================
#  KEY-MANAGER
#  Interfaz organizada y profesional con panel fijo
# ==========================================================

set -euo pipefail

# 🎨 Colores
verde="\e[92m"
rojo="\e[91m"
azul="\e[94m"
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
# Banner Configuración SlowDNS
# =========================
show_slowdns_banner() {
    echo -e "${cyan}==============================================================${reset}"
    echo -e "${verde}${negrita}                CONFIGURADOR DE CLAVES SLOWDNS                ${reset}"
    echo -e "${cyan}==============================================================${reset}\n"
}

# =========================
# Función: Ingresar nuevas claves
# =========================
ingresar_claves() {
    show_slowdns_banner
    echo -e "${amarillo}🔹 Ingresar nuevas claves${reset}\n"

    read -p "  👉 Clave PRIVADA: " PRIVKEY
    read -p "  👉 Clave PÚBLICA: " PUBKEY

    if [[ -z "$PRIVKEY" || -z "$PUBKEY" ]]; then
        echo -e "${rojo}❌ Error: Ambas claves son obligatorias.${reset}"
        sleep 2
        return
    fi

    echo ""
    # Guardar claves
    for file in "${PRIVKEY_FILES[@]}"; do
        echo "$PRIVKEY" > "$file"
        echo -e "  ✅ Privada actualizada en: ${cyan}$file${reset}"
    done
    for file in "${PUBKEY_FILES[@]}"; do
        echo "$PUBKEY" > "$file"
        echo -e "  ✅ Pública actualizada en: ${cyan}$file${reset}"
    done

    # Reiniciar servicio y mostrar mensaje final
    reiniciar_slowdns "✔ Claves reemplazadas y servicio reiniciado correctamente."
}

# =========================
# Función: Mostrar claves actuales
# =========================
mostrar_claves() {
    echo -e "${cyan}==============================================================${reset}"
    echo -e "${amarillo}${negrita}🔹 Claves actuales${reset}"
    echo -e "${cyan}==============================================================${reset}\n"

    echo -e "${negrita}Privada:${reset}"
    cat "${PRIVKEY_FILES[0]}"
    echo -e "\n${negrita}Pública:${reset}"
    cat "${PUBKEY_FILES[0]}"
    echo ""
    read -p "Presiona Enter para volver al menú..."
}

# =========================
# Función: Reiniciar SlowDNS
# =========================
# Parámetro opcional: mensaje final
reiniciar_slowdns() {
    mensaje_final=${1:-"🔹 Servicio SlowDNS reiniciado."}
    echo -e "\n${amarillo}🔹 Reiniciando servicio SlowDNS...${reset}"
    systemctl daemon-reload
    systemctl restart "$SERVICE_NAME"
    sleep 1

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "  ${verde}✅ $mensaje_final${reset}"
    else
        echo -e "  ${rojo}❌ Error: No se pudo reiniciar SlowDNS.${reset}"
    fi
    sleep 2
}

# =========================
# Función: Menú principal con panel fijo
# =========================
menu_principal() {
    while true; do
        clear
        echo -e "${cyan}==============================================================${reset}"
        echo -e "${verde}${negrita}                        KEY-MANAGER                        ${reset}"
        echo -e "${cyan}==============================================================${reset}\n"

        # Opciones del menú
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
