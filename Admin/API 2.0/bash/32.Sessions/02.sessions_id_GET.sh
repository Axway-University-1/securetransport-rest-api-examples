#!/bin/bash
# ==============================================================================
# Script Name: 02.sessions_id_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script reads one session using the `/sessions/{id}` endpoint: the user, the client, the
# protocol and the command it is running now.
#
# Usage:
# ./02.sessions_id_GET.sh [SESSION_ID]
#
#   SESSION_ID  FTP:..., HTTP:... or SSH:... as 01.sessions_GET.sh lists it (default: the first session listed)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Requires `jq`, which looks the first session up, URL-encodes the id and prints the summary.
# - With no id the script lists the sessions and reads the first: on a server with no session open it says so
#   and exits 1.
# - Confirmed directly: the id may be sent as it is or with the colon encoded (`%3A`); the script encodes it with
#   jq's @uri. `fields=` works (`fields=id,command`); an unknown field answers `{ }`.
# - Confirmed directly: a session that is gone (it ended, or was killed) is 404 "Session with id ... was not found.";
#   an id that is not `FTP:<hash>:<number>`, `HTTP:<hash>` or `SSH:<hash>` is ALSO a 404, with the message "The format of
#   the session is incorrect" (for the DELETE it is 400). The protocol must be in capitals (`ftp:...` is the format error).
# - Exit codes: 0 when the session was read, 1 when not, 2 for a wrong argument (nothing is sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/sessions"
SESSION_ID="$1"
if [ -n "$2" ]; then
    printf "Usage: 02.sessions_id_GET.sh [SESSION_ID]\n"
    exit 2
fi
if [ -z "${SESSION_ID}" ]; then
    SESSION_ID=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?limit=1&fields=id" -H "accept: application/json" \
      -H "${REFERER_HEADER}" | jq -r '.[0].id // empty' 2>/dev/null)
    if [ -z "${SESSION_ID}" ]; then
        printf "There are no sessions to read.\n"
        exit 1
    fi
fi
ENCODED=$(jq -rn --arg id "${SESSION_ID}" '$id | @uri')

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENCODED}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the session (HTTP %s): " "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
printf '%s\n' "${RESPONSE}"
printf "\nIn short:\n"
printf '%s' "${RESPONSE}" | jq -r '
  "  \(.protocol) session of \(.userName) from \(.host), on \(.serverName)",
  "  command \(if (.command // "") == "" then "-" else .command end), since \(.sessionCreationTime)"'
