#!/bin/bash
# ==============================================================================
# Script Name: 03.transfers_operations_POST_pull.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script pulls files from one of the user's transfer sites, on demand,
# using the `/transfers/operations` endpoint with the pull operation. It
# demonstrates:
# - The body: the operation, and its data - the site, the folder to pull into,
#   and an operationIndex to find the transfers by afterwards
# - awaitResult true: the call waits until the pull has started, and the link
#   it answers with carries expectedFilesCount
# - Following the pull with /transfers/pullSummary/{operationIndex}
#
# Usage:
# ./03.transfers_operations_POST_pull.sh SITE FOLDER [OPERATION_INDEX]
#
#   SITE             the name of one of the user's transfer sites
#   FOLDER           where the files land, relative to the home folder
#   OPERATION_INDEX  a name for this pull (default: eu-pull-<seconds since 1970>)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - The site belongs to the user's account; an administrator creates it (see
#   Admin/API 2.0/bash/06.TransferSites/02.sites_POST_ssh.sh).
# - Confirmed directly: with awaitResult true it answers 200, and the files
#   are in FOLDER and counted in the pull summary a few seconds later.
#   awaitResult replaces the older asynchronousCall.
# - transferProfile is needed for a PeSIT site only. customProperties, a map of
#   strings, reach the site as ${DXAGENT_TRANSFERSAPI_<KEY>}.
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
FOLDER="/${2#/}"
OPERATION_INDEX="${3:-eu-pull-$(date +%s)}"
if [ -z "${SITE}" ] || [ "${FOLDER}" = "/" ]; then
    printf "Usage: ./03.transfers_operations_POST_pull.sh SITE FOLDER [OPERATION_INDEX]\n"
    exit 2
fi
if [ ! -f "${COOKIE}" ]; then
    printf "There is no session. Run 01.Authenticate/01.myself_POST.sh first.\n"
    exit 1
fi

BODY=$(jq -n --arg site "${SITE}" --arg folder "${FOLDER}" --arg index "${OPERATION_INDEX}" \
  '{operation: "pull",
    data: {site: $site, destinationDirectory: $folder, operationIndex: $index, awaitResult: true}}')

printf "Pulling with the site %s into %s, as %s...\n" "${SITE}" "${FOLDER}" "${OPERATION_INDEX}"
RESPONSE=$(curl -s -k -b "${COOKIE}" -X POST "${ST_URL}/transfers/operations" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"
printf '%s\nHTTP %s\n' "${BODY}" "${HTTP_CODE}"
case "${HTTP_CODE}" in
    2*) ;;
    *) exit 1 ;;
esac

EXPECTED=$(printf '%s' "${BODY}" | jq -r '.link // ""' | sed -n 's/.*expectedFilesCount=\([0-9]*\).*/\1/p')
printf "Files expected: %s\n" "${EXPECTED:-not reported}"

sleep 3
printf "The pull summary of %s:\n" "${OPERATION_INDEX}"
curl -s -k -b "${COOKIE}" -X GET "${ST_URL}/transfers/pullSummary/${OPERATION_INDEX}" \
  -H "accept: application/json" -H "${REFERER_HEADER}"
printf "\n"
