#!/bin/bash
# ==========================================================
#  Configurador de Claves SlowDNS (ADMRufu)
#  Autor: Christopher + ChatGPT
# ==========================================================

set -euo pipefail

# 🎨 Colores
verde="\e[92m"
rojo="\e[91m"
azul="\e[94m"
amarillo="\e[93m"
reset="\e[0m"

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
echo -e "${azul}═══════════════════════════════════════════════════════${reset}"
echo -e "        ${verde}ASIGNADOR DE CLAVES SLOWDNS (ADMRufu)${reset}"
echo -e "${azul}═══════════════════════════════════════════════════════${reset}\n"

# 📝 Solicitar claves
read -p "👉 Ingresa la nueva CLAVE PRIVADA: " PRIVKEY
read -p "👉 Ingresa la nueva CLAVE PÚBLICA: " PUBKEY

# ✅ Validar que no estén vacías
if [[ -z "$PRIVKEY" || -z "$PUBKEY" ]]; then
    echo -e "${rojo}❌ Error: Debes ingresar ambas claves.${reset}"
    exit 1
fi

# 📦 Guardar claves con backup (timestamp)
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

for file in "${PRIVKEY_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        cp "$file" "$file.bak.$TIMESTAMP"
    fi
    echo "$PRIVKEY" > "$file"
    echo -e "✅ Clave privada actualizada en: ${amarillo}$file${reset}"
done

for file in "${PUBKEY_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        cp "$file" "$file.bak.$TIMESTAMP"
    fi
    echo "$PUBKEY" > "$file"
    echo -e "✅ Clave pública actualizada en: ${amarillo}$file${reset}"
done

# 🔍 Verificación de escritura
for file in "${PRIVKEY_FILES[@]}" "${PUBKEY_FILES[@]}"; do
    if [[ ! -s "$file" ]]; then
        echo -e "${rojo}❌ Error: No se pudo escribir en $file${reset}"
        exit 1
    fi
done

echo -e "\n${verde}✔ Claves reemplazadas correctamente.${reset}\n"

# ⚙️ Reinicio del servicio SlowDNS
echo -e "${azul}Reiniciando SlowDNS...${reset}"

if systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
    systemctl daemon-reload
    systemctl restart "$SERVICE_NAME"
    sleep 1
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${verde}✅ SlowDNS reiniciado correctamente con systemd.${reset}"
    else
        echo -e "${rojo}❌ Error: No se pudo reiniciar SlowDNS con systemd.${reset}"
    fi
else
    echo -e "${amarillo}⚠ No se encontró servicio systemd. Reiniciando manualmente...${reset}"
    pkill -f dnstt-server || true
    nohup dnstt-server -privkey-file "${PRIVKEY_FILES[0]}" \
                       -pubkey-file "${PUBKEY_FILES[0]}" \
                       > /var/log/slowdns.log 2>&1 &
    echo -e "${verde}✅ SlowDNS relanzado manualmente en segundo plano.${reset}"
fi

echo -e "\n${verde}🎉 Proceso completado. Tus nuevas claves ya están activas.${reset}\n"
