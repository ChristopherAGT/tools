#!/bin/bash
# Script para activar TCP BBR y optimizar red en Linux VPS
# Compatible con Ubuntu/Debian/CentOS 8+

# Colores para mensajes
verde="\e[92m"
amarillo="\e[93m"
rojo="\e[91m"
reset="\e[0m"

# Verificar permisos de root
if [ "$EUID" -ne 0 ]; then
    echo -e "${rojo}Por favor, ejecuta el script como root.${reset}"
    exit 1
fi

echo -e "${amarillo}Verificando kernel...${reset}"
KERNEL_VER=$(uname -r | awk -F- '{print $1}')
if [[ $(echo "$KERNEL_VER >= 4.9" | bc) -eq 1 ]]; then
    echo -e "${verde}Kernel compatible: $KERNEL_VER${reset}"
else
    echo -e "${rojo}Kernel demasiado antiguo: $KERNEL_VER. Necesitas >= 4.9${reset}"
    exit 1
fi

# Verificar si BBR ya está activo
CURRENT_BBR=$(sysctl -n net.ipv4.tcp_congestion_control)
if [[ "$CURRENT_BBR" == "bbr" ]]; then
    echo -e "${verde}BBR ya está activo.${reset}"
else
    echo -e "${amarillo}Activando TCP BBR...${reset}"
    grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
fi

echo -e "${amarillo}Aplicando parámetros de red optimizados...${reset}"
cat <<EOF | sudo tee -a /etc/sysctl.conf
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_timestamps=1
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 134217728
net.ipv4.tcp_wmem=4096 65536 134217728
EOF

sudo sysctl -p

echo -e "${amarillo}Verificando BBR...${reset}"
sysctl net.ipv4.tcp_congestion_control
lsmod | grep bbr

echo -e "${verde}✅ Optimización completada.${reset}"
