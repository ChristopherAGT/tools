#!/bin/bash
# ==========================================================
#  Configurador de Claves para SlowDNS (ADMRufu)
#  Autor: ChatGPT - versión mejorada y estructurada
# ==========================================================

set -euo pipefail

# 🎨 Colores
verde="\e[92m"
rojo="\e[91m"
azul="\e[94m"
amarillo="\e[93m"
reset="\e[0m"

# 📂 Directorios donde se guardan las llaves
KEY_PATHS=(
    "/root/ADMRufu/slowdns"
    "/etc/ADMRufu2.0/etc/slowdns"
)

SERVICE_NAME="slowdns"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

clear
echo -e "${azul}═══════════════════════════════════════════════════════${reset}"
echo -e "        ${verde}CONFIGURADOR DE CLAVES SLOWDNS (ADMRufu)${reset}"
echo -e "${azul}═══════════════════════════════════════════════════════${reset}\n"

# 📝 Solicitar claves
read -p "👉 Ingresa tu PRIVATE KEY (hex, 64 caracteres): " PRIV_HEX
read -p "👉 Ingresa tu PUBLIC KEY (hex, 64 caracteres): " PUB_HEX

# ✅ Validación
if [[ ${#PRIV_HEX} -ne 64 || ! $PRIV_HEX =~ ^[0-9a-fA-F]+$ ]]; then
    echo -e "${rojo}❌ Error: la clave privada debe tener 64 caracteres hexadecimales.${reset}"
    exit 1
fi
if [[ ${#PUB_HEX} -ne 64 || ! $PUB_HEX =~ ^[0-9a-fA-F]+$ ]]; then
    echo -e "${rojo}❌ Error: la clave pública debe tener 64 caracteres hexadecimales.${reset}"
    exit 1
fi

# 🔒 Guardar claves en cada ruta
for DIR in "${KEY_PATHS[@]}"; do
    mkdir -p "$DIR"

    TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
    [[ -f "$DIR/server.key" ]] && mv "$DIR/server.key" "$DIR/server.key.bak.$TIMESTAMP"
    [[ -f "$DIR/server.pub" ]] && mv "$DIR/server.pub" "$DIR/server.pub.bak.$TIMESTAMP"

    echo "$PRIV_HEX" | xxd -r -p > "$DIR/server.key"
    echo "$PUB_HEX"  | xxd -r -p > "$DIR/server.pub"
    chmod 600 "$DIR/server.key" "$DIR/server.pub"

    echo -e "✅ Claves actualizadas en: ${amarillo}$DIR${reset}"
done

# 🔍 Verificar tamaño de archivos
for DIR in "${KEY_PATHS[@]}"; do
    if [[ $(stat -c '%s' "$DIR/server.key") -ne 32 || $(stat -c '%s' "$DIR/server.pub") -ne 32 ]]; then
        echo -e "${rojo}❌ Error: los archivos generados no tienen 32 bytes. Verifica tus claves.${reset}"
        exit 1
    fi
done

echo -e "\n${verde}✔ Claves convertidas y guardadas correctamente.${reset}\n"

# ⚙️ Reinicio del servicio SlowDNS
echo -e "${azul}Reiniciando servicio SlowDNS...${reset}"

if systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
    systemctl daemon-reload
    systemctl restart "$SERVICE_NAME"
    sleep 1
    systemctl is-active --quiet "$SERVICE_NAME" \
        && echo -e "${verde}✅ SlowDNS reiniciado correctamente.${reset}" \
        || echo -e "${rojo}❌ Error: no se pudo reiniciar SlowDNS.${reset}"
else
    echo -e "${amarillo}⚠ No existe un servicio systemd llamado '${SERVICE_NAME}'. Intentando método alternativo...${reset}"
    pkill -f dnstt-server || true
    nohup dnstt-server -privkey-file "${KEY_PATHS[0]}/server.key" \
                       -pubkey-file "${KEY_PATHS[0]}/server.pub" \
                       > /var/log/slowdns.log 2>&1 &
    echo -e "${verde}✅ SlowDNS relanzado manualmente en segundo plano.${reset}"
fi

# 📢 Mostrar clave pública en Base64 (para clientes)
echo -e "\n${azul}=== Clave pública en base64 (para clientes) ===${reset}"
base64 -w0 "${KEY_PATHS[0]}/server.pub"
echo -e "\n${azul}===============================================${reset}"

echo -e "\n${verde}🎉 SlowDNS listo con tus claves privadas y públicas nuevas.${reset}\n"
