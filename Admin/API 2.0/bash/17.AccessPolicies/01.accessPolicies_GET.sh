#!/bin/bash
# ==============================================================================
# Script Name: 01.accessPolicies_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the database access policies using the `/accessPolicies`
# endpoint. They are the rules of the embedded PostgreSQL database's
# pg_hba.conf file: which connections, to which database, as which user, from
# which address, are allowed and how they authenticate. It demonstrates:
# - Listing every rule, in the order the database reads them
# - Asking for some fields only, with fields=
#
# Usage:
# ./01.accessPolicies_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Only for a server on the embedded PostgreSQL database.
# - Confirmed directly: the answer is a plain JSON array, not the
#   {"result": [...]} the API reference shows.
# - A rule's id is its line in the file. The database uses the first rule that
#   matches a connection, so the order matters.
# - Requires `jq`, which prints one rule per line.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

printf "Every database access policy, in the order they are read:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accessPolicies" \
  -H "accept: application/json" -H "${REFERER_HEADER}"

printf "\n\nThe same, one line each: id, connection type, database, user, address, method:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET \
  "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accessPolicies?fields=id,connectionType,database,user,address,authMethod" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '.[] | "  \(.id)  \(.connectionType)  \(.database)  \(.user)  \(.address // "-")  \(.authMethod)"'
