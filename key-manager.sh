#!/bin/bash
# ==========================================================
#  KEY-MANAGER SLOWDNS - VPS-MX
#  Autor: ChristopherAGT
#  Gestor seguro de claves SlowDNS
# ==========================================================

set -euo pipefail

# 🎨 Colores
verde="\e[92m"
rojo="\e[91m"
amarillo="\e[93m"
cyan="\e[96m"
magenta="\e[95m"
azul="\e[94m"
reset="\e[0m"
negrita="\e[1m"

# 📂 Rutas reales VPS-MX
PRIVKEY_FILES=(
    "/etc/VPS-MX/Slow/Key/server.key"
)
PUBKEY_FILES=(
    "/etc/VPS-MX/Slow/Key/server.pub"
)

SERVICE_NAME="slowdns"
PANEL_WIDTH=47

# =========================
# Banner
# =========================
show_banner() {
    echo -e "${cyan}┌───────────────────────────────────────────────┐${reset}"
    title="KEY-MANAGER SLOWDNS"
    padding_left=$(( (PANEL_WIDTH - 2 - ${#title}) / 2 ))
    padding_right=$(( PANEL_WIDTH - 2 - padding_left - ${#title} ))
    printf "${cyan}│%*s${negrita}${verde}%s${cyan}%*s│${reset}\n" \
        $padding_left "" "$title" $padding_right ""
    echo -e "${cyan}└───────────────────────────────────────────────┘${reset}\n"
}

# =========================
# Validar archivos
# =========================
validar_rutas() {
    for f in "${PRIVKEY_FILES[@]}" "${PUBKEY_FILES[@]}"; do
        if [[ ! -f "$f" ]]; then
            echo -e "${rojo}❌ No existe el archivo: $f${reset}"
            exit 1
        fi
    done
}

# =========================
# Ingresar nuevas claves
# =========================
ingresar_claves() {
    clear
    show_banner
    validar_rutas

    echo -e "${amarillo}⚠️ ADVERTENCIA${reset}"
    echo -e "Cambiar estas claves desconectará TODOS los clientes.\n"

    read -p "👉 Clave PRIVADA: " PRIVKEY
    read -p "👉 Clave PÚBLICA: " PUBKEY

    if [[ -z "$PRIVKEY" || -z "$PUBKEY" ]]; then
        echo -e "${rojo}❌ Ambas claves son obligatorias.${reset}"
        sleep 2
        return
    fi

    echo -e "\n${amarillo}Guardando claves...${reset}"

    for file in "${PRIVKEY_FILES[@]}"; do
        echo "$PRIVKEY" > "$file"
        chmod 600 "$file"
        echo -e "${verde}✔ Privada escrita en:${cyan} $file${reset}"
    done

    for file in "${PUBKEY_FILES[@]}"; do
        echo "$PUBKEY" > "$file"
        chmod 644 "$file"
        echo -e "${verde}✔ Pública escrita en:${cyan} $file${reset}"
    done

    echo -e "\n${amarillo}Reiniciando SlowDNS...${reset}"
    systemctl daemon-reexec
    systemctl restart "$SERVICE_NAME" || true

    sleep 1
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${verde}✅ SlowDNS reiniciado correctamente.${reset}"
    else
        echo -e "${rojo}❌ SlowDNS no pudo iniciarse.${reset}"
    fi

    read -p "Presiona Enter para continuar..."
}

# =========================
# Mostrar claves
# =========================
mostrar_claves() {
    clear
    show_banner
    validar
