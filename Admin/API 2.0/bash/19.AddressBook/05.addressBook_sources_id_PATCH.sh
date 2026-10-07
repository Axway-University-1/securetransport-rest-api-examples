#!/bin/bash
# ==============================================================================
# Script Name: 05.addressBook_sources_id_PATCH.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script changes one property of an address book source, using the
# `/addressBook/sources/{id}` endpoint with PATCH: a JSON Patch document that
# replaces the number of entries a page of the address book shows
# (MaxPageEntries). Unlike PUT (04.addressBook_sources_id_PUT.sh), it sends
# only what changes.
#
# Usage:
# ./05.addressBook_sources_id_PATCH.sh MAX_PAGE_ENTRIES [SOURCE]
#
#   MAX_PAGE_ENTRIES  the new page size
#   SOURCE            the source's name (default LDAP)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It prints the value before the change, to put it back with.
# - replace needs the property to exist already; add sets one that does not.
# - Confirmed directly: a success answers 204, with no body.
# - Requires `jq`, which reads the source and builds the patch.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/addressBook/sources"

MAX_PAGE_ENTRIES="$1"
SOURCE="${2:-LDAP}"
[[ "${MAX_PAGE_ENTRIES}" =~ ^[1-9][0-9]*$ ]] \
    || { printf "Usage: ./05.addressBook_sources_id_PATCH.sh MAX_PAGE_ENTRIES [SOURCE]\n"; exit 2; }

SOURCE_JSON=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "name=${SOURCE}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -c '.result[0] // empty')
if [ -z "${SOURCE_JSON}" ]; then
    printf "There is no address book source named %s.\n" "${SOURCE}"
    exit 1
fi
SOURCE_ID=$(printf '%s' "${SOURCE_JSON}" | jq -r '.id')
printf "MaxPageEntries of %s is now %s.\n" "${SOURCE}" "$(printf '%s' "${SOURCE_JSON}" | jq -r '.customProperties.MaxPageEntries // "not set"')"

# replace when the property is there, add when it is not
OPERATION=$(printf '%s' "${SOURCE_JSON}" | jq -r 'if .customProperties | has("MaxPageEntries") then "replace" else "add" end')
BODY=$(jq -n --arg op "${OPERATION}" --arg n "${MAX_PAGE_ENTRIES}" '[{op: $op, path: "/customProperties/MaxPageEntries", value: $n}]')

printf "Setting it to %s...\n" "${MAX_PAGE_ENTRIES}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/${SOURCE_ID}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "204" ]
