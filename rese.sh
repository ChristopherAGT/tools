
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# ============================================================
#              ADMLITE RESELLER EDITOR
#                      EPRO DEV
# ============================================================

FILES=(
    "/etc/adm-lite/menu_credito"
    "/usr/bin/ejecutar/menu_credito"
    "/usr/bin/ejecutar/exito"
)

BACKUP_BASE="/var/backups/adm-lite-reseller"

CYAN='\033[38;5;51m'
BLUE='\033[38;5;39m'
GREEN='\033[38;5;82m'
YELLOW='\033[38;5;220m'
RED='\033[38;5;196m'
WHITE='\033[38;5;255m'
GRAY='\033[38;5;245m'
RESET='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Ejecuta este script como root.${RESET}"
    exit 1
fi

clear

echo
echo -e "${CYAN}       ADMLITE RESELLER EDITOR${RESET}"
echo -e "${WHITE}              EPRO DEV${RESET}"
echo
echo -e "${GRAY}EDITOR DE NOMBRE DEL RESELLER${RESET}"
echo

# ------------------------------------------------------------
# VALIDAR ARCHIVOS
# ------------------------------------------------------------

for FILE in "${FILES[@]}"; do
    if [[ ! -f "$FILE" ]]; then
        echo -e "${RED}✗ Archivo no encontrado: $FILE${RESET}"
        exit 1
    fi
done

# ------------------------------------------------------------
# MOSTRAR CONFIGURACION ACTUAL
# ------------------------------------------------------------

echo -e "${CYAN}RESELLER ACTUAL${RESET}"
echo

for FILE in "${FILES[@]}"; do
    echo -e "${BLUE}$FILE${RESET}"
    head -n 1 "$FILE"
    echo
done

# ------------------------------------------------------------
# SOLICITAR NUEVO NOMBRE
# ------------------------------------------------------------

echo -e "${CYAN}NUEVO NOMBRE DEL RESELLER${RESET}"
echo

read -r -p "Nombre: " NEW_RESELLER

if [[ -z "$NEW_RESELLER" ]]; then
    echo -e "${RED}✗ El nombre no puede estar vacío.${RESET}"
    exit 1
fi

if [[ "$NEW_RESELLER" == *$'\n'* || "$NEW_RESELLER" == *$'\r'* ]]; then
    echo -e "${RED}✗ El nombre contiene caracteres no permitidos.${RESET}"
    exit 1
fi

echo
echo -e "${YELLOW}Nuevo nombre: ${WHITE}${NEW_RESELLER}${RESET}"
echo

read -r -p "¿Confirmas el cambio? [s/N]: " CONFIRM

if [[ ! "$CONFIRM" =~ ^[sS]$ ]]; then
    echo
    echo -e "${YELLOW}Operación cancelada.${RESET}"
    exit 0
fi

# ------------------------------------------------------------
# BACKUP
# ------------------------------------------------------------

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_BASE/$TIMESTAMP"

mkdir -p "$BACKUP_DIR"

for FILE in "${FILES[@]}"; do
    cp -a -- "$FILE" "$BACKUP_DIR/$(basename "$FILE")"
done

echo
echo -e "${GREEN}✓ Copias de seguridad creadas${RESET}"
echo -e "${GRAY}$BACKUP_DIR${RESET}"

# ------------------------------------------------------------
# ACTUALIZAR ARCHIVOS
# ------------------------------------------------------------

export NEW_RESELLER

python3 - <<'PY'
import os
import tempfile

new_name = os.environ["NEW_RESELLER"]

files = {
    "/etc/adm-lite/menu_credito": "normal",
    "/usr/bin/ejecutar/menu_credito": "normal",
    "/usr/bin/ejecutar/exito": "verified",
}

prepared = []

try:
    for path, mode in files.items():
        with open(path, "rb") as f:
            original = f.read()

        lines = original.splitlines(keepends=True)

        if not lines:
            raise RuntimeError(f"Archivo vacío: {path}")

        first = lines[0]
        ending = b""

        if first.endswith(b"\r\n"):
            ending = b"\r\n"
            first = first[:-2]
        elif first.endswith(b"\n") or first.endswith(b"\r"):
            ending = first[-1:]
            first = first[:-1]

        decoded = first.decode("utf-8")

        if mode == "verified":
            prefix = "Verified【 "

            if not decoded.startswith(prefix):
                raise RuntimeError(
                    f"Formato inesperado en {path}: {decoded}"
                )

            updated = prefix + new_name

        else:
            updated = new_name

        if "Morocho" not in decoded:
            raise RuntimeError(
                f"No se encontró el nombre anterior esperado en {path}"
            )

        lines[0] = updated.encode("utf-8") + ending
        new_content = b"".join(lines)

        st = os.stat(path)

        fd, temp_path = tempfile.mkstemp(
            prefix=".reseller-",
            dir=os.path.dirname(path)
        )

        with os.fdopen(fd, "wb") as f:
            f.write(new_content)
            f.flush()
            os.fsync(f.fileno())

        os.chmod(temp_path, st.st_mode & 0o7777)
        os.chown(temp_path, st.st_uid, st.st_gid)

        prepared.append((path, temp_path))

    # Aplicar los cambios después de preparar todos los archivos.
    for path, temp_path in prepared:
        os.replace(temp_path, path)
        print(f"ACTUALIZADO: {path}")

except Exception as error:
    for _, temp_path in prepared:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    raise SystemExit(f"ERROR: {error}")

PY

# ------------------------------------------------------------
# VERIFICACION
# ------------------------------------------------------------

echo
echo -e "${CYAN}VERIFICANDO CAMBIOS${RESET}"
echo

for FILE in "${FILES[@]}"; do
    echo -e "${BLUE}$FILE${RESET}"
    head -n 1 "$FILE"
done

echo
echo -e "${GREEN}RESELLER ACTUALIZADO CORRECTAMENTE${RESET}"
echo -e "${GRAY}No se reiniciaron servicios.${RESET}"
echo
echo -e "${CYAN}Backup: ${WHITE}$BACKUP_DIR${RESET}"
echo
