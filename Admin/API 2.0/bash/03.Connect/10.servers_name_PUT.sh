#!/bin/bash
# ==============================================================================
# Script Name: 10.servers_name_PUT.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script updates an SSH server configuration using the PUT method via curl.
# It demonstrates:
# - A direct update with a new port
# - A full update using retrieved server data with modified fields
#
# Usage:
# ./10.servers_name_PUT.sh [NAME [PORT]]
#
#   NAME  the SSH server to change (default SSH_TEST_SERVER_1, the one 07.servers_POST.sh creates)
#   PORT  the new port, 1 to 65535 (default 8031)
#
# Risk: config - changes a protocol server
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The PUT method replaces the entire object, so all required fields must be included.
# - The server is read first, and the script stops (exit 1) when it does not exist or is not an SSH server: a body
#   that says `ssh` would otherwise be sent to a server of another protocol.
# - It prints the port the server had, to put it back with. THE FIRST PUT IS A FRAGMENT, and a fragment resets what it leaves out: the second
#   call reads the server again and sends the whole object back, with `clientPasswordAuth` set to `default` again; the
#   ciphers and the other lists the fragment emptied stay empty (see Confirmed directly). Use it on a server you can
#   create again, as this one is.
# - Requires `jq`, which is used to edit the retrieved JSON.
# - Confirmed directly: a PUT is 204 with no body. A fragment with only `serverName`, `protocol` and `port` answers 204 and resets
#   `clientPasswordAuth`, `ciphers` and `keyExchangeAlgorithms` to empty text. A PUT of an unknown server is 400 "Could not update
#   server with name X.". (An SSH body sent to an existing server of another protocol was not tried: the script reads the protocol first and refuses.)
# - Exit codes: 0 when both PUTs were 204, 1 when the server refuses a call, 2 when an argument is wrong (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
NAME="${1:-SSH_TEST_SERVER_1}"
NEW_PORT="${2:-8031}"
USAGE="Usage: ./10.servers_name_PUT.sh [NAME [PORT]]"

if [ "$#" -gt 2 ] || [ -z "${NAME}" ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
if ! [[ "${NEW_PORT}" =~ ^[0-9]+$ ]] || [ "${NEW_PORT}" -lt 1 ] || [ "${NEW_PORT}" -gt 65535 ]; then
    printf "PORT is a number from 1 to 65535, not %s. Nothing was sent.\n%s\n" "${NEW_PORT}" "${USAGE}"
    exit 2
fi
SERVER_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers/$(jq -rn --arg n "${NAME}" '$n|@uri')"

# The answer to a refused call: the server's own messages, or the text as it is
show_error() { printf '%s' "$1" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "$1"; }

# read_server: puts the server in SERVER_JSON, or says why not and exits 1
read_server() {
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${SERVER_URL}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    SERVER_JSON="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "Could not read the server %s: HTTP %s\n" "${NAME}" "${HTTP_CODE}"
        show_error "${SERVER_JSON}"
        exit 1
    fi
}

read_server
PROTOCOL=$(printf '%s' "${SERVER_JSON}" | jq -r '.protocol // empty')
if [ "${PROTOCOL}" != "ssh" ]; then
    printf "The server %s is a %s server: this script changes SSH servers only. Nothing was changed.\n" "${NAME}" "${PROTOCOL:-unknown}"
    exit 1
fi
printf "The port of %s is now %s (the PUT below sets %s).\n" "${NAME}" "$(printf '%s' "${SERVER_JSON}" | jq -r '.port // "not set"')" "${NEW_PORT}"

# Direct PUT update
BODY=$(jq -cn --arg name "${NAME}" --argjson port "${NEW_PORT}" '{serverName: $name, protocol: "ssh", port: $port}')
printf "Replacing the server with a body of only its name, protocol and port...\n"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${SERVER_URL}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    show_error "${RESPONSE}"
    exit 1
fi

# Retrieve and modify server configuration
read_server

#
# Edit the retrieved object with jq. This targets the exact fields and always
# produces valid JSON, which a text substitution cannot guarantee.
#
BODY=$(printf '%s' "${SERVER_JSON}" | jq -c --argjson newPort "${NEW_PORT}" \
   '.port = $newPort | .clientPasswordAuth = "default"')

printf "Replacing the server with the whole object read back, port %s and clientPasswordAuth default...\n" "${NEW_PORT}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${SERVER_URL}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    show_error "${RESPONSE}"
    exit 1
fi
