#!/bin/bash
# ==============================================================================
# Script Name: 04.icapServers_name_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script reads one ICAP server using the `/icapServers/{name}` endpoint: its
# address, type, limits, what it does when it cannot be reached, and its scan policy.
#
# Usage:
# ./04.icapServers_name_GET.sh [NAME]
#
#   NAME  the server (default example_icap)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The name goes into the path URL-encoded once, with jq's @uri.
# - The settings come in groups: basicSettings, scanFilteringSettings,
#   headerSettings, advancedConnectionSettings and advancedIcapSettings.
# - Confirmed directly: the businessUnits link in metadata, businessUnits?icapServer=,
#   filters nothing: every value lists every unit. This script reads the units'
#   enabledIcapServers itself, which is what says whose transfers the server scans
#   (the first 500 units).
# - Requires `jq`, which URL-encodes the name and prints the summary.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/icapServers"
NAME="${1:-example_icap}"
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
  "  \(.basicSettings.name): \(.basicSettings.type) \(.basicSettings.url), \(if .serverEnabled then "enabled" else "disabled" end)",
  "  files up to \(.basicSettings.maxSize) MB, preview \(.basicSettings.previewSize) KB",
  "  when it cannot be reached: \(if .basicSettings.denyOnConnectionError then "the transfer is denied" else "the transfer goes on" end)",
  "  scan policy: \(if (.scanFilteringSettings.policyExpression // "") == "" then "none, every transfer" else .scanFilteringSettings.policyExpression end)"'

printf "\nBusiness units that enable it, so whose transfers it scans:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/businessUnits" --data-urlencode "limit=500" \
  --data-urlencode "fields=name,enabledIcapServers" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r --arg name "${NAME}" '(.result // [])[] | select((.enabledIcapServers // []) | index($name)) | "  " + .name'
