#!/bin/bash
# ==============================================================================
# Script Name: 02.logs_transfers_GET_billable.sh
# Author: Plamen Milenkov
# Created: 2026-10-05
# Location: Sofia
# ==============================================================================
# Description:
# This script counts the billable transfers per day, using the
# `/logs/transfers` endpoint and its `isBillable` filter. It prints one line
# per calendar day, today last, and the total.
#
# Usage:
# ./02.logs_transfers_GET_billable.sh [DAYS [ACCOUNT]]
#
#   DAYS     how many days to count, today included (default 7)
#   ACCOUNT  count only this account's transfers (default: every account)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The account is filtered with account=. The endpoint ignores accountName=
#   without a word and answers for every account (confirmed directly).
# - SecureTransport 5.5-20260924 or later. An earlier release, or a transfer
#   from before the upgrade, has no billable status, and counts as 0.
# - Each day runs from midnight to midnight in this machine's time zone, sent in
#   RFC 2822, for example "Mon, 05 Oct 2026 00:00:00 +0300".
# - The count is resultSet.totalCount. resultSet.returnCount is capped by limit,
#   which is 1 here to keep the response small.
# - Features/audit-billable-transfers explains which transfers are billable, and
#   tests it.
# - Requires `jq`, which reads the count.
# - Every day is one call, and a call that is not 200 (401, "Authentication required." as plain text, for refused credentials;
#   500) prints the status and the answer and ends the script with exit 1, before a total that would be too small is printed. A
#   200 that carries no count is still said ("could not read a count") and skipped, as before, and makes the exit code 1 at the end.
# - Exit codes: 0 when every day was counted, 1 otherwise, 2 when an argument is wrong (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

DAYS="${1:-7}"
ACCOUNT="$2"
if [ "$#" -gt 2 ]; then
    printf "Usage: ./02.logs_transfers_GET_billable.sh [DAYS [ACCOUNT]]\n"
    exit 2
fi
[[ "${DAYS}" =~ ^[1-9][0-9]*$ ]] || { printf "DAYS must be a whole number, 1 or more: %s\n" "${DAYS}"; exit 2; }

# Midnight today, in seconds. BSD date (macOS) and GNU date (Linux) differ here.
if date -v-1d >/dev/null 2>&1; then
    TODAY_MIDNIGHT=$(date -v0H -v0M -v0S +%s)
    to_rfc2822() { date -r "$1" -R; }
    to_day() { date -r "$1" +%Y-%m-%d; }
else
    TODAY_MIDNIGHT=$(date -d "today 00:00:00" +%s)
    to_rfc2822() { date -d "@$1" -R; }
    to_day() { date -d "@$1" +%Y-%m-%d; }
fi

# Only add the account to the query when one was given
ACCOUNT_FILTER=()
[ -n "${ACCOUNT}" ] && ACCOUNT_FILTER=(--data-urlencode "account=${ACCOUNT}")

printf "Billable transfers per day, for %s\n" "${ACCOUNT:-every account}"

TOTAL=0
UNREAD=0
for OFFSET in $(seq $((DAYS - 1)) -1 0); do
    START=$((TODAY_MIDNIGHT - OFFSET * 86400))
    END=$((START + 86400))

    RESPONSE=$(curl -s -k -G -u "${ST_USER}:${ST_PASSWORD}" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/logs/transfers" \
      --data-urlencode "isBillable=true" "${ACCOUNT_FILTER[@]}" \
      --data-urlencode "startTimeAfter=$(to_rfc2822 "${START}")" \
      --data-urlencode "endTimeBefore=$(to_rfc2822 "${END}")" \
      --data-urlencode "limit=1" --data-urlencode "fields=id" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "  %s  HTTP %s\n" "$(to_day "${START}")" "${HTTP_CODE}"
        [ -n "${RESPONSE}" ] && printf '%s\n' "${RESPONSE}"
        exit 1
    fi
    COUNT=$(printf '%s' "${RESPONSE}" | jq -r '.resultSet.totalCount // empty' 2>/dev/null)

    if [ -z "${COUNT}" ]; then
        printf "  %s  could not read a count\n" "$(to_day "${START}")"
        UNREAD=$((UNREAD + 1))
        continue
    fi
    printf "  %s  %s\n" "$(to_day "${START}")" "${COUNT}"
    TOTAL=$((TOTAL + COUNT))
done

printf "Total: %s billable transfer(s) in %s day(s)\n" "${TOTAL}" "${DAYS}"
[ "${UNREAD}" -eq 0 ]
