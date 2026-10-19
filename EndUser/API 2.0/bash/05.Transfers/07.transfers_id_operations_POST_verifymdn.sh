#!/bin/bash
# ==============================================================================
# Script Name: 07.transfers_id_operations_POST_verifymdn.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script verifies the receipt (the MDN) of an AS2 transfer, using the
# `/transfers/{id}/operations?operation=verifymdn` endpoint: the integrity
# check and the signature check of the receipt.
#
# Usage:
# ./07.transfers_id_operations_POST_verifymdn.sh TRANSFER_ID
#
#   TRANSFER_ID  the transferId of an AS2 transfer, as 01.transfers_GET.sh lists
#                them (for example with protocol=as2)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
# - It checks for an active session first and, if there is none, logs in with
#   01.Authenticate/01.myself_POST.sh and then carries on.
# - verifymdn is the only operation this endpoint has.
# - Not confirmed on a real server: it needs an AS2 transfer with a receipt,
#   and AS2 was not enabled on the server these examples were tested against.
# - Requires `jq`, which prints the result.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${ST_ENDUSER_LOCAL_VARIABLES:-${SCRIPT_DIR}/../set_variables.local.sh}" ||
    { echo "Copy set_variables.local.example.sh to set_variables.local.sh and fill it in."; exit 1; }
export ST_URL="${ST_URL:-https://${ST_SERVER}:${ST_PORT}/api/v2.0}"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
source "${SCRIPT_DIR}/../ensure_session.sh"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

TRANSFER_ID="$1"
if [ -z "${TRANSFER_ID}" ]; then
    printf "Usage: ./07.transfers_id_operations_POST_verifymdn.sh TRANSFER_ID\n"
    exit 2
fi
st_ensure_session

printf "Verifying the receipt of transfer %s...\n" "${TRANSFER_ID}"
RESPONSE=$(curl -s -k -b "${COOKIE}" -X POST "${ST_URL}/transfers/${TRANSFER_ID}/operations?operation=verifymdn" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"

if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not verify the receipt (HTTP %s):\n%s\n" "${HTTP_CODE}" "${BODY}"
    exit 1
fi
printf '%s' "${BODY}" | jq -r '"File integrity: \(.fileIntegrityResult)\nSignature:      \(.signatureResult)"'
