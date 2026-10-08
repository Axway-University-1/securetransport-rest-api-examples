#!/bin/bash
# ==============================================================================
# Script Name: 01.sessions_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the sessions open on the server now, using the `/sessions` endpoint.
# It demonstrates:
# - Listing every session, one line each: id, user, protocol, client host, the command it runs, when it began
# - Keeping the sessions of one protocol (FTP, HTTP or SSH), and those of one user
#
# Usage:
# ./01.sessions_GET.sh [TYPE [USER]]
#
#   TYPE  all, FTP, HTTP or SSH, in capitals (default: all)
#   USER  show only the sessions of this user name, exactly as written (optional)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Requires `jq`, which keeps the sessions asked for and prints one line each.
# - A session exists only while a client is connected, so on a quiet server the list is empty: `[]`.
#   To see one, log in as a test account over FTP, SFTP or the EndUser API and keep the connection open.
# - Confirmed directly: the answer is a plain array, not {resultSet, result}. Each session has id, userName, host,
#   protocol, userClass, currentTransferBandwidth, command, sessionCreationTime, nodeIp and serverName. The reference
#   spells the bandwidth field `currentTransferBandwith` and lists only FTP and HTTP as protocols; the server writes
#   it with the d, and SSH sessions are listed too.
# - Confirmed directly: `type=` is IGNORED by the server (type=SSH, type=XX and type=ftp all answer every session),
#   so this script sends it and then keeps the matching ones itself. The protocol is matched exactly, in capitals.
#   There is no filter for a user: the one here is applied by this script, as is `limit` when it is 0 or negative
#   (400 "Limit should be a positive integer"); `limit=abc` is a bare 404. `fields=` works (an unknown field
#   gives `{ }` for each session) and `localDaemonReturn=` made no difference with any value.
# - Confirmed directly: the list is NOT stable from one call to the next. Right after clients connect, or
#   while they stay connected, a call can lack sessions that are open (one protocol of several), or answer `[]`;
#   the next call has them again. Read it again before acting on it, and never decide from a single read that a
#   session is gone.
# - Confirmed directly: an id is `FTP:<hash>:<number>`, `HTTP:<hash>` or `SSH:<hash>`, long, and hex. `command` is
#   IDLE for an FTP session that is doing nothing, STOR while it uploads, and empty for HTTP and SSH. The user
#   of a session is the account's login name. `sessionCreationTime` is an RFC 2822 date; `nodeIp` holds a
#   newline ("Local \n (address)"); `currentTransferBandwidth` is -1 when nothing is being transferred.
# - Confirmed directly: the administrator's own API login is not a session of this list (the list was empty with
#   one open), and 05.sessions_statistics_userClass_GET.sh counts the same sessions.
# - Exit codes: 0 when the server answered 200, 1 when it refuses, 2 for a wrong argument (nothing is sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/sessions"
TYPE="${1:-all}"
USER_NAME="$2"
case "${TYPE}" in
    all|FTP|HTTP|SSH) ;;
    *)
        printf "Usage: 01.sessions_GET.sh [TYPE [USER]]   (TYPE is all, FTP, HTTP or SSH)\n"
        exit 2
        ;;
esac
if [ -n "$3" ]; then
    printf "Usage: 01.sessions_GET.sh [TYPE [USER]]\n"
    exit 2
fi

if [ "${TYPE}" = "all" ]; then
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}" -H "accept: application/json" -H "${REFERER_HEADER}" \
      -w "\n%{http_code}")
else
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET -G "${MAIN_URL}" --data-urlencode "type=${TYPE}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
fi
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s\n" "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi

printf '%s' "${RESPONSE}" | jq -r --arg type "${TYPE}" --arg user "${USER_NAME}" '
  [.[] | select(($type == "all" or .protocol == $type) and ($user == "" or .userName == $user))] as $s
  | "Sessions: \($s | length)",
    "",
    "Id, user, protocol, client host, command, started:",
    ($s[] | "  \(.id)  \(.userName)  \(.protocol)  \(.host)  \(if (.command // "") == "" then "-" else .command end)  \(.sessionCreationTime)")'
