#!/bin/bash
# ==============================================================================
# Script Name: 05.accessPolicies_id_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script replaces a database access policy, using the
# `/accessPolicies/{id}` endpoint with PUT. It demonstrates:
# - Reading the rule, changing one field with jq, and sending the whole rule
#   back
#
# Usage:
# ./05.accessPolicies_id_PUT.sh [AUTH_METHOD]
#
#   AUTH_METHOD  the rule's new authentication method (default scram-sha-256):
#                trust, reject, scram-sha-256, md5 or password
#
# Risk: config
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Only for a server on the embedded PostgreSQL database.
# - It changes the rule 02.accessPolicies_POST.sh adds, looked up now: an id is
#   a position, and the ones after a deleted rule move up.
# - Confirmed directly: a success answers 204, with no body.
# - Requires `jq`, which finds the rule and edits it.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/accessPolicies"

DATABASE="example_db"
USER_NAME="example_user"
AUTH_METHOD="${1:-scram-sha-256}"

POLICY=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -c --arg db "${DATABASE}" --arg user "${USER_NAME}" \
    '[.[] | select(.database == $db and .user == $user)] | last // empty')
if [ -z "${POLICY}" ]; then
    printf "There is no rule for %s on %s. Run 02.accessPolicies_POST.sh first.\n" "${USER_NAME}" "${DATABASE}"
    exit 1
fi
POLICY_ID=$(printf '%s' "${POLICY}" | jq -r '.id')

# The whole rule, with the one field changed
BODY=$(printf '%s' "${POLICY}" | jq -c --arg method "${AUTH_METHOD}" '.authMethod = $method')

printf "Setting rule %s to %s...\n" "${POLICY_ID}" "${AUTH_METHOD}"
curl -s -o /dev/null -w "HTTP %{http_code}\n" -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/${POLICY_ID}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}"
