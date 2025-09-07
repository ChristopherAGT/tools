#!/bin/bash
#========================================================
#  Script de Configuración de Repositorios Ubuntu 22.04
#  Autor: Christopher
#========================================================

# Colores
verde="\e[92m"
rojo="\e[91m"
azul="\e[94m"
amarillo="\e[93m"
negrita="\e[1m"
reset="\e[0m"

# Archivo de log
LOGFILE="/var/log/configurar_repos.log"

# Spinner
spinner() {
    local pid=$1
    local task=$2
    local delay=0.1
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

    while kill -0 $pid 2>/dev/null; do
        for i in $(seq 0 $((${#spin}-1))); do
            printf "\r${amarillo}[%s]${reset} %s..." "${spin:$i:1}" "$task"
            sleep $delay
        done
    done

    wait $pid
    local status=$?
    if [ $status -eq 0 ]; then
        printf "\r${verde}[✔]${reset} %s completado.        \n" "$task"
    else
        printf "\r${rojo}[✘]${reset} Error en %s. Revisa el log: $LOGFILE\n" "$task"
        exit 1
    fi
}

# Encabezado elegante
clear
echo -e "${azul}${negrita}"
echo "═══════════════════════════════════════════════"
echo "      CONFIGURADOR DE REPOSITORIOS UBUNTU"
echo "═══════════════════════════════════════════════"
echo -e "${reset}"

# Paso 1: Vaciar sources.list
{ sudo bash -c "echo '' > /etc/apt/sources.list" >>"$LOGFILE" 2>&1; } &
pid=$!
spinner $pid "Vaciando archivo de repositorios"

# Paso 2: Insertar repositorios
{ 
sudo tee /etc/apt/sources.list > /dev/null <<EOF
## Ubuntu 22.04

deb http://mirror.ufscar.br/ubuntu jammy main restricted universe multiverse
deb http://mirror.ufscar.br/ubuntu jammy-updates main restricted universe multiverse
deb http://mirror.ufscar.br/ubuntu jammy-backports main restricted universe multiverse
deb http://mirror.ufscar.br/ubuntu jammy-security main restricted universe multiverse
EOF
} >>"$LOGFILE" 2>&1 &
pid=$!
spinner $pid "Agregando nuevos repositorios"

# Paso 3: Actualización del sistema (MOSTRAR log en pantalla y guardarlo)
echo -e "\n${amarillo}▶ Iniciando actualización del sistema...${reset}"
sudo apt update -y 2>&1 | tee -a "$LOGFILE"
sudo apt upgrade -y 2>&1 | tee -a "$LOGFILE"

# Paso 6: Animación final elegante
echo -e "${verde}${negrita}"
echo "═══════════════════════════════════════════════"
echo "        ✅  SISTEMA ACTUALIZADO CON ÉXITO ✅"
echo "═══════════════════════════════════════════════"
echo -e "${reset}"

# Paso 7: Preguntar si reiniciar
echo -ne "${amarillo}¿Deseas reiniciar el sistema ahora? (s/N): ${reset}"
read respuesta
if [[ "$respuesta" =~ ^[sS]$ ]]; then
    echo -e "${azul}Reiniciando...${reset}"
    sleep 2
    sudo reboot
else
    echo -e "${verde}Proceso finalizado sin reinicio.${reset}"
    echo -e "${amarillo}ℹ️ Log disponible en: $LOGFILE${reset}"
fi
