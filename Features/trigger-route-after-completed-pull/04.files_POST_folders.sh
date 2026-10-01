#!/bin/bash
# ==============================================================================
# Script Name: 04.files_POST_folders.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Creates the folders the example needs in the account's home, using the End User
# API `POST /files/{name}` endpoint. It logs in to the End User API as the test account
# itself, on the End User port, and logs out again at the end.
#
# Usage:
# ./04.files_POST_folders.sh
#
# Notes:
# - Run 01.accounts_POST first.
# - Needs settings.local.sh with AR_ACCOUNT_PASSWORD. See settings.sh.
# - Which folders is set by AR_CREATE_FOLDERS: outbound-drop, where the pull
#   finds its files, and delivered, where the push puts them.
# - Requires `jq`, which builds the JSON body.
# - The port is AR_ENDUSER_PORT, 8443 by default. It is not the Admin port.
# - The folder's name goes in the URL, and the body says it is a directory. POST
#   /files with the name in the body is refused with a 409, whatever the body.
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

ar_enduser_login || exit 1

for folder in ${AR_CREATE_FOLDERS}; do
    # The folder's name is in the URL. The body describes it as a directory.
    BODY=$(jq -n '{isDirectory: true, isRegularFile: false, isSymbolicLink: false,
                   isOther: false, isShared: false}')

    printf "Creating the folder %s...\n" "${folder}"
    ar_enduser_call POST "files/${folder}" "application/json" "${BODY}"
    printf "%s\nHTTP %s\n" "${AR_EU_BODY}" "${AR_EU_CODE}"
done

ar_enduser_logout
