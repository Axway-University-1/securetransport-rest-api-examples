#!/bin/bash
# ==============================================================================
# Script Name: 01.daemons_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Stopping and starting, step 1: look first, and keep a copy. GET /daemons gives the status of every daemon, GET /servers says which servers are active.
# What it finds is saved in this folder (state.local.daemons.json and state.local.servers.json), so that step 06 can say whether anything is different
# afterwards and 99.cleanup_DELETE.sh can put back what is not as it was.
#
# Usage:
# ./01.daemons_GET.sh
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/03.Connect/01.daemons_GET.sh and 06.servers_GET.sh. The saving of the two answers is written for this use case.
# - The daemons answer is one object with a key for each daemon (ftpStatus, httpStatus, ...). The servers answer is a list: each server has the protocol of its daemon.
#   A daemon that is Running does not mean its servers are active: they are separate objects.
# - A second run replaces the copy. Run it again only when everything is as you want it to be afterwards.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./01.daemons_GET.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
st_session

result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/daemons" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "GET /daemons: HTTP ${code}"
[[ "${code}" == 200 ]] || { echo "${result%???}"; exit 1; }
DAEMONS_JSON="${result%???}"
printf '%s' "${DAEMONS_JSON}" | jq -r 'to_entries[] | "  \(.key | sub("Status$"; ""))\t\(.value)"'

uc_read_servers || exit 1
echo "GET /servers: HTTP 200"
printf '%s' "${SERVERS_JSON}" | jq -r '.[] | "  \(.protocol)\t\(.serverName)\t\(if .isActive then "active" else "not active" end)"'

printf '%s' "${DAEMONS_JSON}" | jq -S . > "${DAEMONS_STATE}"
printf '%s' "${SERVERS_JSON}" | jq -S 'sort_by(.serverName)' > "${SERVERS_STATE}"
printf "Saved: %s and %s.\n" "$(basename "${DAEMONS_STATE}")" "$(basename "${SERVERS_STATE}")"
