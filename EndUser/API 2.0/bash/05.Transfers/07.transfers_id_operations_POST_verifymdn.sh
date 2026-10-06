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
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - verifymdn is the only operation this endpoint has.
# - Not confirmed on a real server: it needs an AS2 transfer with a receipt,
#   and AS2 was not enabled on the server these examples were tested against.
# - Requires `jq`, which prints the result.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

TRANSFER_ID="$1"
if [ -z "${TRANSFER_ID}" ]; then
    printf "Usage: ./07.transfers_id_operations_POST_verifymdn.sh TRANSFER_ID\n"
    exit 2
fi
if [ ! -f "${COOKIE}" ]; then
    printf "There is no session. Run 01.Authenticate/01.myself_POST.sh first.\n"
    exit 1
fi

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
