#!/bin/bash
# ==============================================================================
# Script Name: 99.cleanup_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-11-09
# Location: Sofia
# ==============================================================================
# Description:
# Puts everything back. First what the scenarios made (their 99.objects_DELETE.sh: the routes, the subscriptions, the site, and the Fusion options), then the Sentinel settings, from the copy of step 02,
# and it reads them to check they are the same. Then the fake HTTP server is stopped, and the End User API deletes the files of the account, the overflow files among them, and the account example_qlt.
# Last the files of the use case. It is safe to run twice, and after a step that failed half way.
#
# Usage:
# ./99.cleanup_DELETE.sh
#
# Risk: config
#
# Notes:
# - Copied from Admin/API 2.0/bash/13.Configurations/20.configurations_sentinel_PUT.sh (the settings are sent back whole) and from Admin/API 2.0/bash/05.Accounts/07.accounts_name_DELETE.sh.
# - The settings go back before the overflow files are deleted, so that the server stops writing to them. The copy is PUT as it was read, and a new reading is compared with it, key by key.
#   Only when they are the same is the copy removed. When they are not, the script lists the keys, keeps the copy and exits 1.
# - A server on which Sentinel had never been set has no host to go back to, and once a host is set the settings refuse an empty one (400 "host must not be null or empty"). Then the script
#   turns reporting off with a PUT, and clears the host and the overflow file path with the server options AxwaySentinel.RemoteHost.host and AxwaySentinel.OverflowFile.path (and sets the
#   port and the overflow size and threshold options to what the copy had), as 20.configurations_sentinel_PUT.sh describes. Confirmed directly (the copy made up to look like a server that never had
#   Sentinel set): reporting off, the host and the path empty. The overflow size and threshold stay at 5 and 90 whatever is sent for them, so the comparison leaves those two out when the copy had none.
#   Some states of a transfer that were off before step 03 are on now: this script does not turn them off again (the copy puts them back when the host is set; otherwise it says so).
# - With no copy of the settings (step 02 never ran) it leaves them alone: nothing was changed.
# - The fake HTTP server is stopped by its process id, after checking that the process is a fake_http_server.py.
# - Confirmed directly: the End User API deletes an overflow file although the server made it (owner root, mode 644): the folder is the account's. The home folder stays on the server after the
#   account is deleted, and so does the copy of each upload that the file archiving keeps under /home/archives.
# - The names are the exact ones of lib.sh, never a pattern. An account that is not there (404) is fine.
# - Requires `jq`, which reads the settings and compares them.
# - Exit codes: 0 when all is back, 1 when the settings are not the same afterwards or something could not be deleted, 2 when a parameter is given.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./99.cleanup_DELETE.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
st_session

rc=0
echo "== The scenarios =="
for scenario in "${UC_DIR}"/[0-9]-*/99.objects_DELETE.sh; do
    [ -f "${scenario}" ] || continue
    printf '%s\n' "-- $(basename "$(dirname "${scenario}")")"
    bash "${scenario}" || rc=1
done

echo "== The Sentinel settings =="
if [ ! -s "${SAVED_FILE}" ]; then
    echo "There is no copy of the settings (step 02 did not run): they were not changed and are left as they are."
