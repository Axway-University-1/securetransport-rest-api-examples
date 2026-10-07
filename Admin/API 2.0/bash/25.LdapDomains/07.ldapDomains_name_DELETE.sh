#!/bin/bash
# ==============================================================================
# Script Name: 07.ldapDomains_name_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes an LDAP domain using the `/ldapDomains/{name}` endpoint.
#
# Usage:
# ./07.ldapDomains_name_DELETE.sh [NAME]
#
#   NAME  the domain (default example_ldap)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Only delete a domain you added: users that sign in through it can no longer do so.
# - A name that does not exist answers 404 "does not exist".
# - Requires `jq`, which URL-encodes the name.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/ldapDomains"
NAME="${1:-example_ldap}"
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

printf "Deleting the LDAP domain %s...\n" "${NAME}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${ENCODED}" -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
