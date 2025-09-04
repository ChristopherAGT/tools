#!/bin/bash
# Script seguro para usar claves privadas y públicas existentes en SlowDNS
# Autor: ChatGPT

set -euo pipefail

SLOWDNS_DIR="/root/ADMRufu/slowdns"
SERVICE_FILE="/etc/systemd/system/slowdns.service"

mkdir -p "$SLOWDNS_DIR"
cd "$SLOWDNS_DIR"

echo "=== Configuración de SlowDNS con claves existentes ==="

# Respaldo de claves antiguas
if [[ -f server.key || -f server.pub ]]; then
    echo "📦 Haciendo respaldo de claves antiguas..."
    mv server.key server.key.bak || true
    mv server.pub server.pub.bak || true
fi

# Solicitar al usuario las claves en HEX
read -p "👉 Ingresa tu PRIVATE KEY (hex de 64 caracteres de tu VPS anterior): " PRIV_HEX
read -p "👉 Ingresa tu PUBLIC KEY (hex de 64 caracteres de tu VPS anterior): " PUB_HEX

# Validar longitud
if [[ ${#PRIV_HEX} -ne 64 || ${#PUB_HEX} -ne 64 ]]; then
  echo "❌ Error: ambas claves deben ser hex de 64 caracteres (32 bytes)."
  exit 1
fi

# Convertir a binario
echo "$PRIV_HEX" | xxd -r -p > server.key
echo "$PUB_HEX" | xxd -r -p > server.pub
chmod 600 server.key server.pub

# Verificar tamaño
if [[ $(stat -c '%s' server.key) -ne 32 || $(stat -c '%s' server.pub) -ne 32 ]]; then
    echo "❌ Error: los archivos generados no tienen 32 bytes. Verifica tus claves."
    exit 1
fi

echo "✅ Claves convertidas a binario correctamente."

# Actualizar el servicio slowdns para usar la clave privada
if grep -q "\-privkey-file" "$SERVICE_FILE"; then
    sed -i "s#-privkey-file[[:space:]]\+\([^[:space:]]\+\)#-privkey-file $SLOWDNS_DIR/server.key#g" "$SERVICE_FILE"
else
    echo "❌ No se encontró la opción -privkey-file en $SERVICE_FILE"
    exit 1
fi

# Reiniciar servicio
systemctl daemon-reload
systemctl restart slowdns

# Verificar estado
echo "=== Estado del servicio ==="
systemctl status slowdns --no-pager -l | head -n 10

# Mostrar la clave pública en base64 para clientes
echo "=== Clave pública en base64 (para clientes) ==="
base64 -w0 server.pub
echo -e "\n==============================================="
echo "✅ SlowDNS listo con tus claves privadas y públicas existentes."
