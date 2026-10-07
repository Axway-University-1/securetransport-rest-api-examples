#!/bin/bash
# ==============================================================================
# Script Name: 04.accessPolicies_id_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads one database access policy, using the
# `/accessPolicies/{id}` endpoint. It demonstrates:
# - Reading the whole rule
# - Reading some fields only, with fields=
#
# Usage:
# ./04.accessPolicies_id_GET.sh [ID]
#
#   ID  the rule's id, its line in pg_hba.conf (default: the rule
#       02.accessPolicies_POST.sh adds, looked up now)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Only for a server on the embedded PostgreSQL database.
# - An id is a position, and the ones after a deleted rule move up. Look a rule
#   up just before using its id.
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

printf "Rule %s:\n" "${POLICY_ID}"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${POLICY_ID}" \
  -H "accept: application/json" -H "${REFERER_HEADER}"

printf "\n\nOnly its database, user and method:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${POLICY_ID}?fields=database,user,authMethod" \
  -H "accept: application/json" -H "${REFERER_HEADER}"
printf "\n"
