#!/bin/bash
# ==============================================================================
# Script Name: 04.ldapDomains_name_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script reads one LDAP domain using the `/ldapDomains/{name}` endpoint: its servers
# with their ids, the bind account, where it searches, and the attributes it maps.
#
# Usage:
# ./04.ldapDomains_name_GET.sh [NAME]
#
#   NAME  the domain (default example_ldap)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The name goes into the path URL-encoded once, with jq's @uri.
# - Confirmed directly: the bind password reads back encrypted, {AES128}..., never as it
#   was sent. That text can be sent back unchanged in a PUT, which keeps the password.
# - Each server has an id of its own: the one 08.ldapDomains_name_operations_POST_testConnection.sh
#   needs. The domain's id, at the end of Location when it was created, is not the name.
# - Requires `jq`, which URL-encodes the name and prints the summary.
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

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENCODED}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read %s (HTTP %s): " "${NAME}" "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
printf '%s\n' "${RESPONSE}"
printf "\nIn short:\n"
printf '%s' "${RESPONSE}" | jq -r '
  "  \(.name): LDAP version \(.protocolVersion), \(if .isDefault then "the default domain" else "not the default" end)",
  (.ldapServers[] | "  server \(.order): \(.host):\(.port), id \(.id)"),
  "  bind as \(.bindDn), search \(.ldapSearches.baseDn) by \(.ldapSearches.searchAttribute)",
  "  ssl \(.sslEnabled), tls \(.tlsEnabled), referrals \(.referralsAllowed), anonymous binds \(.anonymousBindsAllowed)"'
