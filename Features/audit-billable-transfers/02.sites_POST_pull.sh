#!/bin/bash
# ==============================================================================
# Script Name: 02.sites_POST_pull.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Creates the six pull sites these examples use, using the `/sites` endpoint.
# Each is an SSH site of the test account, logging in to this server's own SSH
# listener as partner_to_pull_from and reading from the test account's drop
# folder there (<account>/outbound-drop), each with a download pattern matching only
# the file (or files) for its own scenario. A file is copied, not moved, by a
# pull (storeAndForwardMode PRESERVE is not set here, which is the server's
# default), so the six sites can share one drop folder without one site's pull
# taking a file another site also needs.
#
# Usage:
# ./02.sites_POST_pull.sh
#
# Notes:
# - Run 01.accounts_POST.sh first.
# - Needs settings.local.sh with BT_ACCOUNT_PASSWORD. See settings.sh.
# - Requires `jq`, which builds the JSON body.
# - The SSH port is BT_SSH_PORT, 8022 by default. It is not the REST API port.
# - Site N is named <account>PullSite<N> and its pattern matches the file(s) for
#   scenario <N> only: see settings.sh for the mapping from scenario to file.
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

create_pull_site() {
    local n="$1" pattern="$2"
    local name="${BT_PULL_SITE_PREFIX}${n}"
    local body
    body=$(jq -n \
      --arg name "${name}" \
      --arg host "${BT_SSH_HOST}" \
      --arg port "${BT_SSH_PORT}" \
      --arg account "${BT_TEST_ACCOUNT}" \
      --arg partner "${BT_PULL_PARTNER}" \
      --arg password "${BT_ACCOUNT_PASSWORD}" \
      --arg folder "${BT_DROP_FOLDER}" \
      --arg pattern "${pattern}" \
      '{type: "ssh", protocol: "ssh", name: $name, host: $host, port: $port,
        userName: $partner, usePassword: true, password: $password, account: $account,
        transferType: "partner", downloadFolder: $folder,
        downloadPatternType: "glob", downloadPattern: $pattern}')

    printf "Creating the pull site %s, matching %s...\n" "${name}" "${pattern}"
    ar_admin_post "sites" "${body}"
}

# Scenarios 2.1 and 2.2 can run several files (BT_INBOUND_ONLY_COUNT,
# BT_IN_AND_OUT_COUNT): the pattern matches the plain name and the numbered ones
create_pull_site 1 "${BT_FILE_ONLY_INBOUND%.txt}*.txt"
create_pull_site 2 "${BT_FILE_ONE_OUTBOUND%.txt}*.txt"
create_pull_site 3 "${BT_FILE_TWO_OUTBOUNDS}"
create_pull_site 4 "file_*_for_compress.txt"
create_pull_site 5 "${BT_FILE_ARCHIVE_NAME}"
create_pull_site 6 "${BT_FILE_ARCHIVE2P_NAME}"
