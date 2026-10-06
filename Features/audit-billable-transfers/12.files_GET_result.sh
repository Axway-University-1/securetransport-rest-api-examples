#!/bin/bash
# ==============================================================================
# Script Name: 12.files_GET_result.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Shows what each scenario left behind, using the End User API
# `GET /files/{folder}` endpoint: the test account's six subscription/sN folders
# (what was pulled), then partner_to_push_to's two delivered folders (what was
# pushed). The pushes are asynchronous, so it first waits for delivered-2 to hold
# both files of scenario 2.6, the last pushes to arrive.
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

# Print a folder's regular files, after its account and name
show_folder() {
    list_folder "$2"
    printf "\n%s %s: %s file(s)\n" "$1" "$2" "${FILE_COUNT}"
    printf '%s' "${AR_EU_BODY}" | jq -r '(.files // [])[] | select(.isRegularFile) | "    " + .fileName + "  (" + (.size | tostring) + " bytes)"' 2>/dev/null
}

# partner_to_push_to: scenario 2.6 pushes its two files to delivered-2 last
bt_login_as "${BT_PUSH_PARTNER}" || exit 1
waited=0
list_folder "${BT_DELIVERED_2_FOLDER}"
while [ "${FILE_COUNT}" -lt 2 ] && [ "${waited}" -lt "${BT_WAIT_SECONDS}" ]; do
    printf "%s holds %s of 2 files yet. Waiting...\n" "${BT_DELIVERED_2_FOLDER}" "${FILE_COUNT}"
    sleep 3
    waited=$((waited + 3))
    list_folder "${BT_DELIVERED_2_FOLDER}"
done
for folder in "${BT_DELIVERED_1_FOLDER}" "${BT_DELIVERED_2_FOLDER}"; do
    show_folder "${BT_PUSH_PARTNER}" "${folder}"
done
ar_enduser_logout

# The test account: what each scenario pulled in
bt_login_as "${BT_TEST_ACCOUNT}" || exit 1
for n in 1 2 3 4 5 6; do
    show_folder "${BT_TEST_ACCOUNT}" "${BT_SUBSCRIPTION_FOLDER}/s${n}"
done
ar_enduser_logout
