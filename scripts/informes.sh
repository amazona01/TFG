#!/bin/bash

# Variables para DefectDojo
DEFECTDOJO_URL="http://localhost:80"
API_TOKEN="d13784fc2d08faf7d738b33d1fa0d30e197b454b"

PRODUCT_ID="1"          # ID del producto en Dojo
ENGAGEMENT_ID=""        # vacío ⇒ se busca o crea nuevo engagement
SCAN_TYPE="OpenVAS Parser"

# Definir nombre del archivo de salida con el nuevo formato
DATE=$(date +%Y-%m-%d)   # Fecha actual en formato YYYY-MM-DD
output_file="/var/log/reportes/reporte-${TASK_NAME}_${DATE}.xml"


# Funciones
log() { printf '\e[1;32m[+] %s\e[0m\n' "$*"; }
err() { printf '\e[1;31m[!] %s\e[0m\n' "$*" >&2; }
usage() {
    echo "Uso: $0 --task <nombre_de_la_tarea>"
    exit 1
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

#   Importar reporte a DefectDojo
importar_dojo() {
  local engagement_id=$1
  log "Subiendo reporte a DefectDojo (engagement $engagement_id)…"
  response=$(curl -s -X POST "${DEFECTDOJO_URL}/api/v2/import-scan/" \
       -H "Authorization: Token ${API_TOKEN}" \
       -F "engagement=${engagement_id}" \
       -F "scan_type=${SCAN_TYPE}" \
       -F "file=@${output_file}" \
       -F "skip_duplicates=true" \
       -F "auto_create_context=true")

  # Extraer mensaje o id, si es un falso positivo no mostrar nada
  msg=$(echo "$response" | jq -r '.message // .id' 2>/dev/null || true)
  if [[ "$msg" == "Internal server error, check logs for details" ]]; then
    :
  fi
}

# Parsear argumentos
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --task)
            TASK_NAME="$2"
            shift 2
            ;;
        *)
            echo "❌ Argumento no reconocido: $1"
            usage
            ;;
    esac
done

# Verificar que TASK_NAME fue proporcionado
if [ -z "$TASK_NAME" ]; then
    echo "❌ Debes proporcionar el nombre de la tarea con --task"
    usage
fi

# Exportar la variable de entorno
export TASK_NAME


echo "🔄 Exportando tarea '$TASK_NAME' a archivo '$output_file'..."

# Ejecutar el script para descargar el informe con gvm-script
gvm-script \
    --gmp-username admin \
    --gmp-password admin \
    tls --hostname localhost informes.py > "$output_file"

# Verificar si el archivo fue creado correctamente
if [ -f "$output_file" ]; then
    echo "✅ Informe exportado correctamente: $output_file"
else
    echo "❌ Error al exportar el informe."
fi
# Mes actual 
MES_ACTUAL=$(LC_TIME=es_ES.UTF-8 date +%B)
MES_ACTUAL="${MES_ACTUAL^}"

# Nombre de engagement: si no se pasó con --engagement se crea uno con formato "Greenbone <Mes>"
if [[ -z ${ENGAGEMENT_NAME-} ]]; then
  ENGAGEMENT_NAME="Greenbone ${MES_ACTUAL}"
fi

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













