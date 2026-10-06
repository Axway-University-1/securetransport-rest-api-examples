#!/bin/bash
# ==============================================================================
# Script Name: 04.files_POST_folders.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Creates the folders these examples need, using the End User API
# `POST /files/{name}` endpoint, logged in as each account in turn:
#   - the test account: the subscription folder, and six subfolders inside it,
#     one per scenario (subscription/s1 to subscription/s6)
#   - partner_to_pull_from: a folder named after the test account, and the drop
#     folder inside it, where the sample files wait to be pulled
#   - partner_to_push_to: a folder named after the test account, and the two
#     delivered folders inside it, where the pushes arrive
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
# - A nested folder is created after its parent, like a plain mkdir.
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

# The test account: the subscription folder, then one subfolder per scenario
bt_login_as "${BT_TEST_ACCOUNT}" || exit 1
create_folder "${BT_SUBSCRIPTION_FOLDER#/}"
for n in 1 2 3 4 5 6; do
    create_folder "${BT_SUBSCRIPTION_FOLDER#/}/s${n}"
done
ar_enduser_logout

# partner_to_pull_from: the test account's folder, then its drop folder
bt_login_as "${BT_PULL_PARTNER}" || exit 1
create_folder "${BT_RUN_FOLDER#/}"
create_folder "${BT_DROP_FOLDER#/}"
ar_enduser_logout

# partner_to_push_to: the test account's folder, then the two delivered folders
bt_login_as "${BT_PUSH_PARTNER}" || exit 1
create_folder "${BT_RUN_FOLDER#/}"
create_folder "${BT_DELIVERED_1_FOLDER#/}"
create_folder "${BT_DELIVERED_2_FOLDER#/}"
ar_enduser_logout
