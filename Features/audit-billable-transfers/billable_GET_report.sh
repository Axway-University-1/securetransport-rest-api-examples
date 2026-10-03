#!/bin/bash
# ==============================================================================
# Script Name: billable_GET_report.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Prints the number of billable transfers per day, for the last BT_REPORT_DAYS
# days (today included), for this feature's test account, using the
# `/logs/transfers` endpoint and its `isBillable` filter.
#
# Not numbered like the setup steps: 00.run_all.sh runs this one twice, once
# before anything else and once at the end, to show the before/after change for
# today.
#
# Usage:
# ./billable_GET_report.sh [LABEL [ACCOUNT]]
#
# LABEL is printed in the heading (for example "before" or "after"); it does not
# change what is measured. ACCOUNT reports on another test account than the
# default (the same name given to 00.run_all.sh).
#
# Notes:
# - Scoped to accountName=BT_TEST_ACCOUNT, so an existing account with the same
#   name on your server does not throw the count off. Run this against a server
#   that does not already have that account, for a clean baseline.
# - Each day is a full calendar day in the server's own local time, midnight to
#   midnight, in RFC 2822 (the format curl's --data-urlencode produces from
#   `date -R`, same as the Admin Guide's own export example).
# - Requires `jq`.
# - Confirmed directly: /logs/transfers' resultSet carries TWO counts, not one -
#   returnCount (how many rows are in THIS page, capped by limit) and
#   totalCount (the true total matching the filter, independent of limit). Most
#   other list endpoints in this API only need returnCount, since their
#   returnCount already ignores limit; this one does not. Reading returnCount
#   here, with limit=1 set to keep the response small, silently capped every
#   day's count at 1 - confirmed directly, a real bug caught by comparing
#   against File Tracking's own count for the same account and day.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
if [ -n "$2" ]; then
    [[ "$2" =~ ^[A-Za-z0-9._-]+$ ]] \
        || { printf "ACCOUNT may use only letters, digits, '.', '_' and '-': %s\n" "$2"; exit 2; }
    export BT_RUN_ACCOUNT="$2"
fi
source "${SCRIPT_DIR}/settings.sh"

LABEL="${1:-report}"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

# Midnight today, as an epoch second count - the one place BSD and GNU date
# differ, same split as the Admin Guide's own export example
if date -v-1d >/dev/null 2>&1; then
    TODAY_MIDNIGHT=$(date -v0H -v0M -v0S +%s)
    to_rfc2822() { date -r "$1" -R; }
    to_day_label() { date -r "$1" +%Y-%m-%d; }
else
    TODAY_MIDNIGHT=$(date -d "today 00:00:00" +%s)
    to_rfc2822() { date -d "@$1" -R; }
    to_day_label() { date -d "@$1" +%Y-%m-%d; }
fi

printf "Billable transfers per day, last %s day(s), for %s (%s)\n" \
  "${BT_REPORT_DAYS}" "${BT_TEST_ACCOUNT}" "${LABEL}"

TODAY_COUNT=""
for day_offset in $(seq $((BT_REPORT_DAYS - 1)) -1 0); do
    start_epoch=$((TODAY_MIDNIGHT - day_offset * 86400))
    end_epoch=$((start_epoch + 86400))
    start_rfc=$(to_rfc2822 "${start_epoch}")
    end_rfc=$(to_rfc2822 "${end_epoch}")
    day_label=$(to_day_label "${start_epoch}")

    response=$(curl -s -k -G -u "${ST_USER}:${ST_PASSWORD}" \
      "https://${ST_SERVER}:${ST_PORT}/api/v2.0/logs/transfers" \
      --data-urlencode "isBillable=true" \
      --data-urlencode "accountName=${BT_TEST_ACCOUNT}" \
      --data-urlencode "startTimeAfter=${start_rfc}" \
      --data-urlencode "endTimeBefore=${end_rfc}" \
      --data-urlencode "limit=1" --data-urlencode "fields=id" \
      -H "accept: application/json" -H "${REFERER_HEADER}")

    count=$(printf '%s' "${response}" | jq -r '.resultSet.totalCount // empty' 2>/dev/null)
    if [ -z "${count}" ]; then
        printf "  %s  could not read a count. The response was:\n%s\n" "${day_label}" "${response}"
        continue
    fi
    printf "  %s  %s billable transfer(s)\n" "${day_label}" "${count}"
    [ "${day_offset}" -eq 0 ] && TODAY_COUNT="${count}"
done

# A machine-readable line, so 00.run_all.sh can diff today's count before and
# after, without re-parsing the printed table above
printf "TODAY_COUNT: %s\n" "${TODAY_COUNT}"
