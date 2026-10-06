#!/bin/bash
# ==============================================================================
# Script Name: 02.sites_POST_ssh.sh
# Author: Plamen Milenkov
# Created: 2026-10-05
# Location: Sofia
# ==============================================================================
# Description:
# This script creates two SSH transfer sites using the `/sites` endpoint.
# It demonstrates:
# - A pull site, which downloads the files matching a pattern from a folder on
#   the partner, and renames each file it receives (doAsIn)
# - A push site, which uploads to a folder on the partner, and renames each file
#   it sends (doAsOut)
#
# Usage:
# ./02.sites_POST_ssh.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The sites are attached to the account "john", which must already exist.
# - The partner here is SecureTransport itself: the sites log in to ST_SERVER
#   over SSH, as john. Point PARTNER_HOST at a real partner's server instead.
#   PARTNER_PASSWORD is read from the environment, so export it first:
#     export PARTNER_PASSWORD='the password'
# - The folders are relative to the partner account's home folder, so
#   "/outbound-drop" is <home of john>/outbound-drop.
# - ${stenv.target} in the rename is Expression Language, filled in by
#   SecureTransport with the file name. It is not a shell variable.
# - Requires `jq`, which builds the request bodies.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

ACCOUNT="john"
PARTNER_HOST="${ST_SERVER}"
PARTNER_SSH_PORT="8022"
PARTNER_USER="john"
PARTNER_PASSWORD="${PARTNER_PASSWORD:-change_me}"

#
# The pull site. Every *.txt file in /outbound-drop on the partner is downloaded,
# and arrives here with _PULLED added to its name.
#
BODY=$(jq -n --arg account "${ACCOUNT}" --arg host "${PARTNER_HOST}" --arg port "${PARTNER_SSH_PORT}" \
  --arg user "${PARTNER_USER}" --arg password "${PARTNER_PASSWORD}" \
  '{type: "ssh", protocol: "ssh", name: "SSH_PULL", account: $account,
    host: $host, port: $port, userName: $user, usePassword: true, password: $password,
    transferType: "partner",
    downloadFolder: "/outbound-drop", downloadPatternType: "glob", downloadPattern: "*.txt",
    postTransmissionActions: {doAsIn: "${stenv.target}_PULLED"}}')

printf "Creating the SSH pull site SSH_PULL...\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/sites" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -w "\nHTTP %{http_code}\n" -d "${BODY}"

#
# The push site. Files are uploaded to /delivered on the partner, with _PUSHED
# added to their name.
#
BODY=$(jq -n --arg account "${ACCOUNT}" --arg host "${PARTNER_HOST}" --arg port "${PARTNER_SSH_PORT}" \
  --arg user "${PARTNER_USER}" --arg password "${PARTNER_PASSWORD}" \
  '{type: "ssh", protocol: "ssh", name: "SSH_PUSH", account: $account,
    host: $host, port: $port, userName: $user, usePassword: true, password: $password,
    transferType: "partner", uploadFolder: "/delivered",
    postTransmissionActions: {doAsOut: "${stenv.target}_PUSHED"}}')

printf "Creating the SSH push site SSH_PUSH...\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/sites" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -w "\nHTTP %{http_code}\n" -d "${BODY}"
