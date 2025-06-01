#!/bin/bash
set -euo pipefail

###############################################################################
#                       ░░ CONFIGURACIÓN RÁPIDA ░░                            #
###############################################################################

######## Greenbone (GMP)
GVM_HOST="127.0.0.1"
GVM_PORT="9390"
GVM_USER="admin"
GVM_PASS="contraseña"

# ID o nombre exacto del task
TASK_REF=""   

######## DefectDojo
DEFECTDOJO_URL="http://localhost:80"
API_TOKEN="token_de_defectdojo"

PRODUCT_ID="1"          # ID del producto en Dojo
ENGAGEMENT_ID=""        # vacío ⇒ se busca o crea nuevo engagement
SCAN_TYPE="OpenVAS Parser"

######## Carpeta de salida
OUT_DIR="/var/log/reportes"
mkdir -p "$OUT_DIR"

###############################################################################
#                       ░░ FUNCIONES AUXILIARES ░░                            #
###############################################################################

log() { printf '\e[1;32m[+] %s\e[0m\n' "$*"; }
err() { printf '\e[1;31m[!] %s\e[0m\n' "$*" >&2; }

gvm() {
  gvm-cli --gmp-username "$GVM_USER" --gmp-password "$GVM_PASS" tls \
    --hostname "$GVM_HOST" --port "$GVM_PORT" --xml "$1"
}

obtener_task_id() {
  local xml
  xml=$(gvm "<get_tasks filter=\"name=${TASK_REF}\"/>")
  echo "$xml" | xmlstarlet sel -t -v "//task/@id" 2>/dev/null
}

obtener_last_report_id() {
  local task_id=$1 xml
  xml=$(gvm "<get_tasks task_id=\"$task_id\" details=\"1\"/>")
  echo "$xml" | xmlstarlet sel -t -v "//report[1]/@id" 2>/dev/null
}

urlencode() {
  local data
  data=$(jq -rn --arg v "$1" '$v|@uri')
  echo "$data"
}

# Obtener engagement por nombre exacto (Devuelve ID o vacío)
obtener_engagement_id() {
  curl -s -H "Authorization: Token ${API_TOKEN}" \
       "${DEFECTDOJO_URL}/api/v2/engagements/?name=$(urlencode "$ENGAGEMENT_NAME")" \
       | jq -r '.results[0].id // empty'
}

crear_engagement() {
  echo "[+] Creando engagement '${ENGAGEMENT_NAME}'…" >&2
  curl -s -X POST "${DEFECTDOJO_URL}/api/v2/engagements/" \
       -H "Authorization: Token ${API_TOKEN}" \
       -H "Content-Type: application/json" \
       -d @- <<EOF 2>/dev/null | jq -r '.id'
{
  "name": "${ENGAGEMENT_NAME}",
  "product": ${PRODUCT_ID},
  "target_start": "$(date +%F)",
  "target_end": "$(date -d "$(date +%F) + 25 days" +%F)",
  "status": "In Progress"
}
EOF
}

importar_dojo() {
  local engagement_id=$1
  log "Subiendo reporte a DefectDojo (engagement $engagement_id)…"
  response=$(curl -s -X POST "${DEFECTDOJO_URL}/api/v2/import-scan/" \
       -H "Authorization: Token ${API_TOKEN}" \
       -F "engagement=${engagement_id}" \
       -F "scan_type=${SCAN_TYPE}" \
       -F "file=@${OUT_FILE}" \
       -F "skip_duplicates=true" \
       -F "auto_create_context=true")

  # Extraer mensaje o id, si es error conocido no mostrar nada
  msg=$(echo "$response" | jq -r '.message // .id' 2>/dev/null || true)
  if [[ "$msg" == "Internal server error, check logs for details" ]]; then
    # no mostrar nada ni error
    :
  else
    echo "$msg"
  fi
}

###############################################################################
#                                  MAIN                                       #
###############################################################################

for bin in gvm-cli xmlstarlet jq curl; do
  command -v "$bin" >/dev/null || { err "$bin no instalado."; exit 1; }
done

# Parsear argumentos
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)
      shift
      TASK_REF="$1"
      ;;
    --engagement)
      shift
      ENGAGEMENT_NAME="$1"
      ;;
    *)
      err "Argumento desconocido: $1"
      exit 1
      ;;
  esac
  shift
done

if [[ -z $TASK_REF ]]; then
  err "Debe indicar un task con --task"
  exit 1
fi

log "Buscando Task '${TASK_REF}'…"
TASK_ID=$( [[ $TASK_REF =~ ^[0-9a-f-]{36}$ ]] && echo "$TASK_REF" || obtener_task_id )
[[ -n $TASK_ID ]] || { err "Task no encontrado."; exit 1; }
log "Task ID: $TASK_ID"

log "Obteniendo último reporte…"
REPORT_ID=$(obtener_last_report_id "$TASK_ID")
[[ -n $REPORT_ID ]] || { err "El task todavía no tiene reportes."; exit 1; }
log "Reporte ID: $REPORT_ID"

# Mes actual en español con primera letra mayúscula
MES_ACTUAL=$(LC_TIME=es_ES.UTF-8 date +%B)
MES_ACTUAL="${MES_ACTUAL^}"

# Nombre de engagement: si no se pasó con --engagement se crea uno con formato "Greenbone <Mes>"
if [[ -z ${ENGAGEMENT_NAME-} ]]; then
  ENGAGEMENT_NAME="Greenbone ${MES_ACTUAL}"
fi

# Nombre de archivo de salida
# Cambia espacios por guiones bajos y elimina caracteres especiales para evitar problemas
TASK_CLEAN=$(echo "$TASK_REF" | tr ' ' '_' | tr -cd '[:alnum:]_-')
FECHA=$(date +%d-%m)
OUT_FILE="${OUT_DIR}/reporte-${TASK_CLEAN}__${FECHA}.xml"

log "Descargando reporte a ${OUT_FILE}…"
gvm "<get_reports report_id='$REPORT_ID' details='1'/>" > "$OUT_FILE"
log "Reporte descargado."

if [[ -z $ENGAGEMENT_ID ]]; then
  log "Buscando si ya existe engagement '${ENGAGEMENT_NAME}'…"
  ENGAGEMENT_ID=$(obtener_engagement_id)
fi

if [[ -z $ENGAGEMENT_ID ]]; then
  ENGAGEMENT_ID=$(crear_engagement)
  log "Engagement creado con ID=${ENGAGEMENT_ID}"
else
  log "Engagement ya existente con ID=${ENGAGEMENT_ID}"
fi

importar_dojo "$ENGAGEMENT_ID"

log "✔ Proceso completado."




