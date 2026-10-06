#!/bin/bash
# ==============================================================================
# Script Name: billable_GET_report.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Prints the number of billable transfers per day, for the last BT_REPORT_DAYS
# days (today included), for each of the three accounts of this feature, side by
# side, using the `/logs/transfers` endpoint and its `isBillable` filter:
#
#   partner_to_pull_from   the uploads of the sample files, and their pulls out
#   the test account       the pulls in, and the pushes out
#   partner_to_push_to     the pushes arriving
#
# Not numbered like the setup steps: 00.run_all.sh runs this one twice, once
# before anything else and once at the end, to show the before/after change for
# today, account by account.
#
# Usage:
# ./billable_GET_report.sh [LABEL [ACCOUNT]]
#
# LABEL is printed in the heading (for example "before" or "after"); it does not
# change what is measured. ACCOUNT reports on another test account than the
# default (the same name given to 00.run_all.sh).
#
# Notes:
# - Each account is filtered with account=, an exact match. Not accountName=:
#   /logs/transfers ignores that without a word and counts every account on the
#   server (confirmed directly). An earlier version of this script used it.
# - The partners are shared by every test account, so their counts include any
#   other test account's runs on the same day.
# - Each day is a full calendar day, midnight to midnight, in RFC 2822. macOS
#   (BSD date) and Linux (GNU date) differ here; both are handled below.
# - The count is resultSet.totalCount. resultSet.returnCount is capped by limit,
#   which is 1 here to keep the response small.
# - The last lines are TODAY_COUNT <account>: <count>, one per account, for
#   00.run_all.sh to read.
# - Requires `jq`.
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
ACCOUNTS=("${BT_PULL_PARTNER}" "${BT_TEST_ACCOUNT}" "${BT_PUSH_PARTNER}")

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

# billable_count ACCOUNT START END: the count, or nothing when none could be read
billable_count() {
    curl -s -k -G -u "${ST_USER}:${ST_PASSWORD}" \
      "https://${ST_SERVER}:${ST_PORT}/api/v2.0/logs/transfers" \
      --data-urlencode "isBillable=true" \
      --data-urlencode "account=$1" \
      --data-urlencode "startTimeAfter=$2" \
      --data-urlencode "endTimeBefore=$3" \
      --data-urlencode "limit=1" --data-urlencode "fields=id" \
      -H "accept: application/json" -H "${REFERER_HEADER}" \
      | jq -r '.resultSet.totalCount // empty' 2>/dev/null
}

printf "Billable transfers per day, last %s day(s) (%s)\n\n" "${BT_REPORT_DAYS}" "${LABEL}"
printf "  %-10s" "day"
for account in "${ACCOUNTS[@]}"; do printf "  %22s" "${account}"; done
printf "\n"

TODAY_COUNTS=()
for day_offset in $(seq $((BT_REPORT_DAYS - 1)) -1 0); do
    start_epoch=$((TODAY_MIDNIGHT - day_offset * 86400))
    end_epoch=$((start_epoch + 86400))
    start_rfc=$(to_rfc2822 "${start_epoch}")
    end_rfc=$(to_rfc2822 "${end_epoch}")

    # The whole row is built first, then printed at once
    row=$(printf "  %-10s" "$(to_day_label "${start_epoch}")")
    i=0
    for account in "${ACCOUNTS[@]}"; do
        count=$(billable_count "${account}" "${start_rfc}" "${end_rfc}")
        row="${row}$(printf "  %22s" "${count:-?}")"
        [ "${day_offset}" -eq 0 ] && TODAY_COUNTS[i]="${count}"
        i=$((i + 1))
    done
    printf "%s\n" "${row}"
done

# Machine-readable lines, so 00.run_all.sh can diff today's counts before and
# after, without re-parsing the table above. A count that could not be read is
# left empty, and the table shows it as ?.
printf "\n"
i=0
for account in "${ACCOUNTS[@]}"; do
    printf "TODAY_COUNT %s: %s\n" "${account}" "${TODAY_COUNTS[i]}"
    i=$((i + 1))
done
