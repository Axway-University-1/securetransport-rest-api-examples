#!/bin/bash
# ==============================================================================
# Script Name: 01.logs_server_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script reads the server log using the `/logs/server` endpoint: what the protocol servers,
# the Admin service and the rest wrote while running. It demonstrates:
# - Counting the entries of the last minutes (fromDate=)
# - Searching the message, by component (FTPD, SSHD, HTTPD, ...) and by level
#
# Usage:
# ./01.logs_server_GET.sh [MINUTES [MESSAGE [COMPONENTS [LEVELS]]]]
#
#   MINUTES     how far back to look (default 60)
#   MESSAGE     text the message must contain (optional)
#   COMPONENTS  one or more of TM AS2D SSHD SOCKS ADMIN AUDIT FTPD HTTPD PESITD, with commas
#               between them (optional)
#   LEVELS      one or more of ALL DEBUG ERROR FATAL INFO TRACE WARN, with commas between them
#               (optional)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: the server log is OLDEST first, the opposite of the audit log, so a
#   plain limit shows the oldest entries of the server's life. fromDate keeps it to the recent ones.
# - Confirmed directly: fromDate and endDate are RFC 2822 dates; 2026-10-07 answers 400.
# - Confirmed directly: component= and level= must be in capitals (ftpd and error find nothing),
#   and several values are SEPARATE parameters, component=FTPD&component=HTTPD, which this
#   script sends; a comma list finds nothing. A value that does not exist finds nothing, not 400.
# - Confirmed directly: message= is a part of the message, with case; * is not a wildcard.
# - Confirmed directly: accountName= is IGNORED: any value answers every entry. Search the
#   message for the account name instead.
# - Confirmed directly (5.5-20260924): what a login writes depends on the protocol. SFTP: component SSHD, INFO
#   "User NAME login success." and, for a wrong password, INFO (not WARN) "User NAME login failed.". HTTP (EndUser
#   API): component HTTPD, INFO "User NAME login success."; a failed login names NO account: INFO "Denying access to
#   unknown user from address ADDRESS" (also for a known account with a wrong password), so search for that text; an
#   HTTP login also WARNs "virtual user NAME does not have email associated", which is not a failure. FTP: component
#   FTPD, INFO "virtual user NAME logged in from" and WARN "Failed login for user NAME from". Component TM also
#   writes INFO "User with login name 'NAME' ... successfully authenticated over SSH, HTTP or FTP".
# - Requires `jq`, which prints one entry per line.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
#   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
# - Exit codes: 0 when every answer is 200, 1 otherwise, 2 when MINUTES, a component or a level is wrong, or there are more than four arguments (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/logs/server"
MINUTES="${1:-60}"
MESSAGE="$2"
COMPONENTS="$3"
LEVELS="$4"
if [ "$#" -gt 4 ]; then
    printf "Usage: ./01.logs_server_GET.sh [MINUTES [MESSAGE [COMPONENTS [LEVELS]]]]\n"
    exit 2
fi
[[ "${MINUTES}" =~ ^[1-9][0-9]*$ ]] || { printf "MINUTES must be a whole number of 1 or more: %s\n" "${MINUTES}"; exit 2; }
IFS=',' read -r -a COMPONENT_LIST <<< "${COMPONENTS}"
IFS=',' read -r -a LEVEL_LIST <<< "${LEVELS}"
for ITEM in "${COMPONENT_LIST[@]}"; do
    [ -z "${ITEM}" ] || [[ "${ITEM}" =~ ^(TM|AS2D|SSHD|SOCKS|ADMIN|AUDIT|FTPD|HTTPD|PESITD)$ ]] || { printf "Unknown component %s.\n" "${ITEM}"; exit 2; }
done
for ITEM in "${LEVEL_LIST[@]}"; do
    [ -z "${ITEM}" ] || [[ "${ITEM}" =~ ^(ALL|DEBUG|ERROR|FATAL|INFO|TRACE|WARN)$ ]] || { printf "Unknown level %s.\n" "${ITEM}"; exit 2; }
done

# The start, as an RFC 2822 date in GMT (BSD date, then GNU date)
SINCE_EPOCH=$(( $(date +%s) - MINUTES * 60 ))
SINCE=$(date -u -r "${SINCE_EPOCH}" "+%a, %d %b %Y %H:%M:%S GMT" 2>/dev/null || date -u -d "@${SINCE_EPOCH}" "+%a, %d %b %Y %H:%M:%S GMT")

FILTER=(--data-urlencode "fromDate=${SINCE}")
[ -n "${MESSAGE}" ] && FILTER+=(--data-urlencode "message=${MESSAGE}")
for ITEM in "${COMPONENT_LIST[@]}"; do [ -n "${ITEM}" ] && FILTER+=(--data-urlencode "component=${ITEM}"); done
for ITEM in "${LEVEL_LIST[@]}"; do [ -n "${ITEM}" ] && FILTER+=(--data-urlencode "level=${ITEM}"); done

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

printf "Server log entries since %s: " "${SINCE}"
st_get -G "${MAIN_URL}" --data-urlencode "fromDate=${SINCE}" --data-urlencode "limit=1" --data-urlencode "fields=id"
printf '%s\n' "${RESPONSE}" | jq -r '.resultSet.totalCount'

printf "\nThe first 20 that match the filters: time, level, component, message:\n"
st_get -G "${MAIN_URL}" "${FILTER[@]}" --data-urlencode "limit=20" --data-urlencode "fields=time,level,component,message"
printf '%s\n' "${RESPONSE}" | jq -r '(.result // [])[] | "  \(.time)  \(.level)  \(.component)  \((.message // "") | gsub("[\n\t]"; " ") | .[0:140])"'
