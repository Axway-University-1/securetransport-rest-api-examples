#!/bin/bash
# ==============================================================================
# Script Name: 10.sites_operations_POST_test_new.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script tests a connection before the site is saved, using the
# `/sites/operations` endpoint with operation=testConnection: the body carries the
# partner's address and the login, and no site is created.
#
# Usage:
# ./10.sites_operations_POST_test_new.sh [ACCOUNT [PROTOCOL [HOST [PORT [USER [SECURE]]]]]]
#
#   ACCOUNT   the account the site would belong to (default john)
#   PROTOCOL  ssh, ftp or http (default ssh)
#   HOST      the partner's host (default ST_SERVER)
#   PORT      the partner's port (default 8022)
#   USER      the login (default: the account)
#   SECURE    true or false, for an FTP or HTTP partner over TLS (default false)
#
#   SITE_PASSWORD  the partner's password, in the environment:
#     export SITE_PASSWORD='the password'
#
# Risk: read - opens a connection to the partner, changes nothing
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It exits 0 when the connection and the login both worked, 1 otherwise, 2 when an argument
#   or SITE_PASSWORD is wrong. The partner here is SecureTransport itself: the defaults are its
#   SSH port, logging in as the account. Point it at a real partner's server instead.
# - Confirmed directly: for a site that is not saved the body needs an `account` that exists
#   (400 "Cannot perform a test operation for a non saved site. Account null does not
#   exist." without it), a `name` (any text; nothing is saved under it), `host`, `port` and
#   `protocol`, and the login in `username` and `password` with `usePassword` "true": the
#   field is `username` in lower case here, not `userName` as in a site. An HTTP partner on
#   SecureTransport's own HTTPS port needs `isSecure` "true".
# - The answer is 200 whether or not the test worked; see 09.sites_operations_POST_test.sh. A wrong
#   password counts against the account the login is for, two failed attempts for SSH, and a
#   second wrong test locks it (see 09.sites_operations_POST_test.sh).
# - Requires `jq`, which builds the request.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/sites"
ACCOUNT="${1:-john}"
PROTOCOL="${2:-ssh}"
PARTNER_HOST="${3:-${ST_SERVER}}"
PARTNER_PORT="${4:-8022}"
PARTNER_USER="${5:-${ACCOUNT}}"
SECURE="${6:-false}"
[[ "${PROTOCOL}" =~ ^(ssh|ftp|http)$ ]] || { printf "PROTOCOL is ssh, ftp or http, not %s.\n" "${PROTOCOL}"; exit 2; }
[[ "${PARTNER_PORT}" =~ ^[0-9]+$ ]] || { printf "PORT is a number, not %s.\n" "${PARTNER_PORT}"; exit 2; }
[[ "${SECURE}" =~ ^(true|false)$ ]] || { printf "SECURE is true or false, not %s.\n" "${SECURE}"; exit 2; }
if [ -z "${SITE_PASSWORD}" ]; then
    printf "Set SITE_PASSWORD to the partner's password first.\n"
    exit 2
fi

BODY=$(jq -n --arg account "${ACCOUNT}" --arg protocol "${PROTOCOL}" --arg host "${PARTNER_HOST}" --arg port "${PARTNER_PORT}" \
  --arg user "${PARTNER_USER}" --arg password "${SITE_PASSWORD}" --arg secure "${SECURE}" \
  '{name: "example_untested", account: $account, protocol: $protocol, host: $host, port: $port,
    username: $user, password: $password, usePassword: "true"}
   + (if $secure == "true" then {isSecure: "true"} else {} end)')

printf "Testing %s://%s:%s as %s...\n" "${PROTOCOL}" "${PARTNER_HOST}" "${PARTNER_PORT}" "${PARTNER_USER}"
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
