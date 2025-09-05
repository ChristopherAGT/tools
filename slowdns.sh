#!/bin/bash
# ==========================================================
#  Configurador de Claves SlowDNS (ADMRufu)
#  Versión completa con menú interactivo y diseño profesional
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
# Función: Mostrar banner
# =========================
show_banner() {
    clear
    echo -e "${cyan}┌───────────────────────────────────────────────┐${reset}"
    echo -e "${cyan}│${verde}${negrita}      CONFIGURADOR DE CLAVES SLOWDNS      ${cyan}│${reset}"
    echo -e "${cyan}└───────────────────────────────────────────────┘${reset}\n"
}

# =========================
# Función: Ingresar nuevas claves
# =========================
ingresar_claves() {
    show_banner
    echo -e "${amarillo}🔹 Paso 1: Ingresar nuevas claves${reset}"
    read -p "  👉 Clave PRIVADA: " PRIVKEY
    read -p "  👉 Clave PÚBLICA: " PUBKEY

    if [[ -z "$PRIVKEY" || -z "$PUBKEY" ]]; then
        echo -e "${rojo}❌ Error: Ambas claves son obligatorias.${reset}"
        sleep 2
        return
    fi

    TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
    echo -e "\n${amarillo}🔹 Paso 2: Guardando claves con respaldo...${reset}"

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

    echo -e "\n${verde}✔ Claves reemplazadas correctamente.${reset}"
    sleep 1

    reiniciar_slowdns
}

# =========================
# Función: Mostrar claves actuales
# =========================
mostrar_claves() {
    show_banner
    echo -e "${amarillo}🔹 Claves actuales${reset}\n"
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
reiniciar_slowdns() {
    echo -e "\n${amarillo}🔹 Paso 3: Reiniciando servicio SlowDNS...${reset}"
    systemctl daemon-reload
    systemctl restart "$SERVICE_NAME"
    sleep 1

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "  ${verde}✅ SlowDNS reiniciado correctamente.${reset}"
    else
        echo -e "  ${rojo}❌ Error: No se pudo reiniciar SlowDNS.${reset}"
    fi
    sleep 2
}

# =========================
# Función: Ver backups de claves
# =========================
ver_backups() {
    show_banner
    echo -e "${amarillo}🔹 BACKUPS DE CLAVES DISPONIBLES${reset}\n"

    echo -e "${negrita}${cyan}CLAVES PRIVADAS:${reset}"
    for file in "${PRIVKEY_FILES[@]}"; do
        backups=($(ls -1 "$file".bak* 2>/dev/null | sort))
        if [[ ${#backups[@]} -eq 0 ]]; then
            echo "  Ningún backup encontrado en: $file"
        else
            for b in "${backups[@]}"; do
                echo "  - $b"
            done
        fi
    done

    echo -e "\n${negrita}${cyan}CLAVES PÚBLICAS:${reset}"
    for file in "${PUBKEY_FILES[@]}"; do
        backups=($(ls -1 "$file".bak* 2>/dev/null | sort))
        if [[ ${#backups[@]} -eq 0 ]]; then
            echo "  Ningún backup encontrado en: $file"
        else
            for b in "${backups[@]}"; do
                echo "  - $b"
            done
        fi
    done

    echo -e "\n${amarillo}🔹 Fin del listado de backups${reset}\n"
    read -p "Presiona Enter para volver al menú..."
}

# =========================
# Menú principal
# =========================
menu_principal() {
    while true; do
        show_banner
        echo -e "${amarillo}Selecciona una opción:${reset}"
        echo -e "  ${verde}[1]${reset} Ingresar nuevas claves"
        echo -e "  ${verde}[2]${reset} Mostrar claves actuales"
        echo -e "  ${verde}[3]${reset} Reiniciar servicio SlowDNS"
        echo -e "  ${verde}[4]${reset} Ver backups de claves"
        echo -e "  ${verde}[5]${reset} Salir"
        echo -ne "\nOpción: "
        read opcion

        case $opcion in
            1) ingresar_claves ;;
            2) mostrar_claves ;;
            3) reiniciar_slowdns ;;
            4) ver_backups ;;
            5) echo -e "${cyan}Saliendo...${reset}"; exit 0 ;;
            *) echo -e "${rojo}Opción inválida, intenta de nuevo.${reset}"; sleep 1 ;;
        esac
    done
}

# =========================
# Inicio del script
# =========================
menu_principal
