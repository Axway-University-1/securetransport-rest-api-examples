#!/bin/bash
# ==============================================================================
# Script Name: 04.logs_audit_GET_csv.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script exports the audit log as a CSV file using the `/logs/audit` endpoint, asking for
# text/csv in place of JSON.
#
# Usage:
# ./04.logs_audit_GET_csv.sh [OUTPUT [HOURS]]
#
#   OUTPUT  the file to write (default audit_log.csv)
#   HOURS   how far back, in whole hours (default 24)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: the same endpoint answers text/csv when asked, with a header row:
#   User Name, Remote Host, User Agent, Date Modified, Object Type, Object Identifier, Object
#   String, Id, Object Zone, Object Zone Node, Object Name, Operation Type, Node Name,
#   Description. Asking for application/xml answers 406.
# - At most 1000 entries are asked for; narrow HOURS for a busy server.
# - The file is written to the current folder, and holds object texts: handle it as the audit
#   log itself.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/logs/audit"
OUTPUT="${1:-audit_log.csv}"
HOURS="${2:-24}"
[[ "${HOURS}" =~ ^[1-9][0-9]*$ ]] || { printf "HOURS must be a whole number of 1 or more: %s\n" "${HOURS}"; exit 2; }

printf "Exporting the last %s hour(s) to %s...\n" "${HOURS}" "${OUTPUT}"
HTTP_CODE=$(curl -s -k -G -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}" --data-urlencode "duration=${HOURS}" --data-urlencode "limit=1000" \
  -H "accept: text/csv" -H "${REFERER_HEADER}" -o "${OUTPUT}" -w "%{http_code}")
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "200" ]; then
    cat "${OUTPUT}"
    printf "\n"
    rm -f "${OUTPUT}"
    exit 1
fi
printf "Wrote %s: %s line(s) including the header.\n" "${OUTPUT}" "$(wc -l < "${OUTPUT}" | tr -d ' ')"
printf "Its header: %s\n" "$(head -n 1 "${OUTPUT}")"
