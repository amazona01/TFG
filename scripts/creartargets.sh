#!/bin/bash
set -euo pipefail

###############################################################################
#                       ░░ CONFIGURACIÓN BASE ░░                              #
###############################################################################

GVM_HOST="127.0.0.1"
GVM_PORT="9390"
GVM_USER="admin"
GVM_PASS="contraseña"

###############################################################################
#                       ░░ PARÁMETROS CLI ░░                                  #
###############################################################################

TARGET_NAME=""
TARGET_HOSTS=""
PORT_LIST_NAME="All TCP and Nmap top 100 UDP"

usage() {
  echo "Uso: $0 -n <nombre_target> -h <hosts> [-p <nombre_portlist>]"
  echo
  echo "  -n   Nombre del target"
  echo "  -h   Hosts/IPs (separados por coma)"
  echo "  -p   Nombre del Port List (opcional, por defecto: 'Full and fast')"
  exit 1
}

while getopts "n:h:p:" opt; do
  case $opt in
    n) TARGET_NAME="$OPTARG" ;;
    h) TARGET_HOSTS="$OPTARG" ;;
    p) PORT_LIST_NAME="$OPTARG" ;;
    *) usage ;;
  esac
done

[[ -z "$TARGET_NAME" || -z "$TARGET_HOSTS" ]] && usage

###############################################################################
#                            ░░ FUNCIONES ░░                                  #
###############################################################################

log() { printf '\e[1;32m[+] %s\e[0m\n' "$*"; }
err() { printf '\e[1;31m[!] %s\e[0m\n' "$*" >&2; }

gvm() {
  gvm-cli --gmp-username "$GVM_USER" --gmp-password "$GVM_PASS" tls \
    --hostname "$GVM_HOST" --port "$GVM_PORT" --xml "$1"
}

obtener_portlist_id() {
  local name="$1" xml id
  xml=$(gvm "<get_port_lists/>")
  id=$(echo "$xml" | xmlstarlet sel -t -m "//port_list[name='$name']" -v "@id" -n)
  [[ -n $id ]] || { err "❌ Port List '$name' no encontrada."; exit 1; }
  echo "$id"
}

crear_target() {
  local name="$1"
  local hosts="$2"
  local portlist_id="$3"

  log "Creando target '$name' con hosts $hosts y port list $portlist_id…"

  local xml
  xml=$(gvm "<create_target>
    <name>$name</name>
    <hosts>$hosts</hosts>
    <port_list id=\"$portlist_id\"/>
  </create_target>")

  echo "$xml" | xmlstarlet sel -t -v "//create_target_response/@id" 2>/dev/null
}

###############################################################################
#                                ░░ MAIN ░░                                   #
###############################################################################

for bin in gvm-cli xmlstarlet; do
  command -v "$bin" >/dev/null || { err "$bin no está instalado."; exit 1; }
done

PORT_LIST_ID=$(obtener_portlist_id "$PORT_LIST_NAME")
[[ -n $PORT_LIST_ID ]] || { err "Port list '$PORT_LIST_NAME' no encontrada."; exit 1; }

TARGET_ID=$(crear_target "$TARGET_NAME" "$TARGET_HOSTS" "$PORT_LIST_ID")
[[ -n $TARGET_ID ]] || { err "Fallo al crear el target."; exit 1; }

log "✔ Target creado con ID: $TARGET_ID"
