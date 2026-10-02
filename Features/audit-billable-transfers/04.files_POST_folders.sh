#!/bin/bash
# ==============================================================================
# Script Name: 04.files_POST_folders.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Creates the folders these examples need in the account's home, using the End
# User API `POST /files/{name}` endpoint: the shared drop folder, the two
# delivered folders, the subscription folder, and six subfolders inside it, one
# per scenario (subscription/s1 to subscription/s6).
#
# Usage:
# ./04.files_POST_folders.sh
#
# Notes:
# - Run 01.accounts_POST.sh first.
# - Needs settings.local.sh with BT_ACCOUNT_PASSWORD. See settings.sh.
# - Requires `jq`, which builds the JSON body.
# - The folder's name goes in the URL, and the body says it is a directory. POST
#   /files with the name in the body is refused with a 409, whatever the body
#   (confirmed on Features/trigger-route-after-completed-pull).
# - UNVERIFIED: the subscription/sN subfolders are created with a second POST,
#   after the subscription folder itself exists, on the assumption that creating
#   a nested folder needs its parent to exist first, like a plain mkdir.
# - The port is BT_ENDUSER_PORT, 8443 by default. It is not the Admin port.
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

create_folder() {
    local path="$1"
    local body
    body=$(jq -n '{isDirectory: true, isRegularFile: false, isSymbolicLink: false,
                   isOther: false, isShared: false}')
    printf "Creating the folder %s...\n" "${path}"
    ar_enduser_call POST "files/${path}" "application/json" "${body}"
    printf "%s\nHTTP %s\n" "${AR_EU_BODY}" "${AR_EU_CODE}"
}

ar_enduser_login || exit 1

# Top level first: outbound-drop, delivered-1, delivered-2, subscription
for folder in "${BT_DROP_FOLDER#/}" "${BT_DELIVERED_1_FOLDER#/}" "${BT_DELIVERED_2_FOLDER#/}" "${BT_SUBSCRIPTION_FOLDER#/}"; do
    create_folder "${folder}"
done

# Then one subfolder of subscription per scenario
for n in 1 2 3 4 5 6; do
    create_folder "${BT_SUBSCRIPTION_FOLDER#/}/s${n}"
done

ar_enduser_logout
