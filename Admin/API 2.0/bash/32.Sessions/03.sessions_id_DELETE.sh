#!/bin/bash
# ==============================================================================
# Script Name: 03.sessions_id_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script ends one session, using the `/sessions/{id}` endpoint: the client is disconnected at once.
# It reads the session first and says whose it is, and it can refuse to end it when it is not the
# user's you expect.
#
# Usage:
# ./03.sessions_id_DELETE.sh SESSION_ID [USER]
#
#   SESSION_ID  FTP:..., HTTP:... or SSH:... as 01.sessions_GET.sh lists it (required: there is no default,
#               so that running the script bare ends nothing)
#   USER        the user you expect it to belong to: when the session is another user's, nothing is ended (optional)
#
# Risk: write - ends a session: the client is disconnected, its transfer in progress is cut short
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Requires `jq`, which URL-encodes the id and reads the session's user and protocol.
# - This disconnects a real client. Take the id from 01.sessions_GET.sh and pass the user too, so that a session
#   that has taken the place of the one you meant (ids are not reused, but check) is not ended by mistake. Try it on
#   a test account: log in as it over FTP and keep the connection open.
# - Confirmed directly: answers 204, and the client is cut off at once: an idle FTP client finds the connection
#   closed (EOF) on its next command, an upload in progress ends with a broken pipe, an SSH client exits, and an
#   EndUser API session answers 401 on the next call. The session is gone from the list. Only that session is
#   ended: the user's other sessions (here an FTP and an HTTP one of one account) stay.
# - Confirmed directly: a session that is already gone is 404 "Session with id ... not found"; an id that does not
#   have the `FTP:<hash>:<number>`, `HTTP:<hash>` or `SSH:<hash>` shape is 400 "The format of the session is incorrect"
#   (the GET gives 404 for that). The reference's `localDaemonReturn` query parameter made no difference and is
#   not used. Ending a session does not lock the account: the user can log in again at once.
# - Exit codes: 0 when the session was ended, 1 when it was not found, is another user's or the server refuses,
#   2 for a missing or wrong argument (nothing is sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/sessions"
SESSION_ID="$1"
EXPECTED_USER="$2"
if [ -z "${SESSION_ID}" ] || [[ "${SESSION_ID}" != *:* ]] || [ -n "$3" ]; then
    printf "Usage: 03.sessions_id_DELETE.sh SESSION_ID [USER]   (SESSION_ID is FTP:..., HTTP:... or SSH:..., from 01.sessions_GET.sh)\n"
    exit 2
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
SESSION_USER=$(printf '%s' "${RESPONSE}" | jq -r '.userName')
SESSION_PROTOCOL=$(printf '%s' "${RESPONSE}" | jq -r '.protocol')
if [ -n "${EXPECTED_USER}" ] && [ "${SESSION_USER}" != "${EXPECTED_USER}" ]; then
    printf "That is a %s session of %s, not of %s: nothing was ended.\n" "${SESSION_PROTOCOL}" "${SESSION_USER}" "${EXPECTED_USER}"
    exit 1
fi

printf "Ending the %s session of %s...\n" "${SESSION_PROTOCOL}" "${SESSION_USER}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${ENCODED}" -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
