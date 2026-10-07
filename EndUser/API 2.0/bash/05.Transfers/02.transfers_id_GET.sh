#!/bin/bash
# ==============================================================================
# Script Name: 02.transfers_id_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads the details of one transfer, using the `/transfers/{id}`
# endpoint: the transfer type and site, the real file path, the success or
# error message, and the protocol commands.
#
# Usage:
# ./02.transfers_id_GET.sh [TRANSFER_ID]
#
#   TRANSFER_ID  a transferId, as 01.transfers_GET.sh lists them (default: the
#                user's latest transfer)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - The id is base64 of 'Id [transferStatusId=..., transferStartTime=...]'.
#   Take it as the list gives it; it is used in the path as it is.
# - Requires `jq`, which prints the summary.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

TRANSFER_ID="$1"
if [ ! -f "${COOKIE}" ]; then
    printf "There is no session. Run 01.Authenticate/01.myself_POST.sh first.\n"
    exit 1
fi

if [ -z "${TRANSFER_ID}" ]; then
    TRANSFER_ID=$(curl -s -k -b "${COOKIE}" -X GET "${ST_URL}/transfers?limit=1" \
      -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.[0].transferId // empty')
    if [ -z "${TRANSFER_ID}" ]; then
        printf "There are no transfers yet.\n"
        exit 1
    fi
fi

RESPONSE=$(curl -s -k -b "${COOKIE}" -X GET "${ST_URL}/transfers/${TRANSFER_ID}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"

if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the transfer (HTTP %s):\n%s\n" "${HTTP_CODE}" "${BODY}"
    exit 1
fi
printf '%s\n' "${BODY}"
printf "\nIn short:\n"
printf '%s' "${BODY}" | jq -r '
  "  \(.transferType) of \(.file), \(.size) bytes, \(.status)",
  "  site \(.transferSite), protocol \(.protocol), mode \(.mode)",
  "  real file \(.realFile // "")",
  "  \(.errorMessage // .successMessage // "")"'
