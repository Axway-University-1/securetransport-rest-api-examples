#!/bin/bash
# ==============================================================================
# Script Name: 02.applications_POST.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script creates applications using the `/applications` endpoint.
# It demonstrates:
# - Creating a flow application (HumanSystem), named example_humansystem
# - Checking for an application of a maintenance type first, since the server allows only one of each
# - Creating a maintenance application (AccountFilePurge) with a detailed schema, named example_filepurge, with no schedule unless you ask for one
#
# Usage:
# ./02.applications_POST.sh [SCHEDULE]
#
#   SCHEDULE  none (default): the maintenance application is created with no schedule, so it never runs by itself
#             once: it gets a ONCE schedule that starts tomorrow at 00:00 and deletes files then (see Notes)
#
# Risk: write - creates a flow application and a File Maintenance one that deletes files when it is scheduled (none unless asked)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The two applications are example_humansystem and example_filepurge, so running this bare changes nothing that matters. 07.applications_name_DELETE.sh removes them.
#   The other scripts of this folder act on example_filepurge by default.
# - WHAT THE MAINTENANCE APPLICATION DOES. An AccountFilePurge application is a File Maintenance job: according to the reference, `deleteFilesDays` is the retention period (files older
#   than that many days are deleted), `pattern` the file names it considers (`*.txt` here) and `removeFolders` makes it remove the folders left empty. This one keeps 90 days, matches
#   *.txt and removes empty folders. It acts on the accounts that subscribe to it, and this script subscribes none. With the default SCHEDULE (none) the `schedules` list is empty and it
#   never runs by itself; with `once` it runs at 00:00 of tomorrow, in the server's time zone, and deletes what that retention and pattern say for the accounts that subscribed.
# - Only one application of a given maintenance type is allowed per server. Confirmed directly: a second AccountFilePurge application is refused, with or without a schedule, 400
#   "Application of type AccountFilePurge already exists. Only one instance of this type is allowed." The script therefore looks for one by type first (GET /applications?type=AccountFilePurge),
#   says so and creates none when there is one, under any name. That is not an error (the exit code stays 0). The lab has one that is not ours, so the creation of example_filepurge was
#   NOT seen on the lab: it is written from the reference and tested against a stub `curl`. The flow application has no such limit, and its creation was seen.
# - Confirmed directly: a creation answers 201 with no body; a name that exists is 400 "An application with this name already exists." (not 409); a name with a space is accepted
#   and addressed as %20. A flow application is created with only `type`, `name` and `notes`.
# - Requires `jq`, which builds each body. A ONCE schedule needs a start date in the future, so it is computed from today rather than written in the file.
# - Exit codes: 0 when everything asked for was created or skipped for the reason above, 1 when the server refuses a creation (the other is still tried), 2 when SCHEDULE is wrong (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications"
PURGE_NAME="example_filepurge"
FLOW_NAME="example_humansystem"
SCHEDULE="${1:-none}"
USAGE="Usage: 02.applications_POST.sh [SCHEDULE]   (SCHEDULE is none, the default, or once)"
if [ "$#" -gt 1 ] || { [ "${SCHEDULE}" != "none" ] && [ "${SCHEDULE}" != "once" ]; }; then
    printf "%s\n" "${USAGE}"
    exit 2
fi

FAILED=0

# create_application DESCRIPTION BODY
create_application() {
    printf "Creating %s...\n" "$1"
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" -H "accept: */*" -H "${REFERER_HEADER}" \
      -H "Content-Type: application/json" -d "$2" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    printf "HTTP %s\n" "${HTTP_CODE}"
    if [ "${HTTP_CODE}" != "201" ]; then
        printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
        FAILED=1
    fi
}

# A flow application: only the type, the name and the notes
BODY=$(jq -cn --arg name "${FLOW_NAME}" '{type: "HumanSystem", name: $name, notes: "This is a HumanSystem application"}')
create_application "a HumanSystem application (${FLOW_NAME})" "${BODY}"

# A maintenance application. Only one of each type is allowed on a server, so look for one by type first.
TYPE="AccountFilePurge"
printf "Looking for an application of type '%s'...\n" "${TYPE}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "type=${TYPE}" --data-urlencode "fields=name" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not look for it: HTTP %s\n" "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
EXISTING=$(printf '%s' "${RESPONSE}" | jq -r '[(.result // [])[].name] | join(", ")')
if [ -n "${EXISTING}" ]; then
    printf "An application of type '%s' exists already (%s): the server allows only one, so none was created.\n" "${TYPE}" "${EXISTING}"
else
    # A ONCE schedule needs a start date in the future, so this is computed
    # relative to today rather than hardcoded to a date that will eventually
    # be in the past.
    START_DATE=$(date -u -v+1d +"%Y-%m-%dT00:00:00Z" 2>/dev/null || date -u -d "+1 day" +"%Y-%m-%dT00:00:00Z")
    BODY=$(jq -cn --arg name "${PURGE_NAME}" --arg type "${TYPE}" --arg schedule "${SCHEDULE}" --arg start "${START_DATE}" '
      {type: $type, name: $name, notes: ("This is an " + $type + " application"),
       deleteFilesDays: 90, pattern: "*.txt", expirationPeriod: true, removeFolders: true, notifyDays: "90",
       sendSentinelAlert: false, warnNotifyAccount: false, deletionNotifications: false, deletionNotifyAccount: false,
       schedules: (if $schedule == "once"
                   then [{tag: $type, type: "ONCE", executionTimes: ["00:00"], startDate: $start, skipHolidays: false}]
                   else [] end)}')
    create_application "an ${TYPE} application (${PURGE_NAME}, schedule ${SCHEDULE})" "${BODY}"
fi
exit "${FAILED}"
