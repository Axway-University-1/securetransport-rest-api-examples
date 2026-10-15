#!/bin/bash
# ==============================================================================
# Script Name: 03.transfers_id_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Follows one transfer. It takes the newest transfer from the list, and reads it again by its id: GET /transfers/<id>. The id is long base64 text, so it is encoded before it goes in the URL.
#
# Usage:
# ./03.transfers_id_GET.sh
#
# Risk: read
#
# Notes:
# - Copied from EndUser/API 2.0/bash/05.Transfers/02.transfers_id_GET.sh.
# - The list and the single transfer name some fields differently (the list has filename and direction, the single transfer has file and transferType): read what the call you use returns.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

ID=$(curl -k -s -G -b "${JAR}" -X GET "${ST_URL}/transfers" --data-urlencode "limit=1" -H "accept: application/json" -H "Referer: ${REFERER}" | jq -r '.[0].transferId // empty')
if [ -z "${ID}" ]; then
    echo "The account has no transfer yet. Run 03-files-and-folders first."
    exit 2
fi
ENC=$(jq -rn --arg v "${ID}" '$v | @uri')
result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/transfers/${ENC}" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "HTTP ${code}"
[[ "${code}" == 200 ]] || { st_refused "${code}"; exit 1; }
echo "${result%???}" | jq -r '"  file      \(.file)", "  status    \(.status)", "  type      \(.transferType)", "  protocol  \(.protocol)", "  started   \(.startTime)", "  folder    \(.accountFolder)", "  transfer  \(.transferId)"' 
