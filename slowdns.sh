#!/bin/bash
# Script para configurar claves personalizadas en SlowDNS/DNSTT
# Autor: ChatGPT

set -euo pipefail

SLOWDNS_DIR="/root/ADMRufu/slowdns"
SERVICE_FILE="/etc/systemd/system/slowdns.service"

echo "=== Configuración de claves para SlowDNS ==="
read -p "👉 Ingresa tu PRIVATE KEY (hex de 64 caracteres): " PRIV_HEX
read -p "👉 Ingresa tu PUBLIC KEY (hex de 64 caracteres): " PUB_HEX

# Verificar que tengan la longitud correcta
if [[ ${#PRIV_HEX} -ne 64 || ${#PUB_HEX} -ne 64 ]]; then
  echo "❌ Error: ambas claves deben ser hexadecimales de 64 caracteres (32 bytes)."
  exit 1
fi

# Crear carpeta si no existe
mkdir -p "$SLOWDNS_DIR"
cd "$SLOWDNS_DIR"

# Generar archivos binarios desde hex
echo "$PRIV_HEX" | xxd -r -p > server.key
echo "$PUB_HEX"  | xxd -r -p > server.pub

# Fijar permisos seguros
chmod 600 server.key server.pub

# Verificar tamaño correcto
echo "=== Verificación de tamaños ==="
stat -c '%n -> %s bytes' server.key server.pub
if [[ $(stat -c '%s' server.key) -ne 32 || $(stat -c '%s' server.pub) -ne 32 ]]; then
  echo "❌ Error: los archivos no miden 32 bytes. Revisa las claves ingresadas."
  exit 1
fi

# Asegurar que el servicio use nuestra clave privada
if grep -q "\-privkey-file" "$SERVICE_FILE"; then
  sed -i "s#-privkey-file[[:space:]]\+\([^[:space:]]\+\)#-privkey-file $SLOWDNS_DIR/server.key#g" "$SERVICE_FILE"
else
  echo "❌ No se encontró la opción -privkey-file en $SERVICE_FILE"
  exit 1
fi

# Recargar systemd y reiniciar slowdns
systemctl daemon-reload
systemctl restart slowdns

echo "=== Estado del servicio ==="
systemctl status slowdns --no-pager -l | head -n 10

# Mostrar clave pública en base64 para clientes
echo "=== Clave pública en base64 (para usar en clientes) ==="
base64 -w0 server.pub
echo -e "\n==============================================="
echo "✅ Claves instaladas y slowdns reiniciado."
echo "   - Privada: $SLOWDNS_DIR/server.key"
echo "   - Pública: $SLOWDNS_DIR/server.pub"
