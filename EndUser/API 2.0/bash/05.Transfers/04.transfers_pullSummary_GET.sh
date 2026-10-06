#!/bin/bash
# ==============================================================================
# Script Name: 04.transfers_pullSummary_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads how a pull is getting on, using the
# `/transfers/pullSummary/{operationIndex}` endpoint: how many files in all,
# how many succeeded, failed, are in retry, in progress or on hold.
#
# Usage:
# ./04.transfers_pullSummary_GET.sh OPERATION_INDEX
#
#   OPERATION_INDEX  the operationIndex the pull was started with (see
#                    03.transfers_operations_POST_pull.sh)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - Pulls that share an operationIndex are counted together.
# - Confirmed directly: an operationIndex no pull used answers 200 with every
#   count 0, not 404.
# - Exits 1 when a file failed for good, 3 while files are still in retry, in
#   progress or on hold, so a script can wait on it.
# - Requires `jq`.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

OPERATION_INDEX="$1"
if [ -z "${OPERATION_INDEX}" ]; then
    printf "Usage: ./04.transfers_pullSummary_GET.sh OPERATION_INDEX\n"
    exit 2
fi
if [ ! -f "${COOKIE}" ]; then
    printf "There is no session. Run 01.Authenticate/01.myself_POST.sh first.\n"
    exit 1
fi

ENCODED=$(printf '%s' "${OPERATION_INDEX}" | jq -sRr '@uri')
RESPONSE=$(curl -s -k -b "${COOKIE}" -X GET "${ST_URL}/transfers/pullSummary/${ENCODED}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"

if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the pull summary (HTTP %s):\n%s\n" "${HTTP_CODE}" "${BODY}"
    exit 1
fi
printf '%s' "${BODY}" | jq -r '"\(.totalCount) file(s): \(.successful) successful, \(.failed) failed, \(.inRetry) in retry, \(.inProgress) in progress, \(.onHold) on hold"'
[ "$(printf '%s' "${BODY}" | jq '.failed')" -gt 0 ] && exit 1
[ "$(printf '%s' "${BODY}" | jq '.inRetry + .inProgress + .onHold')" -gt 0 ] && exit 3
exit 0
