#!/usr/bin/env bash
# Exporta el último reporte de un task de Greenbone y lo importa en DefectDojo
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
TASK_REF="Escaneo de pruebas"   # UUID o nombre

######## DefectDojo
DEFECTDOJO_URL="http://localhost:80"
API_TOKEN="token defectdojo"

PRODUCT_ID="1"          # ID del producto en Dojo
ENGAGEMENT_ID=""        # vacío ⇒ se crea engagement nuevo
SCAN_TYPE="OpenVAS Parser"

######## Archivo de salida
OUT_FILE="reporte_greenbone.xml"

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

crear_engagement() {
  echo "[+] Creando engagement nuevo…" >&2
  curl -s -X POST "${DEFECTDOJO_URL}/api/v2/engagements/" \
       -H "Authorization: Token ${API_TOKEN}" \
       -H "Content-Type: application/json" \
       -d @- <<EOF 2>/dev/null | jq -r '.id'
{
  "name": "Greenbone Scan $(date +%F)",
  "product": ${PRODUCT_ID},
  "target_start": "$(date +%F)",
  "target_end": "$(date +%F)",
  "status": "In Progress"
}
EOF
}

importar_dojo() {
  local engagement_id=$1
  log "Subiendo reporte a DefectDojo (engagement $engagement_id)…"
  curl -s -X POST "${DEFECTDOJO_URL}/api/v2/import-scan/" \
       -H "Authorization: Token ${API_TOKEN}" \
       -F "engagement=${engagement_id}" \
       -F "scan_type=${SCAN_TYPE}" \
       -F "file=@${OUT_FILE}" \
       -F "skip_duplicates=true" \
       -F "auto_create_context=true" | jq -r '.message // .id'
}

###############################################################################
#                                  MAIN                                       #
###############################################################################

for bin in gvm-cli xmlstarlet jq curl; do
  command -v "$bin" >/dev/null || { err "$bin no instalado."; exit 1; }
done

log "Buscando task '${TASK_REF}'…"
TASK_ID=$( [[ $TASK_REF =~ ^[0-9a-f-]{36}$ ]] && echo "$TASK_REF" || obtener_task_id )
[[ -n $TASK_ID ]] || { err "Task no encontrado."; exit 1; }
log "Task ID: $TASK_ID"

log "Obteniendo último reporte…"
REPORT_ID=$(obtener_last_report_id "$TASK_ID")
[[ -n $REPORT_ID ]] || { err "El task todavía no tiene reportes."; exit 1; }
log "Reporte ID: $REPORT_ID"

log "Descargando reporte a ${OUT_FILE}…"
gvm "<get_reports report_id='$REPORT_ID' details='1'/>" > "$OUT_FILE"
log "Reporte descargado."

if [[ -z $ENGAGEMENT_ID ]]; then
  ENGAGEMENT_ID=$(crear_engagement)
  log "Engagement creado con ID=${ENGAGEMENT_ID}"
fi

importar_dojo "$ENGAGEMENT_ID"
log "✔ Proceso completado."
