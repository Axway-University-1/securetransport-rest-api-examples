#!/bin/bash
# ==============================================================================
# Script Name: 02.activeUsers_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Part 1, global usage, step 2: the active users. GET /statisticsSummary/activeUsers, read in full (limit=1000), compared with the accounts that exist today, narrowed to one day, and
# narrowed by name. It shows that the list is kept by NAME (a deleted account stays in it), that one page is 100 names, and that lastAccessTime is the server's own text.
#
# Usage:
# ./02.activeUsers_GET.sh [DAY]
#
#   DAY  the day to narrow to, yyyy-MM-dd (default: today on this machine; the server cuts its days in its own time zone)
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/33.StatisticsSummary/02.statisticsSummary_activeUsers_GET.sh, then asks the list of accounts to compare it with.
# - The list of names holds users that did something in the last 60 days (the 60 days come from the product owner and were not tried: the oldest entry on the lab is 30 days old).
# - totalCount is what is counted, returnCount is the size of this answer. A list of more than 1000 names is read with offset.
# - The name filter is a "contains" match that tells capitals from small letters, and * is not a wildcard in it (it is one in accounts and in the transfer log).
# - lastAccessTime is text for people, to the minute and with no offset. It cannot be sent back as a filter.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./02.activeUsers_GET.sh [DAY]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: DAY.\n%s\n" "$#" "${USAGE}"; exit 2; fi
DAY="${1:-$(date +%Y-%m-%d)}"
uc_check_day "${DAY}" "${USAGE}"
st_session

uc_get statisticsSummary/activeUsers
if [ "${LIST_CODE}" != "200" ]; then printf "GET /statisticsSummary/activeUsers: HTTP %s: %s\n" "${LIST_CODE}" "$(uc_why)"; exit 1; fi
printf '%s' "${LIST_BODY}" | jq -r '"With no limit: returnCount \(.resultSet.returnCount), totalCount \(.resultSet.totalCount). One page is 100 names."'

uc_get statisticsSummary/activeUsers "limit=1000"
if [ "${LIST_CODE}" != "200" ]; then printf "GET /statisticsSummary/activeUsers?limit=1000: HTTP %s: %s\n" "${LIST_CODE}" "$(uc_why)"; exit 1; fi
ACTIVE="${LIST_BODY}"
printf '%s' "${ACTIVE}" | jq -r '"With limit=1000: returnCount \(.resultSet.returnCount), totalCount \(.resultSet.totalCount). The active users are the names in the list, not the accounts."'
RETURNED=$(printf '%s' "${ACTIVE}" | jq -r '.resultSet.returnCount')
TOTAL=$(printf '%s' "${ACTIVE}" | jq -r '.resultSet.totalCount')
if [ "${RETURNED}" != "${TOTAL}" ]; then echo "The list is longer than one answer of 1000: read it with offset (see 06-lists-paging-and-fields)."; fi

uc_get accounts "limit=1000" "fields=name"
if [ "${LIST_CODE}" != "200" ]; then printf "GET /accounts: HTTP %s: %s\n" "${LIST_CODE}" "$(uc_why)"; exit 1; fi
ACCOUNTS=$(printf '%s' "${LIST_BODY}" | jq -r '.resultSet.totalCount')
GONE=$(jq -n --argjson active "${ACTIVE}" --argjson accounts "${LIST_BODY}" '[$active.result[].name] - [$accounts.result[].name] | length')
echo "The server has ${ACCOUNTS} accounts today. Of the ${RETURNED} names read, ${GONE} are no longer an account: a deleted account stays in the list."

uc_get statisticsSummary/activeUsers "lastAccessTime.from=${DAY}" "lastAccessTime.to=${DAY}" "limit=1000"
if [ "${LIST_CODE}" != "200" ]; then printf "GET /statisticsSummary/activeUsers for %s: HTTP %s: %s\n" "${DAY}" "${LIST_CODE}" "$(uc_why)"; exit 1; fi
printf '%s' "${LIST_BODY}" | jq -r --arg day "${DAY}" '"Last seen on \($day), the day of the server: \(.resultSet.totalCount). The first of them:", (.result[0:3][] | "  \(.name)  \(.lastAccessTime)")'

FIRST=$(printf '%s' "${ACTIVE}" | jq -r '.result[0].name // empty')
if [ -n "${FIRST}" ]; then
    PART="${FIRST:1:${#FIRST}-2}"
    [ -n "${PART}" ] || PART="${FIRST}"
    uc_count "name=${PART}" statisticsSummary/activeUsers "name=${PART}" "limit=1" || exit 1
    echo "name=${PART} (the middle of ${FIRST}) found ${COUNT}: the filter looks inside the name."
    uc_count "name=*" statisticsSummary/activeUsers "name=*" "limit=1" || exit 1
    echo "name=* found ${COUNT}: * is a plain character here, not a wildcard."
fi
