#!/bin/bash
# ==============================================================================
# Script Name: 13.files_GET_result.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Shows what the pull and the push left behind, using the End User API
# `GET /files/{folder}` endpoint. It lists the files in each of the folders in
# AR_CHECK_FOLDERS, as the test account sees them. The last folder, delivered, is
# where the push puts the files, so it waits for that one to fill up.
#
# Usage:
# ./13.files_GET_result.sh
#
# Risk: read
#
# Notes:
# - Run it after 12.files_PUT_triggerfile.sh. The pull and the route run
#   asynchronously, so the push can take a few seconds to arrive. The script
#   waits up to AR_WAIT_SECONDS for the files in the last folder.
# - Needs settings.local.sh with AR_ACCOUNT_PASSWORD. See settings.sh.
# - Requires `jq`, which reads the listing.
# - Exits 1 if nothing arrived in the last folder, or if the server refused a listing.
# - This only shows files. The transfer log shows the route runs themselves.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
source "${SCRIPT_DIR}/settings.sh"

if [ -z "${AR_ACCOUNT_PASSWORD}" ]; then
    printf "AR_ACCOUNT_PASSWORD is not set. Copy settings.local.example.sh to settings.local.sh and choose one.\n"
    exit 1
fi

# Print the regular files in a folder, and set FILE_COUNT and LIST_RC (0 unless the
# server refused the listing)
list_folder() {
    ar_enduser_call GET "files/$1" ""
    LIST_RC=$?
    FILE_COUNT=$(printf '%s' "${AR_EU_BODY}" | jq '[(.files // [])[] | select(.isRegularFile)] | length' 2>/dev/null)
    FILE_COUNT=${FILE_COUNT:-0}
}

ar_enduser_login || exit 1

LAST_FOLDER=$(printf '%s\n' ${AR_CHECK_FOLDERS} | tail -n 1)

# The push is asynchronous: give the last folder time to fill up
waited=0
list_folder "${LAST_FOLDER}"
while [ "${FILE_COUNT}" -eq 0 ] && [ "${waited}" -lt "${AR_WAIT_SECONDS}" ]; do
    printf "Nothing in %s yet. Waiting...\n" "${LAST_FOLDER}"
    sleep 3
    waited=$((waited + 3))
    list_folder "${LAST_FOLDER}"
done

LISTINGS_REFUSED=0
for folder in ${AR_CHECK_FOLDERS}; do
    list_folder "${folder}"
    printf "\n%s: %s file(s)\n" "${folder}" "${FILE_COUNT}"
    if [ "${LIST_RC}" -ne 0 ]; then
        printf "The listing of %s was refused (HTTP %s).\n" "${folder}" "${AR_EU_CODE}"
        LISTINGS_REFUSED=1
    fi
    printf '%s' "${AR_EU_BODY}" | jq -r '(.files // [])[] | select(.isRegularFile) | "    " + .fileName + "  (" + (.size | tostring) + " bytes)"' 2>/dev/null
    [ "${folder}" = "${LAST_FOLDER}" ] && LAST_COUNT="${FILE_COUNT}"
done

ar_enduser_logout

[ "${LISTINGS_REFUSED}" -eq 0 ] && [ "${LAST_COUNT}" -gt 0 ]
