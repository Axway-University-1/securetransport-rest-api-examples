#!/bin/bash
# ==============================================================================
# Script Name: 02.zones_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script creates a network zone using the `/zones` endpoint.
# It demonstrates:
# - A zone with a name and a description, and no edge
# - Optionally one edge: a title, an address and one SSH protocol with a port (left disabled)
# - Reading the new zone's address from the Location header
#
# Usage:
# ./02.zones_POST.sh [NAME [DESCRIPTION [EDGE_TITLE [EDGE_ADDRESS [EDGE_PORT]]]]]
#
#   NAME          the zone's name (default example_zone); not \ / ; ' , at most 255 characters
#   DESCRIPTION   its description (default "Created by the examples"), at most 255 characters
#   EDGE_TITLE    add one edge with this title (same rules as NAME)
#   EDGE_ADDRESS  the edge's address, a host name or an address (needs EDGE_TITLE)
#   EDGE_PORT     an SSH protocol on this port, 1024 to 65535, left disabled (needs EDGE_TITLE)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A zone is a NETWORK ZONE (a DMZ zone): it describes where the server's protocol servers are reached from. The lab has one,
#   `Private` ("This network zone holds the information for back ends", one edge `Host` with the lab's own FTP, SSH, HTTP, ADMIN,
#   AS2 and PESIT ports); a DMZ zone lists its edge servers in `edges` (title, addresses, protocols with ports, proxies). A zone is
#   addressed by its NAME in the path, and the name is case sensitive (`Private` is found, `private` is a 404). Never change or
#   delete `Private`: the examples default to an `example_*` zone, and the ones that change something need the name.
# - Run 07.zones_name_DELETE.sh to remove what this creates. A zone that only describes an edge changes nothing by itself: no
#   listener is opened and no traffic is routed until a business unit names it (see 04.zones_name_GET.sh). `isDefault` is not sent, so the zone
#   is not the default (a default zone is one the server applies when a new object names none; see 05 and 06).
# - Confirmed directly: a success is 201 with the zone's address in `Location` and no body. Only `name` is required (`{}` is 400 "name must not be
#   null"). A duplicate is **400** "The zone name is not unique.", not the 409 the reference lists, and names are case sensitive (`example_a`
#   and `EXAMPLE_A` coexist). A name with `/`, `\`, `;` or `'` is 400, one of 256 characters is 400 "name length must be between 1 and 255 characters"; a
#   space, an accent and a dash are accepted (the Location then holds the name URL-encoded). An unknown field is 400 "Unsupported parameter - bogus".
#   An edge needs a `title` (400 "edges[0].title must not be null"; the same characters as a name); its `deploymentSite` defaults to `Prod`, `enabledProxy`
#   and a protocol's `isEnabled` to false, and the edge gets an `edgeId`. A protocol needs `streamingProtocol` (HTTP, FTP, AS2, SSH, PESIT or ADMIN; another
#   value is 403 "unable to comply") and a `port` from 1024 (400 "Port number for protocol HTTP must be from 1024 to 65535"). A protocol's `sslAlias` that is not a
#   certificate of the server is 400 "Error creating zone". The protocols come back in the server's order, not the one sent. A proxy
#   (`proxyProtocol` SOCKS_PROXY or HTTP_PROXY, `port`, `username`, `isUsePassword`, `password`) is accepted and its password is never read back (`null`).
#   Left out of this script on purpose: more than one edge, the proxies and the extra fields; send them in a body of your own.
# - Requires `jq`, which builds the request body.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/zones"
NAME="${1:-example_zone}"
DESCRIPTION="${2:-Created by the examples}"
EDGE_TITLE="$3"
EDGE_ADDRESS="$4"
EDGE_PORT="$5"
HEADERS_FILE=$(mktemp)
trap 'rm -f "${HEADERS_FILE}"' EXIT

# a name or a title: 1 to 255 characters, none of \ / ; '
valid_name() {
    case "$1" in
        ''|*/*|*\\*|*';'*|*"'"*) return 1 ;;
    esac
    [ "${#1}" -le 255 ]
}
valid_name "${NAME}" || { printf "NAME must be 1 to 255 characters, none of \\ / ; ' .\n"; exit 2; }
[ "${#DESCRIPTION}" -le 255 ] || { printf "DESCRIPTION is 255 characters at most.\n"; exit 2; }
if [ -n "${EDGE_TITLE}" ]; then
    valid_name "${EDGE_TITLE}" || { printf "EDGE_TITLE must be 1 to 255 characters, none of \\ / ; ' .\n"; exit 2; }
elif [ -n "${EDGE_ADDRESS}" ] || [ -n "${EDGE_PORT}" ]; then
    printf "EDGE_ADDRESS and EDGE_PORT need an EDGE_TITLE.\n"
    exit 2
fi
if [ -n "${EDGE_PORT}" ]; then
    [[ "${EDGE_PORT}" =~ ^[0-9]+$ ]] && [ "${EDGE_PORT}" -ge 1024 ] && [ "${EDGE_PORT}" -le 65535 ] \
        || { printf "EDGE_PORT is a number from 1024 to 65535, not %s.\n" "${EDGE_PORT}"; exit 2; }
fi

BODY=$(jq -cn --arg name "${NAME}" --arg description "${DESCRIPTION}" --arg title "${EDGE_TITLE}" --arg address "${EDGE_ADDRESS}" --arg port "${EDGE_PORT}" '
  {name: $name, description: $description}
  + (if $title != "" then {edges: [{title: $title}
      + (if $address != "" then {ipAddresses: [{ipAddress: $address}]} else {} end)
      + (if $port != "" then {protocols: [{streamingProtocol: "SSH", port: ($port | tonumber), isEnabled: false}]} else {} end)]} else {} end)')

printf "Creating the zone %s...\n" "${NAME}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -D "${HEADERS_FILE}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "201" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
printf "It is at %s\n" "$(sed -n 's/^[Ll]ocation: *//p' "${HEADERS_FILE}" | tr -d '\r')"
