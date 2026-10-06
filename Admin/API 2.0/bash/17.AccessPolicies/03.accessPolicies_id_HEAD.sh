#!/bin/bash
# ==============================================================================
# Script Name: 03.accessPolicies_id_HEAD.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script checks whether a database access policy exists, using the
# `/accessPolicies/{id}` endpoint with HEAD: 200 when it does, 404 when it does
# not.
#
# Usage:
# ./03.accessPolicies_id_HEAD.sh [ID]
#
#   ID  the rule's id, its line in pg_hba.conf (default: the rule
#       02.accessPolicies_POST.sh adds, looked up now)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Only for a server on the embedded PostgreSQL database.
# - An id is a position, and the ones after a deleted rule move up. Look a rule
#   up just before using its id; an id kept from earlier may name another rule.
# - Requires `jq`, which finds the rule.
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

POLICY_ID="$1"
if [ -z "${POLICY_ID}" ]; then
    POLICY_ID=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" \
      | jq -r --arg db "${DATABASE}" --arg user "${USER_NAME}" \
        '[.[] | select(.database == $db and .user == $user)] | last | .id // empty')
    if [ -z "${POLICY_ID}" ]; then
        printf "There is no rule for %s on %s. Run 02.accessPolicies_POST.sh first.\n" "${USER_NAME}" "${DATABASE}"
        exit 1
    fi
fi

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" --head "${MAIN_URL}/${POLICY_ID}" \
  -H "accept: */*" -H "${REFERER_HEADER}")
if [ "${HTTP_CODE}" = "200" ]; then
    printf "Rule %s exists.\n" "${POLICY_ID}"
else
    printf "Rule %s does not exist (HTTP %s).\n" "${POLICY_ID}" "${HTTP_CODE}"
    exit 1
fi
