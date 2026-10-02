#!/bin/bash
# ==============================================================================
# Script Name: 01.accounts_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Creates the test account that owns every site, subscription and route these
# examples use, using the `/accounts` endpoint. It is a user account with its
# own password, so the sites can log in to this server's SSH listener as it, and
# the account can log in to the End User API to upload the sample files.
#
# Usage:
# ./01.accounts_POST.sh
#
# Notes:
# - Needs settings.local.sh with BT_ACCOUNT_PASSWORD. See settings.sh.
# - Requires `jq`, which builds the JSON body.
# - transfersWebServiceAllowed is on. Without it the account cannot log in to the
#   End User API, and that login fails with a 401.
# - The account is created with a home folder of BT_HOME_FOLDER. 99.cleanup_DELETE
#   removes the account again.
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

BODY=$(jq -n \
  --arg name "${BT_TEST_ACCOUNT}" \
  --arg home "${BT_HOME_FOLDER}" \
  --arg password "${BT_ACCOUNT_PASSWORD}" \
  '{name: $name, type: "user", homeFolder: $home, uid: "1001", gid: "1001",
    transfersWebServiceAllowed: true,
    user: {name: $name, passwordCredentials: {password: $password}}}')

printf "Creating the account %s...\n" "${BT_TEST_ACCOUNT}"
ar_admin_post "accounts" "${BODY}"
