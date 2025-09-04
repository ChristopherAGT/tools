#!/bin/bash
# Script para cambiar el nombre del Reseller en admrufu 2.0
# By: Tu Nombre o Marca

# Colores
verde="\e[92m"
rojo="\e[91m"
azul="\e[94m"
amarillo="\e[93m"
negrita="\e[1m"
reset="\e[0m"

# Limpiar pantalla
clear

# Banner
echo -e "${azul}${negrita}"
echo "═══════════════════════════════════════"
echo "        CAMBIAR NOMBRE DE RESELLER      "
echo "═══════════════════════════════════════"
echo -e "${reset}"

# Mostrar reseller actual
if [ -f /etc/reseller ]; then
    actual=$(cat /etc/reseller)
else
    actual="(No existe aún)"
fi

echo -e "👤 ${amarillo}Reseller actual:${reset} $actual"
echo

# Solicitar nuevo nombre
read -p "👉 Escribe el nuevo nombre de Reseller: " nuevo

# Validación
if [ -z "$nuevo" ]; then
    echo -e "${rojo}❌ Error:${reset} No ingresaste un nombre."
    exit 1
fi

# Guardar nuevo reseller
echo "$nuevo" > /etc/reseller

# Confirmación
echo
echo -e "${verde}✅ Éxito:${reset} El nombre de Reseller fue cambiado a: ${negrita}$nuevo${reset}"
echo

# Preguntar si quiere reiniciar el panel/script
read -p "🔄 ¿Quieres reiniciar el panel ahora? (s/n): " resp
if [[ "$resp" =~ ^[sS]$ ]]; then
    systemctl restart admrufu 2>/dev/null || bash /root/admrufu.sh
    echo -e "${verde}⚡ Panel reiniciado correctamente.${reset}"
else
    echo -e "${amarillo}ℹ️ Recuerda reiniciar manualmente el panel para aplicar el cambio.${reset}"
fi

echo
echo -e "${azul}${negrita}═══════════════════════════════════════"
echo "         CAMBIO DE RESELLER LISTO        "
echo "═══════════════════════════════════════${reset}"
