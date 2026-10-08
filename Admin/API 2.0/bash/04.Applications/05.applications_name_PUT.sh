#!/bin/bash
# ==============================================================================
# Script Name: 05.applications_name_PUT.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script updates an application using the `/applications/{name}` endpoint.
# It demonstrates:
# - Retrieving the full application object
# - Modifying the notes field (by default with a timestamp)
# - Sending a PUT request to update the application
#
# Usage:
# ./05.applications_name_PUT.sh [NAME [NOTES]]
#
#   NAME   the application (default example_filepurge, one of the two 02.applications_POST.sh creates)
#   NOTES  the new notes (default "New note" and the time, in UTC); "" for none
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - PUT replaces the entire object, so all required fields must be preserved: the script sends back the object it read, with only the notes changed.
# - It prints the old notes, and the command that puts them back, before it changes anything.
# - Requires `jq`, which is used to edit the retrieved JSON. No file is written: the answer is kept in a variable.
# - On a server that already has an AccountFilePurge application, 02 does not create example_filepurge (only one is allowed): use example_humansystem.
# - Confirmed directly: a success is 204 with no body (also for a flow application sent back as it was read); the new notes read back at once.
# - Exit codes: 0 when the server answered 204, 1 when the application cannot be read or the server refuses, 2 when there are too many arguments (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications"
NAME="${1:-example_filepurge}"
if [ "$#" -gt 2 ]; then
    printf "Usage: 05.applications_name_PUT.sh [NAME [NOTES]]\n"
    exit 2
fi
if [ "$#" -ge 2 ]; then
    NEW_NOTES="$2"
else
    NEW_NOTES="New note $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
fi
NAME_URI=$(jq -rn --arg name "${NAME}" '$name | @uri')

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
printf "The notes of %s are now '%s'.\n" "${NAME}" "${OLD_NOTES}"
printf "To put them back: ./05.applications_name_PUT.sh %s %q\n" "${NAME}" "${OLD_NOTES}"

#
# Edit the retrieved object with jq. This targets the notes field itself and
# always produces valid JSON, which a text substitution cannot guarantee.
#
BODY=$(printf '%s' "${RESPONSE}" | jq -c --arg notes "${NEW_NOTES}" '.notes = $notes')

printf "Changing the notes...\n"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X "PUT" "${MAIN_URL}/${NAME_URI}" -H "accept: application/json" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
