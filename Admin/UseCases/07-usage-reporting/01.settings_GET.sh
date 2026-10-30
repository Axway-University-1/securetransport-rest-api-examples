#!/bin/bash
# ==============================================================================
# Script Name: 01.settings_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Part 1, global usage, step 1: the release and the settings that shape the usage report. GET /version and GET /configurations/options?name=StatisticsSummaryReport*. Read only.
#
# Usage:
# ./01.settings_GET.sh
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/13.Configurations/03.configurations_options_GET.sh, with the name filter StatisticsSummaryReport*, and from Admin/API 2.0/bash/02.Introduction/01.version_GET.sh.
# - The values of ClientSecret and of any other setting with Secret in its name are not printed: a secret stays a secret in its encrypted form too.
# - Ask for limit=100: a list is 100 entries when no limit is given, and there are 15 of these settings on the lab.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./01.settings_GET.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
st_session

uc_get version
if [ "${LIST_CODE}" != "200" ]; then printf "GET /version: HTTP %s: %s\n" "${LIST_CODE}" "$(uc_why)"; exit 1; fi
printf '%s' "${LIST_BODY}" | jq -r '"Release \(.version), \(.serverType)"'

uc_get configurations/options "name=StatisticsSummaryReport*" "limit=100"
if [ "${LIST_CODE}" != "200" ]; then printf "GET /configurations/options: HTTP %s: %s\n" "${LIST_CODE}" "$(uc_why)"; exit 1; fi
COUNT=$(printf '%s' "${LIST_BODY}" | jq -r '.resultSet.totalCount // 0')
if [ "${COUNT}" = "0" ]; then echo "The server has no StatisticsSummaryReport* setting: this release has no usage report."; exit 1; fi
echo "The ${COUNT} settings of the usage report:"
printf '%s' "${LIST_BODY}" | jq -r '.result[] | "  \(.name) = \(if (.name | test("Secret")) then "(hidden)" else (.values | join(", ")) end)"'
echo
echo "The ones that shape the report:"
for name in StatisticsSummaryReport.AutomaticReport StatisticsSummaryReport.AutomaticReport.DaysToInclude StatisticsSummaryReport.ActiveUsersCount StatisticsSummaryReport.TransfersIn StatisticsSummaryReport.Volume StatisticsSummaryReport.FilePath; do
    printf '%s' "${LIST_BODY}" | jq -r --arg n "${name}" '(.result[] | select(.name == $n)) as $o | "  \($o.name): \($o.values | join(", ") | if . == "" then "(empty)" else . end)"'
done
echo "ST.ActiveUsers and ST.Volume were 0 in every report on the lab, with these settings and with the include... parameters of the call (see the README)."