else
    SAVED_HOST=$(jq -r '.host // ""' "${SAVED_FILE}")
    if [ -n "${SAVED_HOST}" ]; then
        uc_send PUT configurations/sentinel "$(jq -c . "${SAVED_FILE}")"
        if [ "${LIST_CODE}" = "204" ]; then echo "The copy was sent back (HTTP 204)."; else printf "Sending the copy back: HTTP %s: %s\n" "${LIST_CODE}" "$(uc_why)"; rc=1; fi
    else
        echo "The server had no Sentinel host before. Turning reporting off, then clearing the host and the overflow file..."
        uc_get configurations/sentinel
        if [ "${LIST_CODE}" = "200" ]; then
            uc_send PUT configurations/sentinel "$(printf '%s' "${LIST_BODY}" | jq -c '.enabled = false | .heartbeatEnabled = false')"
            [ "${LIST_CODE}" = "204" ] || { printf "Turning reporting off: HTTP %s: %s\n" "${LIST_CODE}" "$(uc_why)"; rc=1; }
        fi
        uc_send PUT configurations/options "$(jq -cn --slurpfile saved "${SAVED_FILE}" '[
          {name: "AxwaySentinel.RemoteHost.host", values: [""]},
          {name: "AxwaySentinel.OverflowFile.path", values: [""]},
          {name: "AxwaySentinel.RemoteHost.port", values: [($saved[0].port // "" | tostring)]},
          {name: "AxwaySentinel.OverflowFile.size", values: [($saved[0].overflowFileSize // "" | tostring)]},
          {name: "AxwaySentinel.OverflowFile.threshold", values: [($saved[0].overflowFileThreshold // "" | tostring)]}]')"
        if [ "${LIST_CODE}" = "204" ]; then echo "The options were cleared (HTTP 204)."; else printf "Clearing the options: HTTP %s: %s\n" "${LIST_CODE}" "$(uc_why)"; rc=1; fi
    fi
    uc_get configurations/sentinel
    if [ "${LIST_CODE}" != "200" ]; then
        printf "Reading the settings: HTTP %s: %s\n" "${LIST_CODE}" "$(uc_why)"; rc=1
    else
        SKIP='[]'
        # a server that had no host had no size and no warning threshold either, and takes no empty value for them: they stay, and are harmless with reporting off.
        # Its states of a transfer were set by step 03 and are not turned off again here.
        [ -n "${SAVED_HOST}" ] || SKIP='["overflowFileSize", "overflowFileThreshold", "eventStates"]'
        DIFF=$(jq -n --slurpfile saved "${SAVED_FILE}" --argjson now "${LIST_BODY}" --argjson skip "${SKIP}" \
            '$saved[0] as $a | ($a | keys) + ($now | keys) | unique | map(. as $k | select($a[$k] != $now[$k] and ((($skip | index($k)) != null and ($k == "eventStates" or $a[$k] == null)) | not)))[]' 2>/dev/null)
        if [ -z "${DIFF}" ]; then
            echo "The settings read back are the same as the copy, key by key."
            rm -f "${SAVED_FILE}"
        else
            echo "The settings read back differ from the copy in:"
            printf '%s\n' "${DIFF}" | sed 's/^/  /'
            echo "The copy is kept in $(basename "${SAVED_FILE}"); put the settings right by hand."
            rc=1
        fi
    fi
fi

echo "== The fake HTTP server =="
uc_fake_stop

echo "== The files and the account =="
if [ -s "${PASSWORD_FILE}" ]; then
    FILES=$(uc_eu_files)
    if [ $? -eq 0 ]; then
        while IFS= read -r FILE; do
            [ -n "${FILE}" ] || continue
            code=$(uc_eu_delete "${FILE}")
            case "${code}" in
                204) echo "The file ${FILE} was deleted." ;;
                *) echo "The file ${FILE} could not be deleted (HTTP ${code})."; rc=1 ;;
            esac
        done <<< "${FILES}"
    else
        echo "The files of ${ACCOUNT} could not be listed: they are left."
    fi
else
    echo "There is no password for the account: its files are left."
fi
code=$(uc_delete "accounts/${ACCOUNT}")
case "${code}" in
    204) echo "The account ${ACCOUNT} was deleted." ;;
    404) echo "The account ${ACCOUNT} was not there." ;;
    *) echo "The account ${ACCOUNT} could not be deleted (HTTP ${code}): delete it by hand."; rc=1 ;;
esac
curl -k -s -o /dev/null -b "${JAR}" -X DELETE "${ST_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)"
rm -f "${JAR}" "${CSRF_FILE}" "${PASSWORD_FILE}" "${FAKE_LOG_FILE}"
echo "Cleaned up. The transfers stay in the transfer log."
exit "${rc}"
