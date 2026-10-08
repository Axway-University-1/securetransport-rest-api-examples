#!/bin/bash
# ==============================================================================
# Script Name: 01.statisticsSummary_generateReport_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script generates the statistics summary report, using the `/statisticsSummary/generateReport`
# endpoint: the transfers in and out of the server, one line for each day of a period. It is the report
# the server can send to the Axway Platform for usage reporting, made now, for the dates you give.
# It demonstrates:
# - Reading one day, or a period, and printing one line per day and the totals
# - Asking for the active users count and the incoming file volume
#
# Usage:
# ./01.statisticsSummary_generateReport_GET.sh [START [END [ACTIVE_USERS [VOLUME]]]]
#
#   START         first day, dd/MM/yyyy (default: today)
#   END           last day, dd/MM/yyyy, included (default: START)
#   ACTIVE_USERS  true to ask for the count of active users (optional, default false)
#   VOLUME        true to ask for the incoming file volume (optional, default false)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Requires `jq`, which prints one line per day, and the totals.
# - Confirmed directly: both dates are required (400 "'startDate' and 'endDate' parameters are mandatory.") and are
#   dd/MM/yyyy only (`2026-10-01` and `01-10-2026` are 400 "... is not in correct format"; `1/10/2026` is accepted).
#   The END day is INCLUDED: START and END the same day gives that one day. The report has one entry for each day,
#   `granularity` 86400000 (a day, in milliseconds), keyed by the start of the day in the SERVER's time zone with its
#   offset (`2026-10-07T00:00:00.000+03:00`; the offset changes over a change to summer time). A day with no
#   transfers is there with zeros, and so is a period years back.
# - Confirmed directly: a START after END is 400 "Incorrect date frame. 'startDate' must be before 'endDate'.", and an END
#   after today, a day that does not exist (`32/10/2026`) or START in the future is 400 "An error occur while generating
#   report for the following date frame". The reference gives no limit on the length of a period: a period of nine months
#   was answered at once.
# - Confirmed directly what the numbers are, by uploading and downloading with a test account and reading today's day
#   again: they follow the server within seconds (they are not cached or periodic). `ST.TransfersIn` goes up by one for
#   each file received, `ST.TransfersOut` by one for each file sent (a download over the EndUser API or FTP; a file
#   deleted through the API or FTP is logged as an outgoing transfer but is NOT counted). `ST.Transfers` is the number
#   to bill: it counts every inbound, the first outbound of a file's chain not at all and every later outbound: an
#   upload then two downloads gave In +1, Out +2, Transfers +2, so it is not In + Out. It can be larger than `ST.TransfersIn`
#   and smaller than the sum.
# - Confirmed directly: `ST.ActiveUsers` and `ST.Volume` read 0 on the lab in every call, also with
#   includeActiveUsersCount=true and includeIncomingFileVolume=true (and with the other spellings, 1, yes, TRUE, which
#   are accepted without complaint, as is `abc`), a 3 MB EndUser API upload, a 1 MB FTP upload and many logins that day. The
#   reference says they are 0 unless asked for; what makes them non-zero was not seen, so do not rely on them.
# - The answer also holds `envId`, `schemaId`, `timestamp` and a `meta` object: company name, product name and version,
#   the patch level, `isECEnabled`, `isADIEnabled`, the installed plugins, the time frame and the `reportSummary` (the
#   totals over the period, the same keys as a day's `usage`). Each day's own `meta` is `{}`. The reference's
#   `report` is a map keyed by day, not an array.
#   `meta.reportTimeframe` ends at the start of the day AFTER END (END 08/10 gives `2026-10-09T00:00:00`).
# - HEAD answers 400 (no dates); POST is 405.
# - Exit codes: 0 when the server answered 200, 1 when it refuses, 2 for a wrong argument (nothing is sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/statisticsSummary/generateReport"
START="${1:-$(date +%d/%m/%Y)}"
END="${2:-${START}}"
ACTIVE_USERS="${3:-false}"
VOLUME="${4:-false}"
DATE_PATTERN='^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$'
if ! [[ "${START}" =~ ${DATE_PATTERN} && "${END}" =~ ${DATE_PATTERN} ]] || [ -n "$5" ] \
    || { [ "${ACTIVE_USERS}" != "true" ] && [ "${ACTIVE_USERS}" != "false" ]; } \
    || { [ "${VOLUME}" != "true" ] && [ "${VOLUME}" != "false" ]; }; then
    printf "Usage: 01.statisticsSummary_generateReport_GET.sh [START [END [ACTIVE_USERS [VOLUME]]]]   (dates are dd/MM/yyyy, the last two true or false)\n"
    exit 2
fi

QUERY=(--data-urlencode "startDate=${START}" --data-urlencode "endDate=${END}")
[ "${ACTIVE_USERS}" = "true" ] && QUERY+=(--data-urlencode "includeActiveUsersCount=true")
[ "${VOLUME}" = "true" ] && QUERY+=(--data-urlencode "includeIncomingFileVolume=true")

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET -G "${MAIN_URL}" "${QUERY[@]}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s\n" "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi

printf '%s' "${RESPONSE}" | jq -r '
  (.report | to_entries | sort_by(.key)) as $days
  | "Statistics summary of \(.meta.productName) \(.meta.productVersion), environment \(.envId), one entry per \((.granularity // 0) / 3600000) hours",
    "Period: \(.meta.reportTimeframe.startDate) to \(.meta.reportTimeframe.endDate) (\($days | length) days)",
    "",
    "Day, transfers in, out, billable transfers, active users, volume:",
    ($days[] | "  \(.key[0:10])  in \(.value.usage["ST.TransfersIn"] // 0)  out \(.value.usage["ST.TransfersOut"] // 0)  transfers \(.value.usage["ST.Transfers"] // 0)  users \(.value.usage["ST.ActiveUsers"] // 0)  volume \(.value.usage["ST.Volume"] // 0)"),
    "",
    "Total: in \(.meta.reportSummary["ST.TransfersIn"] // 0)  out \(.meta.reportSummary["ST.TransfersOut"] // 0)  transfers \(.meta.reportSummary["ST.Transfers"] // 0)  users \(.meta.reportSummary["ST.ActiveUsers"] // 0)  volume \(.meta.reportSummary["ST.Volume"] // 0)"'
