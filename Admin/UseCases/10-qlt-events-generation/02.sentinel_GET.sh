#!/bin/bash
# ==============================================================================
# Script Name: 02.sentinel_GET.sh
# Author: Plamen Milenkov
# Created: 2026-11-09
# Location: Sofia
# ==============================================================================
# Description:
# Step 2: write down the Sentinel settings of the server, exactly as they are, before step 03 changes them. They are the settings of the whole server: whatever Sentinel, Workbench or Event
# Router the server reports to now, this is where it is told so. The copy is kept in state.local.sentinel.json (git ignores it) and 99.cleanup_DELETE.sh puts it back.
#
# Usage:
# ./02.sentinel_GET.sh
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/13.Configurations/18.configurations_sentinel_GET.sh.
# - It never overwrites the copy. A copy that is there is the settings of before the first run, and the settings now may be the ones of step 03: the script says so and keeps it.
#   Remove the copy only by hand, and only when the settings on the server are the ones you want to keep.
# - Requires `jq`, which prints the summary.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./02.sentinel_GET.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
st_session

summary() {
    jq -r 'def dash: if . == null or . == "" then "-" else . end;
           "  reporting: \(if .enabled then "on" else "off" end), to \(.host | dash):\(.port | dash)",
           "  overflow file: \(.overflowFilePath | dash) (\(.overflowFileSize | dash) MB, warning at \(.overflowFileThreshold | dash) %, policy \(.overflowFilePolicy | dash))",
           "  transfer states reported: \([(.eventStates // {}) | to_entries[] | select(.value != "false")] | length) of \((.eventStates // {}) | length)"'
}

if [ -s "${SAVED_FILE}" ]; then
    echo "The settings are kept already, in $(basename "${SAVED_FILE}"). They are not overwritten: they are the ones of before this use case."
    summary < "${SAVED_FILE}"
    exit 0
fi

uc_get configurations/sentinel
if [ "${LIST_CODE}" != "200" ]; then printf "GET /configurations/sentinel: HTTP %s: %s\n" "${LIST_CODE}" "$(uc_why)"; exit 1; fi
umask 077
printf '%s\n' "${LIST_BODY}" > "${SAVED_FILE}"
echo "The Sentinel settings of the server, kept in $(basename "${SAVED_FILE}"):"
summary < "${SAVED_FILE}"
