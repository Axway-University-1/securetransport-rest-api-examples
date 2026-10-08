#!/bin/bash
# ==============================================================================
# Script Name: 07.servers_POST.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script creates new server entries using the `/servers` endpoint.
# It demonstrates:
# - Creating a minimal server with name and protocol
# - Duplicating an existing server by modifying its configuration
#
# Usage:
# ./07.servers_POST.sh [NAME [NEW_NAME [NEW_PORT]]]
#
#   NAME      the minimal SSH server to create (default SSH_TEST_SERVER_1)
#   NEW_NAME  the duplicate of it (default SSH_TEST_SERVER_2); not the same as NAME
#   NEW_PORT  the port of the duplicate, 1 to 65535 (default 8030)
#
# Risk: config - adds protocol servers, which open ports
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The serverName must be unique: a name that exists is refused (409) and the script stops there (exit 1).
# - Supported protocols: ftp, ssh, http, as2, pesit. This script makes SSH ones.
# - Neither server is started: a created server is inactive until 13.servers_operations_POST.sh starts it, so the port is only
#   a setting until then. Take a port that nothing on the server listens on before you start one: the lab's own SSH server
#   uses 8022 (the default here is not that one).
# - 12.servers_name_DELETE.sh removes the two servers again.
# - Requires `jq`, which builds the first body and edits the retrieved JSON for the second.
# - Confirmed directly: a creation is 201 with no body, and a `Location` that is a search, `/servers?serverName=NAME`, not a
#   path. A minimal server (only `serverName` and `protocol`) is inactive with `port` null and `isSftpEnabled` false, and carries
#   the default ciphers and the public key algorithms. A duplicate name is 409 "Server with name X already exist.". A port that
#   another server already uses is accepted (201) while the server is not running. A name with a space is fine. A body that
#   lacks what the protocol needs is 400 (an http server with no port and no certificate alias: "Missing HTTPS port").
# - Exit codes: 0 when both servers were created, 1 when the server refuses a call, 2 when an argument is wrong (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers"
NAME="${1:-SSH_TEST_SERVER_1}"
NEW_NAME="${2:-SSH_TEST_SERVER_2}"
NEW_PORT="${3:-8030}"
USAGE="Usage: ./07.servers_POST.sh [NAME [NEW_NAME [NEW_PORT]]]"

if [ "$#" -gt 3 ] || [ -z "${NAME}" ] || [ -z "${NEW_NAME}" ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
if [ "${NAME}" = "${NEW_NAME}" ]; then
    printf "NAME and NEW_NAME must differ. Nothing was sent.\n%s\n" "${USAGE}"
    exit 2
fi
if ! [[ "${NEW_PORT}" =~ ^[0-9]+$ ]] || [ "${NEW_PORT}" -lt 1 ] || [ "${NEW_PORT}" -gt 65535 ]; then
    printf "NEW_PORT is a number from 1 to 65535, not %s. Nothing was sent.\n%s\n" "${NEW_PORT}" "${USAGE}"
    exit 2
fi

# The answer to a refused call: the server's own messages, or the text as it is
show_error() { printf '%s' "$1" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "$1"; }

# Create a minimal SSH server
BODY=$(jq -cn --arg name "${NAME}" '{serverName: $name, protocol: "ssh"}')
printf "Creating the minimal SSH server %s...\n" "${NAME}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "201" ]; then
    show_error "${RESPONSE}"
    exit 1
fi

# Duplicate an existing server with modifications
printf "Creating a new server with the name: %s and port: %s...\n" "${NEW_NAME}" "${NEW_PORT}"

# Retrieve existing server config
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/$(jq -rn --arg n "${NAME}" '$n|@uri')" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the server %s: HTTP %s\n" "${NAME}" "${HTTP_CODE}"
    show_error "${RESPONSE}"
    exit 1
fi

# Modify serverName and port
#
# Edit the retrieved object with jq. This targets the exact fields and always
# produces valid JSON, which a text substitution cannot guarantee.
#
BODY=$(printf '%s' "${RESPONSE}" | jq -c --arg newName "${NEW_NAME}" --argjson newPort "${NEW_PORT}" \
   '.serverName = $newName | .port = $newPort | .clientPasswordAuth = "default"')

# Create new server with modified config
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "201" ]; then
    show_error "${RESPONSE}"
    exit 1
fi
