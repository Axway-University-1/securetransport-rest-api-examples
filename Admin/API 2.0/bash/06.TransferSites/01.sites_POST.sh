#!/bin/bash
# ==============================================================================
# Script Name: 01.sites_POST.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script creates a transfer site using the `/sites` endpoint.
# It demonstrates:
# - An HTTP site, built with jq, attached to an account
# - The HTTP code, and the new site's id from the Location header
#
# Usage:
# ./01.sites_POST.sh
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The site is attached to an account, which must already exist. This example
#   uses the account "john".
# - The host below points at ST_SERVER, which is only an example. A transfer
#   site normally points at a partner's server.
# - The site is called HTTP. 04.sites_id_DELETE.sh removes it again, together with the two SSH sites of
#   02.sites_POST_ssh.sh.
# - Requires `jq`, which builds the request body.
# - Confirmed directly: a creation is 201 with no body and the site's address in `Location`, which ends with its id; the same name on the same
#   account again is 409 "Entry already exist.". The HTTP site is saved with no password (`password` reads back null).
# - Exit codes: 0 when the site was created (201), 1 when the server refuses it. It takes no argument.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

#
# First we will load the variables into our context.
# Put your own values in set_variables.local.sh, which set_variables.sh
# loads and which git ignores.
#
source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/sites"

if [ "$#" -ne 0 ]; then
    printf "Usage: ./01.sites_POST.sh\n"
    exit 2
fi

SITE_NAME="HTTP"
ACCOUNT="${ST_EXAMPLE_ACCOUNT:-john}"
PARTNER_USER="${ST_EXAMPLE_ACCOUNT:-john}"
HEADERS_FILE=$(mktemp)
trap 'rm -f "${HEADERS_FILE}"' EXIT

# Create TS
#
# The body is built with jq, so that a value with a quote or a backslash in it
# cannot break the JSON.
#
BODY=$(jq -cn --arg name "${SITE_NAME}" --arg account "${ACCOUNT}" --arg host "${ST_SERVER}" --arg user "${PARTNER_USER}" \
  '{name: $name, type: "http", protocol: "http", account: $account, host: $host, port: "443",
    downloadPattern: "*", uploadFolder: "/", userName: $user}')

printf "Creating the HTTP site %s...\n" "${SITE_NAME}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -D "${HEADERS_FILE}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "201" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
LOCATION=$(sed -n 's/^[Ll]ocation: *//p' "${HEADERS_FILE}" | tr -d '\r' | tail -n 1)
if [ -n "${LOCATION}" ]; then
    printf "New site ID: %s\n" "${LOCATION##*/}"
fi
