#!/bin/bash
# ==========================================================
#  KEY-MANAGER SLOWDNS - VPS-MX
#  Autor: ChristopherAGT
# ==========================================================

set -euo pipefail

# Colores
verde="\e[92m"
rojo="\e[91m"
amarillo="\e[93m"
cyan="\e[96m"
magenta="\e[95m"
azul="\e[94m"
reset="\e[0m"
negrita="\e[1m"

# Rutas
PRIVKEY="/etc/VPS-MX/Slow/Key/server.key"
PUBKEY="/etc/VPS-MX/Slow/Key/server.pub"
SERVICE="slowdns"
WIDTH=47

banner() {
    echo -e "${cyan}┌───────────────────────────────────────────────┐${reset}"
    title="KEY-MANAGER SLOWDNS"
    padL=$(( (WIDTH - 2 - ${#title}) / 2 ))
    padR=$(( WIDTH - 2 - padL - ${#title} ))
    printf "${cyan}│%*s${negrita}${verde}%s${cyan}%*s│${reset}\n" "$padL" "" "$title" "$padR" ""
    echo -e "${cyan}└───────────────────────────────────────────────┘${reset}\n"
}

check_files() {
    [[ -f "$PRIVKEY" && -f "$PUBKEY" ]] || {
        echo -e "${rojo}❌ Archivos de claves no encontrados.${reset}"
        exit 1
    }
}

set_keys() {
    clear
    banner
    check_files

    echo -e "${amarillo}⚠️ Cambiar claves desconecta todos los clientes${reset}\n"

    read -r -p "👉 Clave PRIVADA: " priv
    read -r -p "👉 Clave PÚBLICA: " pub

    [[ -z "$priv" || -z "$pub" ]] && {
        echo -e "${rojo}❌ Claves vacías.${reset}"
        sleep 2
        return
    }

    echo "$priv" > "$PRIVKEY"
    echo "$pub"  > "$PUBKEY"

    chmod 600 "$PRIVKEY"
    chmod 644 "$PUBKEY"

    systemctl restart "$SERVICE" || true

    echo -e "${verde}✅ Claves aplicadas.${reset}"
    read -r -p "Enter para continuar..."
}

show_keys() {
    clear
    banner
    check_files

    echo -e "${magenta}Privada:${reset}"
    cat "$PRIVKEY"
    echo -e "\n${magenta}Pública:${reset}"
    cat "$PUBKEY"

    echo
    read -r -p "Enter para continuar..."
}

restart_srv() {
    clear
    banner
    systemctl restart "$SERVICE" || true
    systemctl is-active --quiet "$SERVICE" \
        && echo -e "${verde}✅ Servicio activo${reset}" \
        || echo -e "${rojo}❌ Servicio detenido${reset}"
    read -r -p "Enter para continuar..."
}

menu() {
    while true; do
        clear
        banner
        echo -e "${magenta}1${reset} 📝 Cambiar claves"
        echo -e "${magenta}2${reset} 🔍 Mostrar claves"
        echo -e "${magenta}3${reset} 🔄 Reiniciar SlowDNS"
        echo -e "${magenta}0${reset} ❌ Salir"
        echo -e "${azul}───────────────────────────────────────────────${reset}"
        read -r -p "Opción: " opt

        case "${opt:-}" in
            1) set_keys ;;
            2) show_keys ;;
            3) restart_srv ;;
            0) exit 0 ;;
            *) echo -e "${rojo}Opción inválida${reset}"; sleep 1 ;;
        esac
    done
}

menu
