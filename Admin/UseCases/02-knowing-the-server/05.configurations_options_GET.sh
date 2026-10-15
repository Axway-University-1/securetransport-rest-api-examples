#!/bin/bash
# ==============================================================================
# Script Name: 05.configurations_options_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Finding one setting among a thousand. GET /configurations/options takes a name with * as a wildcard. This counts them all, then looks for a pattern and prints name and value, then counts the ones changed from their default.
#
# Usage:
# ./05.configurations_options_GET.sh [PATTERN]
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/13.Configurations/03.configurations_options_GET.sh.
# - PATTERN is an option name, * matches anything (default Webservices.Admin.*).
# - values is always a list, even for an option with one value; an encrypted option shows no secret.
# - limit=1 is the cheap way to count: totalCount says how many there are.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
PATTERN="${1:-Webservices.Admin.*}"
st_session

# count QUERY...: totalCount of a query
count() {
    local result code
    result=$(curl -k -s -G -w "%{http_code}" -b "${JAR}" "${ST_URL}/configurations/options" "$@" --data-urlencode "limit=1" -H "accept: application/json" -H "Referer: ${REFERER}")
    code=${result: -3}
    [[ "${code}" == 200 ]] || { echo "HTTP ${code}: ${result%???}" >&2; exit 1; }
    echo "${result%???}" | jq -r '.resultSet.totalCount'
}

echo "Options in all:          $(count)"
echo "Changed from default:    $(count --data-urlencode "isModified=true")"
echo "Matching ${PATTERN}: $(count --data-urlencode "name=${PATTERN}")"
result=$(curl -k -s -G -w "%{http_code}" -b "${JAR}" "${ST_URL}/configurations/options" \
         --data-urlencode "name=${PATTERN}" --data-urlencode "limit=10" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
[[ "${code}" == 200 ]] || { echo "HTTP ${code}: ${result%???}"; exit 1; }
echo "${result%???}" | jq -r '.result[] | "  \(.name) = \(.values | join(","))"' 
