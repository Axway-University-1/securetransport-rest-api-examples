#!/bin/bash
# ==============================================================================
# Script Name: 11.servers_name_PATCH.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script demonstrates how to PATCH an SSH server configuration using curl.
# It performs:
# - A PATCH to update the port
# - A PATCH to remove RSA keys from the publicKeys field
#
# Usage:
# ./11.servers_name_PATCH.sh [NAME [PORT]]
#
#   NAME  the SSH server to change (default SSH_TEST_SERVER_1, the one 07.servers_POST.sh creates)
#   PORT  the new port, 1 to 65535 (default 8026)
#
# Risk: config - changes a protocol server
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The PATCH method allows partial updates to specific fields. The body is a JSON Patch: an ARRAY of operations,
#   even for one. An object on its own is refused (400 "Incorrect JSON format").
# - The server is read first, and the script stops (exit 1) when it does not exist or is not an SSH server. It prints the port
#   and the public keys the server had, to put them back with.
# - `publicKeys` is ONE text, the algorithms separated by commas (`ssh-rsa,x509v3-rsa2048-sha256,...`), not an array: jq splits it,
#   drops every entry that has `rsa` in it, and joins the rest, which is sent with `replace` on `/publicKeys`. When no entry has `rsa`
#   in it nothing is patched for the keys, and the script says so.
# - Requires `jq`, which builds both patches and edits the key list.
# - Confirmed directly: a PATCH is 204 with no body. `replace` of `/port` works on a server whose port is null as well as on one that
#   has one, and so do `add` and `remove` (the field is then null); a port over 65535 is 400 "mPort must be less than or equal to
#   65535" and text is 400 "Something went wrong while patching the entity". `publicKeys` is not checked: an empty text and a name
#   that is no algorithm were both accepted (204). A path that does not exist is 400 `Missing field "nonsense"`; an unknown server
#   is 400 "Server with name X does not exist.". A server created with only a name and a protocol has the keys `ssh-rsa,
#   x509v3-rsa2048-sha256,rsa-sha2-256,rsa-sha2-512,ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521,ssh-ed25519`.
# - Exit codes: 0 when every PATCH was 204, 1 when the server refuses a call, 2 when an argument is wrong (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
NAME="${1:-SSH_TEST_SERVER_1}"
NEW_PORT="${2:-8026}"
USAGE="Usage: ./11.servers_name_PATCH.sh [NAME [PORT]]"

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

# patch_server PATCH: sends a JSON Patch, prints the code, and exits 1 unless it is 204
patch_server() {
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${SERVER_URL}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
      -d "$1" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    printf "HTTP %s\n" "${HTTP_CODE}"
    if [ "${HTTP_CODE}" != "204" ]; then
        show_error "${RESPONSE}"
        exit 1
    fi
}

read_server
PROTOCOL=$(printf '%s' "${SERVER_JSON}" | jq -r '.protocol // empty')
if [ "${PROTOCOL}" != "ssh" ]; then
    printf "The server %s is a %s server: this script changes SSH servers only. Nothing was changed.\n" "${NAME}" "${PROTOCOL:-unknown}"
    exit 1
fi
printf "The port of %s is now %s.\n" "${NAME}" "$(printf '%s' "${SERVER_JSON}" | jq -r '.port // "not set"')"

printf "Patching the server port...\n"
PATCH=$(jq -cn --argjson port "${NEW_PORT}" '[{op: "replace", path: "/port", value: $port}]')
patch_server "${PATCH}"

printf "Patching the server publicKeys...\n"
OLD_PUBLIC_KEYS=$(printf '%s' "${SERVER_JSON}" | jq -r '.publicKeys // ""')
echo "Public keys before removing rsa: ${OLD_PUBLIC_KEYS}"

NEW_PUBLIC_KEYS=$(printf '%s' "${OLD_PUBLIC_KEYS}" | jq -Rr 'split(",") | map(select(contains("rsa") | not)) | join(",")')
echo "Public keys after removal: ${NEW_PUBLIC_KEYS}"

if [ "${NEW_PUBLIC_KEYS}" = "${OLD_PUBLIC_KEYS}" ]; then
    printf "There is no rsa key to remove: the publicKeys are left as they are.\n"
else
    PATCH=$(jq -cn --arg keys "${NEW_PUBLIC_KEYS}" '[{op: "replace", path: "/publicKeys", value: $keys}]')
    patch_server "${PATCH}"
fi

printf "\nDone\n"
printf "Retrieve the server information to check the changes...\n"
read_server
printf '%s\n' "${SERVER_JSON}" | jq '{serverName, protocol, port, publicKeys}'
