#!/bin/bash
# ==============================================================================
# Script Name: 02.icapServers_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script adds an ICAP server using the `/icapServers` endpoint: its name, address
# and which transfers it scans. It is created disabled, so that nothing is sent to it
# until 06.icapServers_name_PATCH.sh enables it.
#
# Usage:
# ./02.icapServers_POST.sh [NAME [URL [TYPE]]]
#
#   NAME  the server's name (default example_icap)
#   URL   icap://host:port/service (default icap://icap.example.com:1344/AVSCAN)
#   TYPE  INCOMING, OUTGOING or BOTH: which transfers it scans (default INCOMING)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - An ICAP server scans transfers only for the business units that list it in
#   enabledIcapServers (see 12.BusinessUnits), and only while it is enabled.
# - INCOMING scans uploads, OUTGOING downloads, BOTH both. maxSize (MB, 0 or less is
#   unlimited) and previewSize (KB) are required; this script sends 10 and 1024.
# - The answer is 201 with the new server's address in Location, and no body. A name
#   that exists answers 409 "already exist"; one with / ; or ' answers 400.
# - Confirmed directly: the server does not check the URL: http://x is accepted. This
#   script requires icap://, so a typo is caught here.
# - Confirmed directly: with scanning on, SecureTransport asks the server OPTIONS, then
#   sends each file as a REQMOD request, with a preview of previewSize KB first.
#   tests/integration/lib/dummy_servers.py has a FakeIcap that can stand in for one.
# - 03.icapServers_name_HEAD.sh to 07.icapServers_name_DELETE.sh check, read, change,
#   switch on and remove it.
# - Requires `jq`, which builds the body.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/icapServers"
NAME="${1:-example_icap}"
URL="${2:-icap://icap.example.com:1344/AVSCAN}"
TYPE="${3:-INCOMING}"
HEADERS_FILE=$(mktemp)
trap 'rm -f "${HEADERS_FILE}"' EXIT
if [ -z "${NAME// /}" ] || [[ "${NAME}" == *[/\;\']* ]]; then
    printf "NAME must not be blank, or contain / ; or ': %s\n" "${NAME}"
    exit 2
fi
if ! [[ "${URL}" =~ ^icap://[^/]+/.+ ]]; then
    printf "URL is icap://host:port/service: %s\n" "${URL}"
    exit 2
fi
if ! [[ "${TYPE}" =~ ^(INCOMING|OUTGOING|BOTH)$ ]]; then
    printf "TYPE is INCOMING, OUTGOING or BOTH, not %s.\n" "${TYPE}"
    exit 2
fi

BODY=$(jq -cn --arg name "${NAME}" --arg url "${URL}" --arg type "${TYPE}" \
  '{serverEnabled: false,
    basicSettings: {name: $name, type: $type, url: $url, maxSize: 10, previewSize: 1024, denyOnConnectionError: false},
    advancedConnectionSettings: {connectionTimeout: 10, readTimeout: 30}}')

printf "Adding the ICAP server %s, %s, scanning %s transfers, disabled...\n" "${NAME}" "${URL}" "${TYPE}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -D "${HEADERS_FILE}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "201" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
printf "It is at %s\n" "$(sed -n 's/^[Ll]ocation: *//p' "${HEADERS_FILE}" | tr -d '\r')"
