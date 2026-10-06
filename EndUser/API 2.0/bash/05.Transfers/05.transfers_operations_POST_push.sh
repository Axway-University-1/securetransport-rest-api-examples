#!/bin/bash
# ==============================================================================
# Script Name: 05.transfers_operations_POST_push.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script pushes a file from the home folder to one of the user's transfer
# sites, on demand, using the `/transfers/operations` endpoint with the push
# operation. It demonstrates:
# - The body: the operation, and its data - the file, the site, and an
#   operationIndex to find the transfer by afterwards
# - A synchronous push, which answers once it is done, or an asynchronous one,
#   which answers at once and is retried on failure
# - Finding the transfer in the log by its operationIndex
#
# Usage:
# ./05.transfers_operations_POST_push.sh SITE FILE [async]
#
#   SITE   the name of one of the user's transfer sites
#   FILE   the file to push, relative to the home folder
#   async  push asynchronously (default: synchronously)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - The site belongs to the user's account; an administrator creates it.
# - Confirmed directly: a synchronous push answers 200, an asynchronous one
#   202, and the file arrives at the site's upload folder.
# - A synchronous push is not retried when it fails. An asynchronous one is,
#   as many times as the EventQueue.maxRetryCount option says.
# - Requires `jq`, which builds the body.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

SITE="$1"
FILE="/${2#/}"
ASYNC=false
[ "$3" = "async" ] && ASYNC=true
OPERATION_INDEX="eu-push-$(date +%s)"
if [ -z "${SITE}" ] || [ "${FILE}" = "/" ]; then
    printf "Usage: ./05.transfers_operations_POST_push.sh SITE FILE [async]\n"
    exit 2
fi
if [ ! -f "${COOKIE}" ]; then
    printf "There is no session. Run 01.Authenticate/01.myself_POST.sh first.\n"
    exit 1
fi

BODY=$(jq -n --arg site "${SITE}" --arg file "${FILE}" --arg index "${OPERATION_INDEX}" --argjson async "${ASYNC}" \
  '{operation: "push",
    data: {file: $file, site: $site, operationIndex: $index, asynchronousCall: $async}}')

printf "Pushing %s with the site %s, as %s...\n" "${FILE}" "${SITE}" "${OPERATION_INDEX}"
RESPONSE=$(curl -s -k -b "${COOKIE}" -X POST "${ST_URL}/transfers/operations" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf '%s\nHTTP %s\n' "${RESPONSE%$'\n'*}" "${HTTP_CODE}"
case "${HTTP_CODE}" in
    2*) ;;
    *) exit 1 ;;
esac

sleep 2
printf "The transfer, in the log:\n"
curl -s -k -G -b "${COOKIE}" -X GET "${ST_URL}/transfers" --data-urlencode "operationIndex=${OPERATION_INDEX}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '.[] | "  \(.startTime)  \(.direction)  \(.status)  \(.filename)"'
