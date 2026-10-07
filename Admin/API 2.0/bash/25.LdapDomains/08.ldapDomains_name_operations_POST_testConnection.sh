#!/bin/bash
# ==============================================================================
# Script Name: 08.ldapDomains_name_operations_POST_testConnection.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script tests the connection to one server of an LDAP domain using the
# `/ldapDomains/{name}/operations` endpoint with operation=testConnection.
#
# Usage:
# ./08.ldapDomains_name_operations_POST_testConnection.sh [NAME [SERVER_NUMBER]]
#
#   NAME           the domain (default example_ldap)
#   SERVER_NUMBER  which of its servers, counting from 1 (default 1)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The server is named by its id, which the script looks up in the domain.
# - Confirmed directly: the answer is 200 whether or not it worked; the message says
#   "Successful Connection." or "Connection failed." This script exits 1 for a failure.
# - Confirmed directly: it only opens a connection to the host and port, and sends
#   nothing: it does not bind or search. A directory that accepts connections but would
#   refuse the bind account still reads as successful.
# - tests/integration/lib/dummy_servers.py has a TcpSink that can be the "directory".
# - Requires `jq`, which looks the server up and prints the message.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/ldapDomains"
NAME="${1:-example_ldap}"
NUMBER="${2:-1}"
[[ "${NUMBER}" =~ ^[1-9][0-9]*$ ]] || { printf "SERVER_NUMBER is 1 or more: %s\n" "${NUMBER}"; exit 2; }
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

SERVER_ID=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENCODED}" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r --argjson n "${NUMBER}" '.ldapServers[$n - 1].id // empty' 2>/dev/null)
if [ -z "${SERVER_ID}" ]; then
    printf "The LDAP domain %s has no server number %s.\n" "${NAME}" "${NUMBER}"
    exit 1
fi
BODY=$(jq -cn --arg id "${SERVER_ID}" '{id: $id}')

printf "Testing the connection to server %s of %s...\n" "${NUMBER}" "${NAME}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}/${ENCODED}/operations?operation=testConnection" -H "accept: application/json" \
  -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s: " "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
MESSAGE=$(printf '%s' "${RESPONSE}" | jq -r '.message')
printf "%s\n" "${MESSAGE}"
[[ "${MESSAGE}" == Successful* ]]
