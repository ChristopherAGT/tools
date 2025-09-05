#!/bin/bash
# ==========================================================
#  Configurador de Claves SlowDNS (ADMRufu)
#  Autor: Christopher + ChatGPT
#  Interfaz mejorada y profesional
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

clear
echo -e "${cyan}┌───────────────────────────────────────────────┐${reset}"
echo -e "${cyan}│${verde}${negrita}      CONFIGURADOR DE CLAVES SLOWDNS      ${cyan}│${reset}"
echo -e "${cyan}└───────────────────────────────────────────────┘${reset}\n"

echo -e "${amarillo}🔹 Paso 1: Ingresar nuevas claves${reset}"
read -p "  👉 Clave PRIVADA: " PRIVKEY
read -p "  👉 Clave PÚBLICA: " PUBKEY

if [[ -z "$PRIVKEY" || -z "$PUBKEY" ]]; then
    echo -e "${rojo}❌ Error: Ambas claves son obligatorias.${reset}"
    exit 1
fi

echo -e "\n${amarillo}🔹 Paso 2: Guardando claves con respaldo...${reset}"
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
        exit 1
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
    exit 1
fi

echo -e "\n${cyan}┌───────────────────────────────────────────────┐${reset}"
echo -e "${cyan}│${verde}${negrita}       PROCESO COMPLETADO CON ÉXITO       ${cyan}│${reset}"
echo -e "${cyan}└───────────────────────────────────────────────┘${reset}\n"

echo -e "${amarillo}🎉 Tus nuevas claves ya están activas.${reset}"
echo -e "${amarillo}💡 Recuerda: Los respaldos se encuentran con extensión .bak.${reset}\n"
