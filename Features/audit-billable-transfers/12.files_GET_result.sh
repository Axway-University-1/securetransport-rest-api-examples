#!/bin/bash
# ==============================================================================
# Script Name: 12.files_GET_result.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Shows what each scenario left behind, using the End User API
# `GET /files/{folder}` endpoint: the six subscription/sN folders (what was
# pulled) and both delivered folders (what was pushed). Waits for delivered-1 to
# have something in it before listing, since the pushes are asynchronous.
#
# Usage:
# ./12.files_GET_result.sh
#
# Notes:
# - Run it after 11.transfers_pull_POST.sh.
# - Needs settings.local.sh with BT_ACCOUNT_PASSWORD. See settings.sh.
# - Requires `jq`.
# - This only shows files. 00.run_all.sh's own analysis step is about the
#   billable counts, not this listing; this is a sanity check along the way.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
source "${SCRIPT_DIR}/settings.sh"

if [ -z "${BT_ACCOUNT_PASSWORD}" ]; then
    printf "BT_ACCOUNT_PASSWORD is not set. Copy settings.local.example.sh to settings.local.sh and choose one.\n"
    exit 1
fi

# Print the regular files in a folder, and set FILE_COUNT
list_folder() {
    ar_enduser_call GET "files$1" ""
    FILE_COUNT=$(printf '%s' "${AR_EU_BODY}" | jq '[(.files // [])[] | select(.isRegularFile)] | length' 2>/dev/null)
    FILE_COUNT=${FILE_COUNT:-0}
}

ar_enduser_login || exit 1

# The first push (scenarios 2.2 to 2.4) is asynchronous: give it time to arrive
waited=0
list_folder "${BT_DELIVERED_1_FOLDER}"
while [ "${FILE_COUNT}" -eq 0 ] && [ "${waited}" -lt "${BT_WAIT_SECONDS}" ]; do
    printf "Nothing in %s yet. Waiting...\n" "${BT_DELIVERED_1_FOLDER}"
    sleep 3
    waited=$((waited + 3))
    list_folder "${BT_DELIVERED_1_FOLDER}"
done

for n in 1 2 3 4 5 6; do
    folder="${BT_SUBSCRIPTION_FOLDER}/s${n}"
    list_folder "${folder}"
    printf "\n%s: %s file(s)\n" "${folder}" "${FILE_COUNT}"
    printf '%s' "${AR_EU_BODY}" | jq -r '(.files // [])[] | select(.isRegularFile) | "    " + .fileName + "  (" + (.size | tostring) + " bytes)"' 2>/dev/null
done

for folder in "${BT_DELIVERED_1_FOLDER}" "${BT_DELIVERED_2_FOLDER}"; do
    list_folder "${folder}"
    printf "\n%s: %s file(s)\n" "${folder}" "${FILE_COUNT}"
    printf '%s' "${AR_EU_BODY}" | jq -r '(.files // [])[] | select(.isRegularFile) | "    " + .fileName + "  (" + (.size | tostring) + " bytes)"' 2>/dev/null
done

ar_enduser_logout
