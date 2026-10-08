#!/bin/bash
# ==============================================================================
# Script Name: 02.accessPolicies_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script adds a database access policy using the `/accessPolicies`
# endpoint: one rule of the embedded PostgreSQL database's pg_hba.conf file.
#
# Usage:
# ./02.accessPolicies_POST.sh
#
# Risk: config
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Only for a server on the embedded PostgreSQL database.
# - The rule here rejects connections to a database named example_db, as
#   example_user, from the server itself. No such database exists, so it
#   changes nothing. Change it carefully: a wrong rule can lock SecureTransport
#   out of its own database.
# - Confirmed directly: the rule is added at the end of the file, and its id -
#   its line - comes back in the Location header. A rule that is already there
#   can be added again.
# - connectionType: local, host, hostssl, hostnossl, hostgssenc, hostnogssenc.
#   authMethod: trust, reject, scram-sha-256, md5, password. address, or
#   ipAddress and ipMask, give the client addresses.
# - 06.accessPolicies_id_DELETE.sh removes it again.
# - Requires `jq`, which builds the request body.
# - Confirmed directly: a success is 201 with no body and the new rule's address in `Location`. A refusal is 400 with every reason
#   in `validationErrors` ("Valid auth method values are: reject, trust, scram-sha-256, md5, password."), and changes nothing.
# - Exit codes: 0 when the rule was added (201), 1 when the server refuses.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

DATABASE="example_db"
USER_NAME="example_user"

# A file for the response headers, which hold the new rule's address
HEADERS_FILE=$(mktemp)
trap 'rm -f "${HEADERS_FILE}"' EXIT

BODY=$(jq -cn --arg db "${DATABASE}" --arg user "${USER_NAME}" \
  '{connectionType: "host", database: $db, user: $user, address: "samehost", authMethod: "reject"}')

printf "Adding a rule that rejects %s on %s, from the server itself...\n" "${USER_NAME}" "${DATABASE}"
RESPONSE=$(curl -s -D "${HEADERS_FILE}" -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accessPolicies" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"

printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "201" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
LOCATION=$(sed -n 's/^[Ll]ocation: *//p' "${HEADERS_FILE}" | tr -d '\r')
if [ -n "${LOCATION}" ]; then
    printf "The new rule is number %s.\n" "$(basename "${LOCATION}")"
fi
