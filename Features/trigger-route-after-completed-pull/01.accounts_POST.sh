#!/bin/bash
# ==============================================================================
# Script Name: 01.accounts_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Creates the test account that owns the pull site, the subscription and the push
# site, using the `/accounts` endpoint. It is a user account with its own
# password, so the two sites can log in to this server's SSH listener as it.
#
# Usage:
# ./01.accounts_POST.sh
#
# Risk: write
#
# Notes:
# - Needs settings.local.sh with AR_ACCOUNT_PASSWORD. See settings.sh.
# - Requires `jq`, which builds the JSON body.
# - transfersWebServiceAllowed is on. Without it the account cannot log in to the
#   End User API, which steps 4 and 5 use, and the login fails with a 401.
# - The account is created with a home folder of AR_HOME_FOLDER. Create the
#   subfolders outbound-drop and delivered in it, and put some files in
#   outbound-drop, before running the pull.
# - 99.cleanup_DELETE.sh removes the account again.
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
  --arg name "${AR_TEST_ACCOUNT}" \
  --arg home "${AR_HOME_FOLDER}" \
  --arg password "${AR_ACCOUNT_PASSWORD}" \
  '{name: $name, type: "user", homeFolder: $home, uid: "41733", gid: "41733",
    transfersWebServiceAllowed: true,
    user: {name: $name, passwordCredentials: {password: $password}}}')

printf "Creating the account %s...\n" "${AR_TEST_ACCOUNT}"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -w "\nHTTP %{http_code}\n" -d "${BODY}"
