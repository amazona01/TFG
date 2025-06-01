#!/bin/bash

# Variables por defecto
SCAN_CONFIG_NAME="Full and fast"
USERNAME="admin"
PASSWORD="contraseña"
HOST="127.0.0.1"
PORT="9390"

usage() {
  echo "Uso: $0 -n <nombre_task> -t <nombre_target>"
  exit 1
}

# Parseo de argumentos
while getopts "n:t:" opt; do
  case $opt in
    n) TASK_NAME="$OPTARG" ;;
    t) TARGET_NAME="$OPTARG" ;;
    *) usage ;;
  esac
done

if [ -z "$TASK_NAME" ] || [ -z "$TARGET_NAME" ]; then
  usage
fi

# Obtener Scan Config ID por nombre
SCAN_CONFIG_ID=$(sudo -u mazon gvm-cli --gmp-username "$USERNAME" --gmp-password "$PASSWORD" tls --hostname "$HOST" --port "$PORT" --xml "<get_configs/>" \
| xmllint --xpath "string(//config[name='$SCAN_CONFIG_NAME']/@id)" -)

if [ -z "$SCAN_CONFIG_ID" ]; then
  echo "❌ No se encontró Scan Config con nombre '$SCAN_CONFIG_NAME'"
  exit 1
fi

# Obtener Target ID por nombre
TARGET_ID=$(sudo -u mazon gvm-cli --gmp-username "$USERNAME" --gmp-password "$PASSWORD" tls --hostname "$HOST" --port "$PORT" --xml "<get_targets/>" \
| xmllint --xpath "string(//target[name='$TARGET_NAME']/@id)" -)

if [ -z "$TARGET_ID" ]; then
  echo "❌ No se encontró Target con nombre '$TARGET_NAME'"
  exit 1
fi

# Crear el Task
CREATE_TASK_XML="<create_task>
  <name>$TASK_NAME</name>
  <config id=\"$SCAN_CONFIG_ID\"/>
  <target id=\"$TARGET_ID\"/>
</create_task>"

RESPONSE=$(sudo -u mazon gvm-cli --gmp-username "$USERNAME" --gmp-password "$PASSWORD" tls --hostname "$HOST" --port "$PORT" --xml "$CREATE_TASK_XML")

# Comprobar si la creación fue exitosa
if echo "$RESPONSE" | grep -q 'status="201"'; then
  echo "✔  Task '$TASK_NAME' creado correctamente."
else
  echo "❌ Error creando el Task:"
  echo "$RESPONSE"
fi