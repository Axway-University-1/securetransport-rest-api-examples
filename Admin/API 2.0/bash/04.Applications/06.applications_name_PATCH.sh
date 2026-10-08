#!/bin/bash
# ==============================================================================
# Script Name: 06.applications_name_PATCH.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script performs partial updates to an application using the
# `/applications/{name}` endpoint with the PATCH method.
# It demonstrates:
# - Updating the notes field
# - Updating the startDate of the first schedule, when the application has one
#
# Usage:
# ./06.applications_name_PATCH.sh [NAME]
#
#   NAME  the application (default example_filepurge, one of the two 02.applications_POST.sh creates)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - PATCH allows partial updates without replacing the entire object.
# - It first reads the application and prints the old notes and, when there is one, the first schedule's start date (as an ISO date, ready to be sent back), then the body that undoes
#   each change. The new start date is the day after tomorrow, 00:00 UTC: a ONCE schedule needs a date in the future.
# - An application with no schedule, such as example_humansystem or a File Maintenance application created with the default SCHEDULE none, has no `/schedules/0/startDate` to replace,
#   so that patch is skipped and said so. Only the notes are patched.
# - Requires `jq`, which reads the application and builds each patch.
# - Confirmed directly: each PATCH answers 204 with no body. Replacing `/schedules/0/startDate` works on an application that has a schedule (seen on an ArchiveMaint example, not on a
#   File Maintenance one: the lab has one that is not ours) and the date reads back as milliseconds. A start date in the past, which is what this script used to send (2025-02-21),
#   is 400 "startDate occurs before the current moment."; on an application with no schedules the path is 400 `Missing field "schedules"`.
# - Confirmed directly (on an ArchiveMaint example with a ONCE schedule): the server derives the schedule's `executionTimes` from the time of day of the start date in its own time
#   zone. This one is at +03:00: a start date of 00:00:00Z was read back with `executionTimes` ["03:00"], and the old start date, sent back as the ISO date this script prints, restored
#   both, compared exactly. A PUT that sends the application back as it was read, the start date still the milliseconds, is 204 and changes nothing.
# - Exit codes: 0 when every patch sent was answered 204, 1 when the application cannot be read or the server refuses a patch (the later one is not sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications"
NAME="${1:-example_filepurge}"
if [ "$#" -gt 1 ]; then
    printf "Usage: 06.applications_name_PATCH.sh [NAME]\n"
    exit 2
fi
NAME_URI=$(jq -rn --arg name "${NAME}" '$name | @uri')

# patch DESCRIPTION BODY: send one JSON Patch document; stop the script when the server does not answer 204
patch() {
    printf "%s...\n" "$1"
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X "PATCH" "${MAIN_URL}/${NAME_URI}" -H "accept: application/json" -H "${REFERER_HEADER}" \
      -H "Content-Type: application/json" -d "$2" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    printf "HTTP %s\n" "${HTTP_CODE}"
    if [ "${HTTP_CODE}" != "204" ]; then
        printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
        exit 1
    fi
}

printf "Getting the application %s...\n" "${NAME}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "${MAIN_URL}/${NAME_URI}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the application %s: HTTP %s\n" "${NAME}" "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
OLD_NOTES=$(printf '%s' "${RESPONSE}" | jq -r '.notes // ""')
# The server answers a start date as the epoch in milliseconds, in text; turn it into a date that can be sent back
OLD_START=$(printf '%s' "${RESPONSE}" | jq -r 'if ((.schedules // []) | length) > 0
  then (.schedules[0].startDate | tostring | if test("^[0-9]+$") then ((tonumber / 1000) | floor | todate) else . end) else empty end')
printf "The notes of %s are now '%s'.\n" "${NAME}" "${OLD_NOTES}"
printf "To put them back, PATCH this body: %s\n" "$(jq -cn --arg value "${OLD_NOTES}" '[{op: "replace", path: "/notes", value: $value}]')"
if [ -n "${OLD_START}" ]; then
    printf "The start date of the first schedule is now %s.\n" "${OLD_START}"
    printf "To put it back, PATCH this body: %s\n" "$(jq -cn --arg value "${OLD_START}" '[{op: "replace", path: "/schedules/0/startDate", value: $value}]')"
fi

patch "Patching the application '${NAME}' to change the notes" "$(jq -cn '[{op: "replace", path: "/notes", value: "Patched note"}]')"

if [ -n "${OLD_START}" ]; then
    # A start date has to be in the future: the day after tomorrow, 00:00 UTC
    START_DATE=$(date -u -v+2d +"%Y-%m-%dT00:00:00Z" 2>/dev/null || date -u -d "+2 days" +"%Y-%m-%dT00:00:00Z")
    patch "Patching the application '${NAME}' to change the startDate" "$(jq -cn --arg value "${START_DATE}" '[{op: "replace", path: "/schedules/0/startDate", value: $value}]')"
else
    printf "The application has no schedule, so there is no startDate to change.\n"
fi

#
# Here is an example of adding a new Business Unit to a given application,
# when there are already other Business Units assigned
#
# patch "Patching the application to add a new Business Unit" "$(jq -cn '[{op: "add", path: "/businessUnits/-", value: "HumanResources"}]')"
