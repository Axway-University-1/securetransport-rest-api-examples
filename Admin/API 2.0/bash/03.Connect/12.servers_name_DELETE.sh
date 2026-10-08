#!/bin/bash
# ==============================================================================
# Script Name: 12.servers_name_DELETE.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes a server using the `/servers/{name}` endpoint.
# It demonstrates:
# - A conditional DELETE request after checking server existence (HEAD)
# - Printing the HTTP code of each delete, and stopping with exit 1 when the server refuses one
#
# Usage:
# ./12.servers_name_DELETE.sh [NAME...]
#
#   NAME  the servers to delete, by name (default: SSH_TEST_SERVER_1 and SSH_TEST_SERVER_2, the two 07.servers_POST.sh creates)
#
# Risk: config - removes a protocol server
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The server name must be valid and exist in the system: a server that is not there is reported and skipped (the exit code
#   stays 0), and the others are still tried. A server the server refuses to delete (a 4xx or 5xx) makes the exit code 1.
# - A name you give is deleted if it exists, whatever its protocol: name a real server and it is gone. Run with no argument
#   to delete only the two test servers.
# - Requires `jq`, which encodes the names for the URL and shows the server's own message.
# - Confirmed directly: a delete is 204 with no body. A server that does not exist is answered 400 by DELETE ("Server with name X does not
#   exist."), PATCH (the same) and PUT ("Could not update server with name X."), and **HEAD answers 400 too (no body), not the 404 that GET gives (an HTML page)**, so this
#   script treats a HEAD that is not 200 as "does not exist" only for 400 and 404, and as an error for any other code.
# - Exit codes: 0 when every server was deleted or was not there, 1 when a delete (or the check before it) is refused, 2 when
#   an argument is empty (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers"
USAGE="Usage: ./12.servers_name_DELETE.sh [NAME...]"

if [ "$#" -eq 0 ]; then
    set -- "SSH_TEST_SERVER_1" "SSH_TEST_SERVER_2"
fi
for NAME in "$@"; do
    if [ -z "${NAME}" ]; then
        printf "A server name must not be empty. Nothing was sent.\n%s\n" "${USAGE}"
        exit 2
    fi
done

# The answer to a refused call: the server's own messages, or the text as it is
show_error() { printf '%s' "$1" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "$1"; }

FAILED=0
for NAME in "$@"; do
    SERVER_URL="${MAIN_URL}/$(jq -rn --arg n "${NAME}" '$n|@uri')"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" --head "${SERVER_URL}" \
      -H "accept: */*" -H "${REFERER_HEADER}")
    if [ "${HTTP_CODE}" = "400" ] || [ "${HTTP_CODE}" = "404" ]; then
        printf "The server '%s' does not exist (HEAD answered %s).\n" "${NAME}" "${HTTP_CODE}"
        continue
    fi
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "Could not check the server '%s': HEAD answered %s. Not deleted.\n" "${NAME}" "${HTTP_CODE}"
        FAILED=1
        continue
    fi

    printf "Server exists. Deleting server '%s'...\n" "${NAME}"
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${SERVER_URL}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    printf "HTTP %s\n" "${HTTP_CODE}"
    if [ "${HTTP_CODE}" != "204" ]; then
        show_error "${RESPONSE}"
        FAILED=1
        continue
    fi
    printf "Deleted '%s'.\n" "${NAME}"
done
exit "${FAILED}"
