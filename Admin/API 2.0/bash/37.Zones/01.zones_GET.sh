#!/bin/bash
# ==============================================================================
# Script Name: 01.zones_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script retrieves network zones using the `/zones` endpoint.
# It demonstrates:
# - The number of zones on the server
# - The zone matching a name, or every zone, one line each: default, number of edges, description
# - Only the default zone, if there is one
#
# Usage:
# ./01.zones_GET.sh [NAME]
#
#   NAME  list only the zone with this exact name (default every zone)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A zone is a NETWORK ZONE (a DMZ zone): it describes where the server's protocol servers are reached from. The lab has one,
#   `Private` ("This network zone holds the information for back ends", one edge `Host` with the lab's own FTP, SSH, HTTP, ADMIN,
#   AS2 and PESIT ports); a DMZ zone lists its edge servers in `edges` (title, addresses, protocols with ports, proxies). A zone is
#   addressed by its NAME in the path, and the name is case sensitive (`Private` is found, `private` is a 404). Never change or
#   delete `Private`: the examples default to an `example_*` zone, and the ones that change something need the name.
# - Confirmed directly: the answer is `{resultSet, result}`. `name=` is EXACT and case sensitive (no `*`: `example*` and `EXAMPLE_ZONE` find
#   nothing), and this script also keeps only the zone whose name is exactly NAME. `isDefault=` takes true or false (another text lists every
#   zone). `description=`, `publicURLPrefix=`, `isDnsResolutionEnabled=` and the `edges.*` filters (`edges.title`, `edges.protocols.port`,
#   `edges.protocols.streamingProtocol`, `edges.ipAddresses.ipAddress`, `edges.proxies.username`, `edges.enabledProxy`) work, exactly; an unknown
#   filter is ignored (200), but `edges.proxies.isUsePassword=` answers 403 "unable to comply". `limit=0` lists all, a negative one is 400 "The limit
#   should be a positive number or 0.", `limit=abc` and a negative `offset` are 400; `limit=1&offset=N` walked three zones once each. `fields=` keeps
#   the keys named; an unknown one is 400 "Field bogus does not exist.".
# - Requires `jq`, which prints one line per zone.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
#   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
# - Exit codes: 0 when every answer is 200, 1 otherwise, 2 when there is more than one argument (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/zones"
NAME="$1"
if [ "$#" -gt 1 ]; then
    printf "Usage: ./01.zones_GET.sh [NAME]\n"
    exit 2
fi

# st_get CURL_ARGUMENTS...: a GET of the URL given (with any curl options, such as -G --data-urlencode ...). The answer
# is left in RESPONSE. A status other than 200 ends the script with exit 1, after printing the status and the answer.
st_get() {
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "$@" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "HTTP %s\n" "${HTTP_CODE}"
        [ -n "${RESPONSE}" ] && printf '%s\n' "${RESPONSE}"
        exit 1
    fi
}

printf "Zones on the server: "
st_get "${MAIN_URL}?limit=1&fields=name"
printf '%s\n' "${RESPONSE}" | jq -r '.resultSet.totalCount'

LINE='"  \(.name)  default \(.isDefault)  edges \(.edges | length)  \(.description // "-")"'
NAME_FILTER=()
[ -n "${NAME}" ] && NAME_FILTER=(--data-urlencode "name=${NAME}")

printf "\nThe zones named %s: name, default, edges, description:\n" "${NAME:-(any)}"
st_get -G "${MAIN_URL}" "${NAME_FILTER[@]}" --data-urlencode "limit=0"
printf '%s\n' "${RESPONSE}" | jq -r --arg name "${NAME}" "(.result // [])[] | select(\$name == \"\" or .name == \$name) | ${LINE}"

printf "\nThe default zone:\n"
st_get -G "${MAIN_URL}" --data-urlencode "isDefault=true" --data-urlencode "limit=0"
printf '%s\n' "${RESPONSE}" | jq -r "(.result // [])[] | select(.isDefault) | ${LINE}"
