#!/bin/bash
# ==============================================================================
# Script Name: 03.sites_POST_push.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Creates the two push sites these examples use as "the remote partners", using
# the `/sites` endpoint. Both are SSH sites of the test account, logging in to
# this server's own SSH listener as partner_to_push_to, each uploading into its
# own delivered folder there (<account>/delivered-1 and <account>/delivered-2).
#
# Usage:
# ./03.sites_POST_push.sh
#
# Risk: write
#
# Notes:
# - Run 01.accounts_POST.sh first.
# - Needs settings.local.sh with BT_ACCOUNT_PASSWORD. See settings.sh.
# - Requires `jq`, which builds the JSON body.
# - Stops at the first site the server refuses, and exits 1.
# - Only scenario 2.6 (archive pushed to two partners) uses the second site.
#   Every other scenario that pushes uses the first one.
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

create_push_site() {
    local name="$1" folder="$2"
    local body
    body=$(jq -n \
      --arg name "${name}" \
      --arg host "${BT_SSH_HOST}" \
      --arg port "${BT_SSH_PORT}" \
      --arg account "${BT_TEST_ACCOUNT}" \
      --arg partner "${BT_PUSH_PARTNER}" \
      --arg password "${BT_ACCOUNT_PASSWORD}" \
      --arg folder "${folder}" \
      '{type: "ssh", protocol: "ssh", name: $name, host: $host, port: $port,
        userName: $partner, usePassword: true, password: $password, account: $account,
        transferType: "partner", uploadFolder: $folder}')

    printf "Creating the push site %s, delivering to %s...\n" "${name}" "${folder}"
    ar_admin_post "sites" "${body}"
}

create_push_site "${BT_PUSH_SITE_1}" "${BT_DELIVERED_1_FOLDER}" || exit 1
create_push_site "${BT_PUSH_SITE_2}" "${BT_DELIVERED_2_FOLDER}" || exit 1
