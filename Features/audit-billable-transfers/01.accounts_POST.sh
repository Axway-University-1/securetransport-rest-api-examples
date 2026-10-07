#!/bin/bash
# ==============================================================================
# Script Name: 01.accounts_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Creates the three accounts these examples use, using the `/accounts` endpoint:
#   - the test account, which owns every site, subscription and route
#   - partner_to_pull_from, which holds the sample files the test account pulls
#   - partner_to_push_to, which receives what the test account pushes
# Each is a user account with its own password, so the test account's sites can
# log in to this server's SSH listener as a partner, and each account can log in
# to the End User API.
#
# Usage:
# ./01.accounts_POST.sh
#
# Risk: write
#
# Notes:
# - Needs settings.local.sh with BT_ACCOUNT_PASSWORD. See settings.sh.
# - Requires `jq`, which builds the JSON body.
# - transfersWebServiceAllowed is on. Without it the account cannot log in to the
#   End User API, and that login fails with a 401.
# - The partners are shared by every test account. One that already exists, from
#   another test account's run, is reused and not created again.
#   99.cleanup_DELETE removes a partner only when no other test account's site
#   still logs in as it.
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

create_account() {
    local name="$1" home="$2" body
    body=$(jq -n --arg name "${name}" --arg home "${home}" --arg password "${BT_ACCOUNT_PASSWORD}" \
      '{name: $name, type: "user", homeFolder: $home, uid: "41733", gid: "41733",
        transfersWebServiceAllowed: true,
        user: {name: $name, passwordCredentials: {password: $password}}}')
    printf "Creating the account %s...\n" "${name}"
    ar_admin_post "accounts" "${body}"
}

# create_partner NAME HOME: creates a partner, or reuses it when it is there
create_partner() {
    local code
    code=$(curl -s -k -o /dev/null -w "%{http_code}" -u "${ST_USER}:${ST_PASSWORD}" --head \
      "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/$1" -H "accept: */*" -H "Referer: THIS_IS_A_RANDOM_TEXT")
    if [ "${code}" = "200" ]; then
        printf "The account %s is already there, from another test account's run. Reused.\n" "$1"
        return 0
    fi
    create_account "$1" "$2"
}

create_account "${BT_TEST_ACCOUNT}" "${BT_HOME_FOLDER}" || exit 1
create_partner "${BT_PULL_PARTNER}" "${BT_PULL_PARTNER_HOME}" || exit 1
create_partner "${BT_PUSH_PARTNER}" "${BT_PUSH_PARTNER_HOME}" || exit 1
