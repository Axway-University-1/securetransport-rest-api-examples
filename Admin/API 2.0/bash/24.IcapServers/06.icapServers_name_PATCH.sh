#!/bin/bash
# ==============================================================================
# Script Name: 06.icapServers_name_PATCH.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script changes an ICAP server using the `/icapServers/{name}` endpoint with PATCH:
# it switches the server on or off, and what happens to a transfer when the server
# cannot be reached.
#
# Usage:
# ./06.icapServers_name_PATCH.sh [NAME [ENABLED [DENY_ON_ERROR]]]
#
#   NAME           the server (default example_icap)
#   ENABLED        true to scan, false to stop (default false)
#   DENY_ON_ERROR  true to deny a transfer when the server cannot be reached, false to
#                  let it go on (optional: left as it is)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - An ICAP server scans transfers only for the business units that list it in
#   enabledIcapServers (see 12.BusinessUnits), and only while it is enabled.
# - Confirmed directly: with the server enabled and reachable, a file it blocks is
#   refused: the transfer ends Failed and the file is removed. With the server
#   unreachable, DENY_ON_ERROR true refuses every file of those business units, and
#   false lets them through. Disabled, nothing is scanned.
# - Confirmed directly: scanning is not instant. The file is listed first, and a
#   blocked one disappears within a few seconds.
# - A PATCH of /basicSettings/name renames the server, as a PUT does.
# - Requires `jq`, which URL-encodes the name and builds the patch.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/icapServers"
NAME="${1:-example_icap}"
ENABLED="${2:-false}"
DENY="$3"
[[ "${ENABLED}" =~ ^(true|false)$ ]] || { printf "ENABLED is true or false, not %s.\n" "${ENABLED}"; exit 2; }
if [ -n "${DENY}" ] && ! [[ "${DENY}" =~ ^(true|false)$ ]]; then
    printf "DENY_ON_ERROR is true or false, not %s.\n" "${DENY}"
    exit 2
fi
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

BODY=$(jq -cn --argjson enabled "${ENABLED}" --arg deny "${DENY}" \
  '[{op: "replace", path: "/serverEnabled", value: $enabled}] + (if $deny != "" then [{op: "replace", path: "/basicSettings/denyOnConnectionError", value: ($deny == "true")}] else [] end)')

printf "Setting %s: enabled %s%s...\n" "${NAME}" "${ENABLED}" "${DENY:+, deny when unreachable ${DENY}}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/${ENCODED}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
