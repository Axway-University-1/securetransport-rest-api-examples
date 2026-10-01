#!/bin/bash
# ==============================================================================
# Script Name: 03.sites_POST_push.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Creates the transfer site the pulled files are pushed to, using the `/sites`
# endpoint. It points at this server's own SSH listener, and its upload folder
# is outside the subscription folder.
#
# Usage:
# ./03.sites_POST_push.sh
#
# Notes:
# - Run 01.accounts_POST.sh first.
# - Needs settings.local.sh with AR_ACCOUNT_PASSWORD. See settings.sh.
# - Requires `jq`, which builds the JSON body.
# - doAsOut renames each file as it is sent, to ${stenv.target}_PUSHED, so the
#   outbound rows in File Tracking can be told from the inbound ones.
# - The upload folder must not be the subscription folder, or the pushed files
#   would trigger the route again.
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

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

BODY=$(jq -n \
  --arg name "${AR_PUSH_SITE}" \
  --arg host "${AR_SSH_HOST}" \
  --arg port "${AR_SSH_PORT}" \
  --arg account "${AR_TEST_ACCOUNT}" \
  --arg password "${AR_ACCOUNT_PASSWORD}" \
  --arg folder "${AR_DELIVERED_FOLDER}" \
  --arg rename "${AR_PUSH_RENAME}" \
  '{type: "ssh", protocol: "ssh", name: $name, host: $host, port: $port, userName: $account,
    usePassword: true, password: $password, account: $account,
    transferType: "partner", uploadFolder: $folder,
    postTransmissionActions: {doAsOut: $rename}}')

printf "Creating the push site %s...\n" "${AR_PUSH_SITE}"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/sites" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -w "\nHTTP %{http_code}\n" -d "${BODY}"
