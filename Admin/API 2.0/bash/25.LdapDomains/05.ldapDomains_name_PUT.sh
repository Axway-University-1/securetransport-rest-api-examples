#!/bin/bash
# ==============================================================================
# Script Name: 05.ldapDomains_name_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script replaces an LDAP domain using the `/ldapDomains/{name}` endpoint with PUT: it
# reads the domain, changes its description, and sends the whole domain back.
#
# Usage:
# ./05.ldapDomains_name_PUT.sh [NAME [DESCRIPTION]]
#
#   NAME         the domain (default example_ldap)
#   DESCRIPTION  the new description (default "Replaced by 05.ldapDomains_name_PUT.sh")
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It prints the description before, to put back with.
# - Confirmed directly: the body read back, with the bind password still encrypted,
#   is accepted and keeps the password. A new password sent as plain text is encrypted;
#   a body without any password answers 400 "Please specify the Bind DN password."
# - Confirmed directly: a PUT whose body has another name RENAMES the domain (the old
#   name is gone). This script sets the name back to NAME, so it cannot rename.
# - metadata is read back and dropped; the answer is 204.
# - Requires `jq`, which URL-encodes the name and edits the domain.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/ldapDomains"
NAME="${1:-example_ldap}"
DESCRIPTION="${2:-Replaced by 05.ldapDomains_name_PUT.sh}"
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

DOMAIN=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENCODED}" -H "accept: application/json" -H "${REFERER_HEADER}")
if ! printf '%s' "${DOMAIN}" | jq -e '.name' >/dev/null 2>&1; then
    printf "There is no LDAP domain %s.\n" "${NAME}"
    exit 1
fi
printf "The description of %s is now: %s\n" "${NAME}" "$(printf '%s' "${DOMAIN}" | jq -r '.description // ""')"
BODY=$(printf '%s' "${DOMAIN}" | jq -c --arg name "${NAME}" --arg description "${DESCRIPTION}" 'del(.metadata) | .name = $name | .description = $description')

printf "Setting it to: %s\n" "${DESCRIPTION}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/${ENCODED}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
