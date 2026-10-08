#!/bin/bash
# ==============================================================================
# Script Name: 07.applications_name_DELETE.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes applications using the `/applications/{name}` endpoint.
# For each application it first reads it, to say what it is about to delete, and deletes it if it exists.
#
# By default it cleans up the two applications created by 02.applications_POST.sh.
#
# Usage:
# ./07.applications_name_DELETE.sh [NAME...]
#
#   NAME  the applications to delete (default example_filepurge and example_humansystem, the ones 02.applications_POST.sh creates)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This script deletes data. Application names with spaces must be URL-encoded: the script does it with jq.
# - Only ever point this at names this folder's own POST script created. A server's built-in maintenance applications (Audit Log Maintenance, Transfer Log
#   Maintenance and the others) are real housekeeping jobs, not test data, and the lab's own AccountFilePurge application is not ours either: any name can be given, so check it.
#   Each application is read first and its type is printed, so that a wrong name shows before it is deleted.
# - Requires `jq`, which URL-encodes each name and reads the application.
# - Confirmed directly: a delete is 204 with no body; an application that is not there is 404; an application that still has a subscription cannot be deleted (400 "has active subscriptions").
# - Exit codes: 0 when every application named was deleted or was not there, 1 when the server refused one (the others are still tried), 2 when a name is empty (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications"
if [ "$#" -gt 0 ]; then
    NAMES=("$@")
else
    NAMES=(example_filepurge example_humansystem)
fi
for NAME in "${NAMES[@]}"; do
    if [ -z "${NAME}" ]; then
        printf "An application name must not be empty.\nUsage: 07.applications_name_DELETE.sh [NAME...]\n"
        exit 2
    fi
done

FAILED=0
for NAME in "${NAMES[@]}"; do
    NAME_URI=$(jq -rn --arg name "${NAME}" '$name | @uri')

    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}/${NAME_URI}" --data-urlencode "fields=type" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" = "404" ]; then
        printf "Application %s does not exist.\n" "${NAME}"
        continue
    fi
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "Could not read the application %s: HTTP %s\n" "${NAME}" "${HTTP_CODE}"
        printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
        FAILED=1
        continue
    fi
    printf "Application exists. Deleting application '%s' (type %s)...\n" "${NAME}" "$(printf '%s' "${RESPONSE}" | jq -r '.type')"
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X "DELETE" "${MAIN_URL}/${NAME_URI}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    printf "HTTP %s\n" "${HTTP_CODE}"
    if [ "${HTTP_CODE}" != "204" ]; then
        printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
        FAILED=1
    fi
done
exit "${FAILED}"
