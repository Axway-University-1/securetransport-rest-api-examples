#!/bin/bash
# ==============================================================================
# Script Name: 01.transfers_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads the user's own transfer log, using the `/transfers`
# endpoint. It demonstrates the filters:
# - The latest transfers, a page at a time (limit, offset)
# - Today's failed and aborted ones: a repeated status, and startTimeAfter in
#   RFC 2822
# - The outgoing ones the server started, over SSH: direction, actionBy,
#   protocol
#
# Usage:
# ./01.transfers_GET.sh [LIMIT]
#
#   LIMIT  how many transfers each listing shows (default 10)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - Only the logged-in user's own transfers are listed.
# - The answer is a plain JSON array, not a {result: [...]} envelope.
# - status, protocol, application and operationIndex take several values, each
#   repeated: status=Failed&status=Aborted (confirmed directly).
# - Each entry's transferId is what 02.transfers_id_GET.sh takes.
# - Midnight is worked out with BSD date (macOS) or GNU date (Linux).
# - Requires `jq`, which prints one transfer per line.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

LIMIT="${1:-10}"
if [ ! -f "${COOKIE}" ]; then
    printf "There is no session. Run 01.Authenticate/01.myself_POST.sh first.\n"
    exit 1
fi

# Today's midnight, in RFC 2822
if date -v0H >/dev/null 2>&1; then
    TODAY=$(date -v0H -v0M -v0S -R)
else
    TODAY=$(date -d "today 00:00:00" -R)
fi
LINE='.[] | "  \(.startTime)  \(.direction)  \(.status)  \(.protocol)  \(.filename)"'

printf "The latest %s transfers:\n" "${LIMIT}"
curl -s -k -G -b "${COOKIE}" -X GET "${ST_URL}/transfers" \
  --data-urlencode "limit=${LIMIT}" --data-urlencode "offset=0" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r "${LINE}"

printf "\nToday's failed and aborted transfers:\n"
curl -s -k -G -b "${COOKIE}" -X GET "${ST_URL}/transfers" \
  --data-urlencode "status=Failed" --data-urlencode "status=Aborted" \
  --data-urlencode "startTimeAfter=${TODAY}" --data-urlencode "limit=${LIMIT}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r "${LINE}"

printf "\nThe outgoing transfers the server started, over SSH:\n"
curl -s -k -G -b "${COOKIE}" -X GET "${ST_URL}/transfers" \
  --data-urlencode "direction=Outgoing" --data-urlencode "actionBy=Server" \
  --data-urlencode "protocol=ssh" --data-urlencode "limit=${LIMIT}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r "${LINE}"
