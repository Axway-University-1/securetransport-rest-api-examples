#!/bin/bash
# ==============================================================================
# Script Name: 02.sites_POST_pull.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Creates the transfer site the account pulls from, using the `/sites` endpoint.
# It is an SSH site that points at this server's own SSH listener, and its
# download folder is where the files to be pulled are waiting.
#
# Usage:
# ./02.sites_POST_pull.sh
#
# Risk: write
#
# Notes:
# - Run 01.accounts_POST.sh first.
# - Needs settings.local.sh with AR_ACCOUNT_PASSWORD. See settings.sh.
# - Requires `jq`, which builds the JSON body.
# - doAsIn renames each file as it is received, to ${stenv.target}_PULLED, so the
#   inbound rows in File Tracking can be told from the outbound ones.
# - The SSH port is AR_SSH_PORT, 8022 by default. It is not the REST API port.
# - Exits 1 when the server refuses the site.
# - If the pull later fails to log in, check first whether this server allows an
#   account to open an SSH session to itself.
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

BODY=$(jq -n \
  --arg name "${AR_PULL_SITE}" \
  --arg host "${AR_SSH_HOST}" \
  --arg port "${AR_SSH_PORT}" \
  --arg account "${AR_TEST_ACCOUNT}" \
  --arg password "${AR_ACCOUNT_PASSWORD}" \
  --arg folder "${AR_PULL_FROM_FOLDER}" \
  --arg rename "${AR_PULL_RENAME}" \
  '{type: "ssh", protocol: "ssh", name: $name, host: $host, port: $port, userName: $account,
    usePassword: true, password: $password, account: $account,
    transferType: "partner", downloadFolder: $folder,
    downloadPatternType: "glob", downloadPattern: "*",
    postTransmissionActions: {doAsIn: $rename}}')

printf "Creating the pull site %s...\n" "${AR_PULL_SITE}"
ar_admin_post "sites" "${BODY}" || exit 1
