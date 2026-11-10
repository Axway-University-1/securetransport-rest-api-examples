#!/bin/bash
# ==============================================================================
# Script Name: 03.sentinel_PATCH.sh
# Author: Plamen Milenkov
# Created: 2026-11-09
# Location: Sofia
# ==============================================================================
# Description:
# Step 3: tell the server to report EVERY event it can to a Sentinel that cannot be reached, and to keep them in a file when that fails. The Sentinel is at 192.0.2.1, an address reserved for
# documentation that nothing answers. Every state of a transfer in the Sentinel settings is turned on (the ones that were off, and the ones the settings do not list yet), so that everything the server can
# report is reported. The overflow file is set to the reads file in the home folder of example_qlt; each scenario turns it to a file of its own while its flow runs. Sentinel, Workbench and Event Router all take
# the same events (the QLT protocol), so what the files hold is what any of them would have received.
#
# Usage:
# ./03.sentinel_PATCH.sh [HOST] [PORT]
#
#   HOST  the Sentinel that cannot be reached (default 192.0.2.1)
#   PORT  its port (default 1305); give a HOST with it
#
# Risk: config
#
# Notes:
# - Copied from Admin/API 2.0/bash/13.Configurations/19.configurations_sentinel_PATCH.sh, which also turns on the heartbeat; this one leaves it as it is.
# - It changes the settings of the whole server, so it needs the copy of step 02 and stops without one (exit 1). While they are changed the events of every transfer on the server, not
#   only this account's, go to the overflow file, and a real Sentinel, Workbench or Event Router gets none of them. 99.cleanup_DELETE.sh puts the settings back.
# - The patch replaces the host, the port and the overflow file path and turns reporting on. It adds the size and the warning threshold of the overflow file when the server has none. Every state that is
#   `false` becomes `true` (a state that is `required` stays so). A state the server does not list is added: the list is the one of the reference (lib.sh) plus whatever the server lists.
# - A state whose name has a slash in it, POST_PROC/ROUTED, is addressed in the patch with ~1 for the slash (a JSON Pointer), and a ~ with ~0. Confirmed directly.
# - Confirmed directly: a host that cannot be reached is not an error of the call. The server accepts the settings (204) and the failure shows only as events going to the file. Mostly they
#   are in it within a second or two.
# - Confirmed directly: the server makes the overflow file when it writes the first event to it (a change of the settings alone makes none), as large as its size setting (5 MB on this lab),
#   owned by root and readable by anyone (mode 644). It is a circular buffer: when it is full the oldest events are overwritten. The policy `ignore` (the default) then stops collecting new events; `stop` would pause
#   every transfer of the server, which this use case never sets.
# - Requires `jq`, which builds the patch from the copy and prints the settings.
# - Exit codes: 0 when the server answered 204, 1 when there is no copy or the server refuses, 2 when a parameter is wrong (nothing sent).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./03.sentinel_PATCH.sh [HOST] [PORT]"
HOST="${1:-${FAKE_HOST}}"
PORT="${2:-${FAKE_PORT}}"
if [ "$#" -gt 2 ] || [ -z "${HOST}" ] || ! [[ "${PORT}" =~ ^[0-9]+$ ]] || [ "${PORT}" -lt 1 ] || [ "${PORT}" -gt 65535 ]; then printf "%s\n" "${USAGE}"; exit 2; fi
[ -s "${SAVED_FILE}" ] || { echo "The Sentinel settings are not kept: run 02.sentinel_GET.sh first. Nothing was changed."; exit 1; }
st_session

BODY=$(jq -c --arg host "${HOST}" --argjson port "${PORT}" --arg path "/home/${ACCOUNT}/${READS_NAME}" --argjson all "$(printf '%s\n' "${ALL_STATES[@]}" | jq -R . | jq -s .)" '
  def pointer: gsub("~"; "~0") | gsub("/"; "~1");
  (.eventStates // {}) as $states |
  [{op: "replace", path: "/host", value: $host}, {op: "replace", path: "/port", value: $port},
   {op: "replace", path: "/overflowFilePath", value: $path}, {op: "replace", path: "/enabled", value: true}]
  + (if .overflowFileSize == null then [{op: "add", path: "/overflowFileSize", value: 5}] else [] end)
  + (if .overflowFileThreshold == null then [{op: "add", path: "/overflowFileThreshold", value: 90}] else [] end)
  + [($all + ($states | keys) | unique)[] as $state | select(($states[$state] // "false") == "false")
     | {op: (if $states | has($state) then "replace" else "add" end), path: ("/eventStates/" + ($state | pointer)), value: "true"}]' "${SAVED_FILE}")
CHANGED_STATES=$(printf '%s' "${BODY}" | jq '[.[] | select(.path | startswith("/eventStates/"))] | length')

echo "Reporting to ${HOST}:${PORT}, with the overflow file ${READS_NAME}, and turning on ${CHANGED_STATES} state(s) that were off or unknown..."
uc_send PATCH configurations/sentinel "${BODY}"
printf "HTTP %s\n" "${LIST_CODE}"
if [ "${LIST_CODE}" != "204" ]; then uc_why; exit 1; fi

uc_get configurations/sentinel
if [ "${LIST_CODE}" != "200" ]; then printf "GET /configurations/sentinel: HTTP %s: %s\n" "${LIST_CODE}" "$(uc_why)"; exit 1; fi
echo "The settings are now:"
printf '%s' "${LIST_BODY}" | jq -r '"  reporting: \(if .enabled then "on" else "off" end), to \(.host):\(.port)",
  "  overflow file: \(.overflowFilePath) (\(.overflowFileSize) MB, warning at \(.overflowFileThreshold) %, policy \(.overflowFilePolicy))",
  "  states reported: \([(.eventStates // {}) | to_entries[] | select(.value != "false")] | length) of \((.eventStates // {}) | length), \([(.eventStates // {}) | to_entries[] | select(.value == "required")] | length) of them required"'
OFF=$(printf '%s' "${LIST_BODY}" | jq -r '[(.eventStates // {}) | to_entries[] | select(.value == "false") | .key] | join(", ")')
if [ -n "${OFF}" ]; then echo "  still off: ${OFF}"; exit 1; fi
