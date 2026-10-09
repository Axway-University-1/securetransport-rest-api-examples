#!/bin/bash
# ==============================================================================
# Script Name: 09.sites_operations_POST_test.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script tests the connection of a saved transfer site, using the
# `/sites/operations` endpoint with operation=testConnection: the server opens a
# connection to the partner and logs in, as a transfer would, and sends nothing.
#
# Usage:
# ./09.sites_operations_POST_test.sh [ACCOUNT [NAME]]
#
#   ACCOUNT  the account the site belongs to (default john, or ST_EXAMPLE_ACCOUNT)
#   NAME     the site (default SSH_PULL, which 02.sites_POST_ssh.sh creates)
#
#   SITE_PASSWORD  optional, in the environment: test with this password instead of the one
#                  saved with the site
#
# Risk: read - opens a connection to the partner, changes nothing
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It exits 0 when the connection and the login both worked, 1 otherwise.
# - The body names the site by its id, with its name, host, port and protocol (the reference
#   marks those required). Confirmed directly: the server fills in everything else, the user
#   and the saved password included, from the site with that id, so nothing secret is sent. What
#   the body does carry wins over what was saved: a wrong password, host or port in it fails the
#   test. The protocol is the saved site's (a wrong one in the body is ignored), and a host or
#   port left out of the body is the saved site's too.
# - Confirmed directly: the answer is 200 whether or not the test worked. Read
#   `connectionStatus` (could the server reach the partner) and `authenticationStatus` (did the
#   login work), and `errorDetails` for why not: a closed port is "Connection refused", a host
#   that does not resolve "Unknown site host: <host>", a wrong SSH password "Password
#   authentication failed...", a wrong FTP password "530-Login failed...", a partner that is not
#   an SSH server "Failed to negotiate transport component". SSH answers the cipher, the key
#   algorithm and the host key's type; FTP and HTTP leave them null. An unknown id is a JSON 404.
# - A partner that accepts the connection and then says nothing keeps the test waiting for
#   longer than 30 seconds.
# - A test with a wrong password is a real failed login, and counts against the account the site
#   logs in as. Confirmed directly: one wrong SSH password counts as TWO failed attempts (the
#   password, then keyboard-interactive), and with failedAuthMaximum at 3 a second wrong test
#   LOCKS that account, which then refuses every login, even with the right password, until it
#   is unlocked. A login that works in between resets the count. Do not test a real partner
#   account's password twice in a row.
# - Works for SSH, FTP and HTTP sites. A custom site (S3...) answers 200 as well, with its own
#   message in errorDetails.
# - Requires `jq`, which reads the id and builds the request.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/sites"
ACCOUNT="${1:-${ST_EXAMPLE_ACCOUNT:-john}}"
NAME="${2:-SSH_PULL}"

# The one site of that account with that name: "1 <id>", or how many there are.
# The name filter ignores case and takes a * wildcard, so the exact name is
# picked out of what comes back.
read -r FOUND SITE_ID < <(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" \
  --data-urlencode "account=${ACCOUNT}" --data-urlencode "name=${NAME}" --data-urlencode "fields=id,name" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r --arg name "${NAME}" '[(.result // [])[] | select(.name == $name)] | if length == 1 then "1 \(.[0].id)" else "\(length)" end')
if [ "${FOUND}" != "1" ]; then
    printf "Found %s sites named %s on the account %s; this script acts on exactly one.\n" "${FOUND:-0}" "${NAME}" "${ACCOUNT}"
    exit 1
fi

SITE_JSON=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${SITE_ID}" -H "accept: application/json" -H "${REFERER_HEADER}")
if ! printf '%s' "${SITE_JSON}" | jq -e '.id' >/dev/null 2>&1; then
    printf "Could not read the site %s (id %s).\n" "${NAME}" "${SITE_ID}"
    exit 1
fi
BODY=$(printf '%s' "${SITE_JSON}" | jq -c --arg password "${SITE_PASSWORD}" \
  '{id, name, host: (.host // ""), port: (.port // ""), protocol, account}
   + (if $password != "" then {password: $password, usePassword: "true"} else {} end)')

printf "Testing the connection of the site %s of %s...\n" "${NAME}" "${ACCOUNT}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}/operations?operation=testConnection" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf '%s\n' "${RESPONSE}"
    exit 1
fi
printf '%s' "${RESPONSE}" | jq -r '"  connection:      \(.connectionStatus)", "  authentication:  \(.authenticationStatus)",
  (if .errorDetails then "  error:           \(.errorDetails)" else empty end)'
printf '%s' "${RESPONSE}" | jq -e '.connectionStatus == "success" and .authenticationStatus == "success"' >/dev/null
