#!/bin/bash

# ==================================================
#  HERRAMIENTA DE ELIMINACIÓN DE CERTIFICADOS SSL
#  Gestor: acme.sh
#  Autor: Christopher
# ==================================================

ACME_BIN="/root/.acme.sh/acme.sh"
ACME_DIR="/root/.acme.sh"

clear
echo "================================================"
echo "   HERRAMIENTA PARA ELIMINAR CERTIFICADOS SSL"
echo "                (acme.sh)"
echo "================================================"
echo

read -rp "👉 Ingrese el dominio del certificado a eliminar (ej: ejemplo.com): " DOMINIO

# ---------------- VALIDACIÓN ----------------
if [[ -z "$DOMINIO" ]]; then
  echo
  echo "❌ Error: El dominio no puede estar vacío."
  exit 1
fi

if [[ ! "$DOMINIO" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
  echo
  echo "❌ Error: El dominio ingresado no es válido."
  exit 1
fi

echo
echo "🔍 Verificando certificado para el dominio: $DOMINIO"
echo

CERT_EXISTE=$($ACME_BIN --list 2>/dev/null | grep -w "$DOMINIO")

if [[ -z "$CERT_EXISTE" ]]; then
  echo "⚠️  No existe ningún certificado emitido para: $DOMINIO"
  echo "No hay nada que eliminar."
  exit 0
fi

# ---------------- CONFIRMACIÓN ----------------
echo
read -rp "⚠️  ¿Está seguro que desea eliminar el certificado SSL para '$DOMINIO'? (s/N): " CONFIRMAR

if [[ ! "$CONFIRMAR" =~ ^[sS]$ ]]; then
  echo
  echo "❌ Operación cancelada por el usuario."
  exit 0
fi

# ---------------- ELIMINACIÓN ----------------
echo
echo "🧹 Eliminando certificado del gestor acme.sh..."
$ACME_BIN --remove -d "$DOMINIO"

if [[ -d "$ACME_DIR/${DOMINIO}_ecc" ]]; then
  echo "🗑️  Eliminando archivos del certificado ECC..."
  rm -rf "$ACME_DIR/${DOMINIO}_ecc"
fi

echo "🗑️  Limpiando archivos residuales..."
rm -rf "$ACME_DIR/${DOMINIO}"*

# ---------------- VERIFICACIÓN FINAL ----------------
echo
echo "🔎 Verificando eliminación completa..."

if ls "$ACME_DIR" | grep -q "$DOMINIO"; then
  echo "⚠️  Advertencia: Aún existen archivos relacionados al dominio."
  echo "Revise manualmente el directorio $ACME_DIR"
else
  echo "✅ Verificación exitosa: El certificado fue eliminado completamente."
fi

echo
echo "================================================"
echo "           PROCESO FINALIZADO"
echo "================================================"
