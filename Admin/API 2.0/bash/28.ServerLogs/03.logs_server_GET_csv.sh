#!/bin/bash
# ==============================================================================
# Script Name: 03.logs_server_GET_csv.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script exports the server log as a CSV file using the `/logs/server` endpoint, asking for
# text/csv in place of JSON.
#
# Usage:
# ./03.logs_server_GET_csv.sh [OUTPUT [MINUTES [COMPONENT]]]
#
#   OUTPUT     the file to write (default server_log.csv)
#   MINUTES    how far back, in whole minutes (default 60)
#   COMPONENT  one component, for example FTPD (optional)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: the same endpoint answers text/csv when asked, with a header row: Time,
#   Level, Component, Thread, Message, Filename, Class, Method, Line, Account or Login, Stack
#   Trace, Activity, Transferred File, Client Hostname, Edge Hostname, Server Hostname, Node
#   Name, Session ID, Session Start Time, Transfer ID.
# - At most 1000 entries are asked for, oldest first; narrow MINUTES for a busy server.
# - The file is written to the current folder, and holds account names and addresses.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/logs/server"
OUTPUT="${1:-server_log.csv}"
MINUTES="${2:-60}"
COMPONENT="$3"
[[ "${MINUTES}" =~ ^[1-9][0-9]*$ ]] || { printf "MINUTES must be a whole number of 1 or more: %s\n" "${MINUTES}"; exit 2; }
if [ -n "${COMPONENT}" ] && ! [[ "${COMPONENT}" =~ ^(TM|AS2D|SSHD|SOCKS|ADMIN|AUDIT|FTPD|HTTPD|PESITD)$ ]]; then
    printf "Unknown component %s.\n" "${COMPONENT}"
    exit 2
fi

SINCE_EPOCH=$(( $(date +%s) - MINUTES * 60 ))
SINCE=$(date -u -r "${SINCE_EPOCH}" "+%a, %d %b %Y %H:%M:%S GMT" 2>/dev/null || date -u -d "@${SINCE_EPOCH}" "+%a, %d %b %Y %H:%M:%S GMT")
FILTER=()
[ -n "${COMPONENT}" ] && FILTER=(--data-urlencode "component=${COMPONENT}")

printf "Exporting the entries since %s to %s...\n" "${SINCE}" "${OUTPUT}"
HTTP_CODE=$(curl -s -k -G -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}" --data-urlencode "fromDate=${SINCE}" "${FILTER[@]}" --data-urlencode "limit=1000" \
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
