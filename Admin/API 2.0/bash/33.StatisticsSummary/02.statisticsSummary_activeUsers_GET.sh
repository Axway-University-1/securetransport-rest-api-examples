#!/bin/bash
# ==============================================================================
# Script Name: 02.statisticsSummary_activeUsers_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the users who have logged in, with the time of their last login, using the
# `/statisticsSummary/activeUsers` endpoint.
# It demonstrates:
# - Paging through the list with limit and offset, and printing one line per user
# - Keeping the users whose name holds some text, or the users who logged in after (or before) a time
#
# Usage:
# ./02.statisticsSummary_activeUsers_GET.sh [NAME [FROM [TO]]]
#
#   NAME  a part of the login name, case sensitive, no `*` (optional; empty for every user)
#   FROM  only users whose last login was after this: yyyy-MM-dd, an RFC 2822 date or a timestamp in milliseconds (optional)
#   TO    only users whose last login was before this, in the same formats (optional)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Requires `jq`, which prints one line per user.
# - Confirmed directly: the answer is `{resultSet, result}`, the result a list of `name`, `lastAccessTime` and
#   `lastAdhocAccessTime`. `lastAccessTime` is TEXT for people, not a date to parse: `October 8, 2026, 8:43 AM`, to the minute, in
#   the server's time zone, with a no-break space (U+202F) before AM or PM. `lastAdhocAccessTime` is an empty string for a
#   user who never used ad hoc (file sharing by e-mail) access, which is every user on the lab.
# - Confirmed directly: a user is listed from the FIRST LOGIN, over any protocol (an EndUser API login and an FTP login
#   both did), and the time moves with each later login. A wrong password does not move it. A user who never logged in is not
#   listed, and neither is the administrator that makes this call.
# - Confirmed directly: **the list is not of the accounts that exist**. An account that is deleted stays in it, with its last
#   login time, and a new account of the same name starts from that entry. There is no way to remove one.
# - Confirmed directly: `name=` is a PART of the login name, case sensitive, and takes no `*` (`ohn` finds `john` and
#   `john_doe`, `example_` every name that holds it, `EXAMPLE_` and `john*` find nothing). To get one user, pick the exact name
#   out of the answer. `FROM` and `TO` take the
#   three date formats the reference names, and anything else is 400 "Invalid date format. Format must be *EEE, dd MMM yyyy
#   HH:mm:ss Z*, *yyyy-MM-dd* or a timestamp.". `lastAdhocAccessTime.from` and `.to` are not offered here.
# - Confirmed directly: `limit=0` lists everything, a negative limit is 400 "The limit should be a positive number or 0.",
#   `offset` skips that many, `fields=name` keeps the named keys (an unknown one is 400 "Field <name> does not exist.") and
#   `totalCount` counts all the users that match, not the page. The default page, with no `limit`, held all 46 users of the lab,
#   so this script asks for a page of 100 and goes on while the page is full.
# - Exit codes: 0 when the server answered 200, 1 when it refuses, 2 for a wrong argument (nothing is sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/statisticsSummary/activeUsers"
NAME="$1"
FROM="$2"
TO="$3"
if [ -n "$4" ]; then
    printf "Usage: 02.statisticsSummary_activeUsers_GET.sh [NAME [FROM [TO]]]\n"
    exit 2
fi

QUERY=()
[ -n "${NAME}" ] && QUERY+=(--data-urlencode "name=${NAME}")
[ -n "${FROM}" ] && QUERY+=(--data-urlencode "lastAccessTime.from=${FROM}")
[ -n "${TO}" ] && QUERY+=(--data-urlencode "lastAccessTime.to=${TO}")

LIMIT=100
OFFSET=0
FIRST=1
while true; do
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET -G "${MAIN_URL}" "${QUERY[@]}" \
      --data-urlencode "limit=${LIMIT}" --data-urlencode "offset=${OFFSET}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "HTTP %s\n" "${HTTP_CODE}"
        printf '%s' "${RESPONSE}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
        exit 1
    fi
    if [ "${FIRST}" = "1" ]; then
        printf '%s' "${RESPONSE}" | jq -r '"Users who have logged in: \(.resultSet.totalCount)", "", "User, last login, last ad hoc access:"'
        FIRST=0
    fi
    printf '%s' "${RESPONSE}" | jq -r '.result[] | "  \(.name)  \(.lastAccessTime)  \(if (.lastAdhocAccessTime // "") == "" then "-" else .lastAdhocAccessTime end)"'
    COUNT=$(printf '%s' "${RESPONSE}" | jq -r '.resultSet.returnCount')
    [ "${COUNT}" -lt "${LIMIT}" ] && break
    OFFSET=$((OFFSET + LIMIT))
done
