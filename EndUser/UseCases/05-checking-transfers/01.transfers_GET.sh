#!/bin/bash
# ==============================================================================
# Script Name: 01.transfers_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# What happened to my files? GET /transfers lists the transfers of the account, newest first, with a name, direction, protocol and status. This prints the latest few, one line each. Every upload and download of the other use cases shows up here.
#
# Usage:
# ./01.transfers_GET.sh [LIMIT]
#
# Risk: read
#
# Notes:
# - Copied from EndUser/API 2.0/bash/05.Transfers/01.transfers_GET.sh.
# - LIMIT is how many to ask for (default 5); without a limit the server sends a page of 100, which is not a cap (limit=500 returned 105); a longer history is read with limit and offset.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
LIMIT="${1:-5}"
[[ "${LIMIT}" =~ ^[1-9][0-9]*$ ]] || { echo "LIMIT must be a whole number above 0: ${LIMIT}"; exit 2; }
st_session

result=$(curl -k -s -G -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/transfers" \
         --data-urlencode "limit=${LIMIT}" --data-urlencode "offset=0" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "HTTP ${code}"
[[ "${code}" == 200 ]] || { st_refused "${code}"; exit 1; }
echo "${result%???}" | jq -r ".[] | ${ROW}"
