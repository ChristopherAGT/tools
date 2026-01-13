#!/bin/bash

# ==================================================
#  HERRAMIENTA DE ELIMINACIÓN DE CERTIFICADOS SSL
#  Gestor: acme.sh
#  Autor: Christopher
# ==================================================

# ---------------- COLORES ----------------
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

ACME_BIN="/root/.acme.sh/acme.sh"
ACME_DIR="/root/.acme.sh"

clear
echo -e "${CYAN}${BOLD}================================================${RESET}"
echo -e "${BLUE}${BOLD}   HERRAMIENTA PARA ELIMINAR CERTIFICADOS SSL${RESET}"
echo -e "${BLUE}${BOLD}                (acme.sh)${RESET}"
echo -e "${CYAN}${BOLD}================================================${RESET}"
echo

# ---------------- INGRESO DEL DOMINIO ----------------
read -rp "$(echo -e "${YELLOW}👉 Ingrese el dominio del certificado a eliminar (ej: ejemplo.com): ${RESET}")" DOMINIO

# ---------------- VALIDACIÓN ----------------
if [[ -z "$DOMINIO" ]]; then
  echo -e "\n${RED}❌ Error: El dominio no puede estar vacío.${RESET}"
  exit 1
fi

if [[ ! "$DOMINIO" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
  echo -e "\n${RED}❌ Error: El dominio ingresado no es válido.${RESET}"
  exit 1
fi

echo -e "\n${CYAN}🔍 Verificando certificado para el dominio: ${BOLD}$DOMINIO${RESET}\n"

CERT_EXISTE=$($ACME_BIN --list 2>/dev/null | grep -w "$DOMINIO")

if [[ -z "$CERT_EXISTE" ]]; then
  echo -e "${YELLOW}⚠️  No existe ningún certificado emitido para: $DOMINIO${RESET}"
  echo -e "${YELLOW}No hay nada que eliminar.${RESET}"
  exit 0
fi

# ---------------- CONFIRMACIÓN ----------------
echo
read -rp "$(echo -e "${RED}⚠️  ¿Está seguro que desea eliminar el certificado SSL para '$DOMINIO'? (s/N): ${RESET}")" CONFIRMAR

if [[ ! "$CONFIRMAR" =~ ^[sS]$ ]]; then
  echo -e "\n${RED}❌ Operación cancelada por el usuario.${RESET}"
  exit 0
fi

# ---------------- ELIMINACIÓN ----------------
echo -e "\n${CYAN}🧹 Eliminando certificado del gestor acme.sh...${RESET}"
$ACME_BIN --remove -d "$DOMINIO"

if [[ -d "$ACME_DIR/${DOMINIO}_ecc" ]]; then
  echo -e "${CYAN}🗑️  Eliminando archivos del certificado ECC...${RESET}"
  rm -rf "$ACME_DIR/${DOMINIO}_ecc"
fi

echo -e "${CYAN}🗑️  Limpiando archivos residuales...${RESET}"
rm -rf "$ACME_DIR/${DOMINIO}"*

# ---------------- VERIFICACIÓN FINAL ----------------
echo
echo -e "${BLUE}🔎 Verificando eliminación completa...${RESET}"

if ls "$ACME_DIR" | grep -q "$DOMINIO"; then
  echo -e "${YELLOW}⚠️  Advertencia: Aún existen archivos relacionados al dominio.${RESET}"
  echo -e "${YELLOW}Revise manualmente el directorio $ACME_DIR${RESET}"
else
  echo -e "${GREEN}✅ Verificación exitosa: El certificado fue eliminado completamente.${RESET}"
fi

echo
echo -e "${CYAN}${BOLD}================================================${RESET}"
echo -e "${GREEN}${BOLD}           PROCESO FINALIZADO${RESET}"
echo -e "${CYAN}${BOLD}================================================${RESET}"
