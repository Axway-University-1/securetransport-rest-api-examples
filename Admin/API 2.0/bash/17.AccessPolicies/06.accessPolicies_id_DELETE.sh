#!/bin/bash
# ==============================================================================
# Script Name: 06.accessPolicies_id_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes the database access policies 02.accessPolicies_POST.sh
# adds, using the `/accessPolicies/{id}` endpoint. It demonstrates:
# - Looking a rule up by its content, just before deleting it
# - Deleting every matching rule safely, when ids move as rules are deleted
#
# Usage:
# ./06.accessPolicies_id_DELETE.sh
#
# Risk: config
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Only for a server on the embedded PostgreSQL database.
# - Confirmed directly: an id is the rule's line in pg_hba.conf, and the rules
#   after a deleted one move up. Deleting ids found in one listing therefore
#   deletes the wrong rules from the second one on. This script lists the rules
#   again before each delete, and deletes the last match first.
# - Only ever point it at a rule you added: deleting one of the server's own
#   can lock SecureTransport out of its own database.
# - Requires `jq`, which finds the rules.
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

DELETED=0
while true; do
    # Listed again each time: the ids have moved since the last delete
    POLICY_ID=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" \
      | jq -r --arg db "${DATABASE}" --arg user "${USER_NAME}" \
        '[.[] | select(.database == $db and .user == $user)] | last | .id // empty')
    [ -z "${POLICY_ID}" ] && break

    printf "Deleting rule %s...\n" "${POLICY_ID}"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${POLICY_ID}" \
      -H "accept: */*" -H "${REFERER_HEADER}")
    printf "HTTP %s\n" "${HTTP_CODE}"
    [ "${HTTP_CODE}" = "204" ] || exit 1
    DELETED=$((DELETED + 1))
done
printf "Deleted %s rule(s) for %s on %s.\n" "${DELETED}" "${USER_NAME}" "${DATABASE}"
