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
# export PARTNER_PASSWORD='the partner account password'
# ./02.sites_POST_ssh.sh [PORT]
#
#   PARTNER_PASSWORD  the password the sites log in with, from the environment (required: without it, or with the placeholder
#                     change_me, the script prints this usage, sends nothing and exits 2)
#   PORT              the partner's SSH port, 1 to 65535 (default 8022)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The sites are attached to the account "john", which must already exist.
# - The partner here is SecureTransport itself: the sites log in to ST_SERVER
#   over SSH, as john. Point PARTNER_HOST at a real partner's server instead.
#   PARTNER_PASSWORD is read from the environment, so export it first:
#     export PARTNER_PASSWORD='the password'
#   There is no default password: a placeholder one would be saved on both sites and could never log in.
# - The folders are relative to the partner account's home folder, so
#   "/outbound-drop" is <home of john>/outbound-drop.
# - ${stenv.target} in the rename is Expression Language, filled in by
#   SecureTransport with the file name. It is not a shell variable.
# - Requires `jq`, which builds the request bodies.
# - 04.sites_id_DELETE.sh removes SSH_PULL and SSH_PUSH again.
# - Confirmed directly: each creation is 201 with the site's address in `Location`, which ends with the site's id; a second one with the same name
#   on the same account is 409 "Entry already exist.". The password is stored encrypted and reads back as `{AES128}...`, never as sent.
# - Exit codes: 0 when both sites were created (201), 1 when the server refuses one (the other is still tried), 2 when PARTNER_PASSWORD is
#   missing or the placeholder, or the port is wrong (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/sites"
USAGE="Usage: export PARTNER_PASSWORD='...'; ./02.sites_POST_ssh.sh [PORT]"

ACCOUNT="john"
PARTNER_HOST="${ST_SERVER}"
PARTNER_SSH_PORT="8022"
PARTNER_USER="john"

# The port may be given as the first argument; 8022 above is the default
PARTNER_SSH_PORT="${1:-${PARTNER_SSH_PORT}}"
if [ "$#" -gt 1 ] || ! [[ "${PARTNER_SSH_PORT}" =~ ^[0-9]+$ ]] || [ "${PARTNER_SSH_PORT}" -lt 1 ] || [ "${PARTNER_SSH_PORT}" -gt 65535 ]; then
    printf "PORT is a number from 1 to 65535. Nothing was sent.\n%s\n" "${USAGE}"
    exit 2
fi
if [ -z "${PARTNER_PASSWORD}" ] || [ "${PARTNER_PASSWORD}" = "change_me" ]; then
    printf "PARTNER_PASSWORD must be set in the environment to the password of the partner account, not left empty or as change_me. Nothing was sent.\n%s\n" "${USAGE}"
    exit 2
fi

HEADERS_FILE=$(mktemp)
trap 'rm -f "${HEADERS_FILE}"' EXIT
FAILED=0

# create_site DESCRIPTION BODY: posts the site, prints the code and the new id, and sets FAILED when the server refuses it
create_site() {
    printf "Creating %s...\n" "$1"
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" \
      -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
      -d "$2" -D "${HEADERS_FILE}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    printf "HTTP %s\n" "${HTTP_CODE}"
    if [ "${HTTP_CODE}" != "201" ]; then
        printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
        FAILED=1
        return
    fi
    LOCATION=$(sed -n 's/^[Ll]ocation: *//p' "${HEADERS_FILE}" | tr -d '\r' | tail -n 1)
    if [ -n "${LOCATION}" ]; then
        printf "New site ID: %s\n" "${LOCATION##*/}"
    fi
}

#
# The pull site. Every *.txt file in /outbound-drop on the partner is downloaded,
# and arrives here with _PULLED added to its name.
#
BODY=$(jq -cn --arg account "${ACCOUNT}" --arg host "${PARTNER_HOST}" --arg port "${PARTNER_SSH_PORT}" \
  --arg user "${PARTNER_USER}" --arg password "${PARTNER_PASSWORD}" \
  '{type: "ssh", protocol: "ssh", name: "SSH_PULL", account: $account,
    host: $host, port: $port, userName: $user, usePassword: true, password: $password,
    transferType: "partner",
    downloadFolder: "/outbound-drop", downloadPatternType: "glob", downloadPattern: "*.txt",
    postTransmissionActions: {doAsIn: "${stenv.target}_PULLED"}}')
create_site "the SSH pull site SSH_PULL" "${BODY}"

#
# The push site. Files are uploaded to /delivered on the partner, with _PUSHED
# added to their name.
#
BODY=$(jq -cn --arg account "${ACCOUNT}" --arg host "${PARTNER_HOST}" --arg port "${PARTNER_SSH_PORT}" \
  --arg user "${PARTNER_USER}" --arg password "${PARTNER_PASSWORD}" \
  '{type: "ssh", protocol: "ssh", name: "SSH_PUSH", account: $account,
    host: $host, port: $port, userName: $user, usePassword: true, password: $password,
    transferType: "partner", uploadFolder: "/delivered",
    postTransmissionActions: {doAsOut: "${stenv.target}_PUSHED"}}')
create_site "the SSH push site SSH_PUSH" "${BODY}"

exit "${FAILED}"
