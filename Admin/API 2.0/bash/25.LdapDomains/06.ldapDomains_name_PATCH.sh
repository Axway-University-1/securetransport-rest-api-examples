#!/bin/bash
# ==============================================================================
# Script Name: 06.ldapDomains_name_PATCH.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script changes an LDAP domain using the `/ldapDomains/{name}` endpoint with PATCH:
# its description, and the port of its first server.
#
# Usage:
# ./06.ldapDomains_name_PATCH.sh [NAME [DESCRIPTION [PORT]]]
#
#   NAME         the domain (default example_ldap)
#   DESCRIPTION  the new description (default "Patched by 06.ldapDomains_name_PATCH.sh")
#   PORT         the new port of the first server (optional: left as it is)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A list is addressed by index: /ldapServers/0/port is the first server.
# - Confirmed directly: adding to /ldapServers/- takes order 1 and moves the others down.
# - Confirmed directly: /isDefault can be set to true, and then cannot be set back to
#   false (400 "You cannot set precedence on non default domain"). It is not used here.
# - A PATCH of /name renames the domain, as a PUT does.
# - Requires `jq`, which URL-encodes the name and builds the patch.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/ldapDomains"
NAME="${1:-example_ldap}"
DESCRIPTION="${2:-Patched by 06.ldapDomains_name_PATCH.sh}"
PORT="$3"
if [ -n "${PORT}" ] && { ! [[ "${PORT}" =~ ^[0-9]+$ ]] || [ "${PORT}" -gt 65535 ]; }; then
    printf "PORT is a number up to 65535: %s\n" "${PORT}"
    exit 2
fi
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

BODY=$(jq -cn --arg description "${DESCRIPTION}" --arg port "${PORT}" \
  '[{op: "replace", path: "/description", value: $description}] + (if $port != "" then [{op: "replace", path: "/ldapServers/0/port", value: ($port | tonumber)}] else [] end)')

PORT_TEXT=""
[ -n "${PORT}" ] && PORT_TEXT=" and the port of the first server (${PORT})"
printf "Patching %s: description%s...\n" "${NAME}" "${PORT_TEXT}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/${ENCODED}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
