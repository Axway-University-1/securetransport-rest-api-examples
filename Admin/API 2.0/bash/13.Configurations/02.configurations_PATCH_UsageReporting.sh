#!/bin/bash
# ==============================================================================
# Script Name: 02.configurations_PATCH_UsageReporting.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script configures the automatic usage reporting to the Axway Platform, by patching the ten
# StatisticsSummaryReport Server Configuration Options, using the `/configurations/options/{name}` endpoint.
# It demonstrates:
# - Every value taken from an environment variable: the client secret is never in the file, and a value that is missing, or still
#   a placeholder such as <PUT YOUR CLIENT ID HERE>, stops the script before anything is sent
# - The old values of all ten options read and printed first, so that they can be put back
# - Request bodies built with jq, and an exit at the first option the server refuses
#
# Usage:
# export ST_USAGE_CLIENT_ID='...'
# export ST_USAGE_CLIENT_SECRET='...'
# export ST_USAGE_ENVIRONMENT_ID='...'
# export ST_USAGE_ENVIRONMENT_NAME='...'
# export ST_USAGE_FILE_PATH='/a/folder/on/the/server'
# export ST_USAGE_PLATFORM_API='https://...'
# export ST_USAGE_PLATFORM_AUTHENTICATION='https://...'
# export ST_USAGE_SCHEMA_ID='https://...'
# export ST_USAGE_DAYS_TO_INCLUDE='3'
# export ST_USAGE_NETWORK_ZONE='...'      (optional)
# ./02.configurations_PATCH_UsageReporting.sh
#
#   The client, secret and environment are the ones of the Axway Platform (https://platform.axway.com/). ST_USAGE_FILE_PATH is a folder on the server where the
#   reports are written. The platform addresses are the ones the server has by default in newer versions. ST_USAGE_NETWORK_ZONE is the edge the connection to the
#   platform must pass through: when it is not set, the option is set to empty. Without the nine others, or with one that is still a placeholder, the script
#   prints what is missing, sends NOTHING and exits 2.
#
# Risk: config - writes ten server wide options, among them a client secret; the script prints the old values first
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This writes ten server wide options, among them a client secret. The secret is read from the environment only, so it is in no file and no argument, and the script never prints it.
#   (The old value of the secret is printed as the server keeps it, encrypted: `{AES128}...`.)
# - The old values of the ten options are read first (an option that cannot be read stops the script before any change) and printed as `option: [values]`. To put them back, set the
#   variables to them and run the script again: the encrypted secret is accepted as it is, and the server keeps it unchanged.
# - Requires `jq`, which reads the old values and builds each request body.
# - Each option is patched with `replace` of `/values`. The script stops at the first answer that is not 2xx and says which options were changed already.
# - Confirmed directly: each PATCH answers 204 with no body. The options read `readOnly` true and are patched anyway. An option sent the already encrypted text of its own secret reads back unchanged;
#   a plain value sent to ClientSecret is stored encrypted, and the encrypted text differs on every write. The server checks no value against its meaning ("abc" was accepted for the number of days),
#   so the script checks the days and the two addresses itself. An option is cleared with `[""]`.
# - NOT run against the Amplify Platform: only against the lab's own options, which were put back (check 21). With AutomaticReport on, the server sends a report with these settings.
# - Exit codes: 0 when every option was set, 1 when an option cannot be read or the server refuses one, 2 when a variable is missing or still a placeholder (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations/options"
SCO="StatisticsSummaryReport"
# The option, the environment variable that holds its value, and whether the value may be empty
OPTIONS=("${SCO}.ClientId" "${SCO}.ClientSecret" "${SCO}.EnvironmentId" "${SCO}.EnvironmentName" "${SCO}.FilePath" "${SCO}.NetworkZone" "${SCO}.Platform.API" "${SCO}.Platform.Authentication" "${SCO}.SchemaId" "${SCO}.AutomaticReport.DaysToInclude")
VARIABLES=(ST_USAGE_CLIENT_ID ST_USAGE_CLIENT_SECRET ST_USAGE_ENVIRONMENT_ID ST_USAGE_ENVIRONMENT_NAME ST_USAGE_FILE_PATH ST_USAGE_NETWORK_ZONE ST_USAGE_PLATFORM_API ST_USAGE_PLATFORM_AUTHENTICATION ST_USAGE_SCHEMA_ID ST_USAGE_DAYS_TO_INCLUDE)

# Nothing is sent until every value is there and none is a placeholder.
PROBLEMS=0
for i in "${!OPTIONS[@]}"; do
    VARIABLE="${VARIABLES[$i]}"
    VALUE="${!VARIABLE}"
    if [ -z "${VALUE}" ]; then
        # only the network zone may be left empty: the option is then set to empty
        if [ "${VARIABLE}" != "ST_USAGE_NETWORK_ZONE" ]; then
            printf "%s is not set (it is the value of %s).\n" "${VARIABLE}" "${OPTIONS[$i]}"
            PROBLEMS=1
        fi
        continue
    fi
    case "${VALUE}" in
        "<"*">"|*"PUT YOUR"*) printf "%s still holds a placeholder: %s\n" "${VARIABLE}" "${VALUE}"; PROBLEMS=1 ;;
    esac
done
if [ -n "${ST_USAGE_DAYS_TO_INCLUDE}" ] && ! [[ "${ST_USAGE_DAYS_TO_INCLUDE}" =~ ^[0-9]{1,4}$ ]]; then
    printf "ST_USAGE_DAYS_TO_INCLUDE is a whole number of days, not %s.\n" "${ST_USAGE_DAYS_TO_INCLUDE}"
    PROBLEMS=1
fi
for VARIABLE in ST_USAGE_PLATFORM_API ST_USAGE_PLATFORM_AUTHENTICATION; do
    if [ -n "${!VARIABLE}" ] && [[ "${!VARIABLE}" != https://* ]]; then
        printf "%s is an https address, not %s.\n" "${VARIABLE}" "${!VARIABLE}"
        PROBLEMS=1
    fi
done
if [ "${PROBLEMS}" -ne 0 ]; then
    printf "Nothing was sent. Set the variables listed above (see the usage in the header of this script) and run it again.\n"
    exit 2
fi

option_uri() { jq -rn --arg name "$1" '$name | @uri'; }

printf "Reading the old values of the %s options...\n" "${#OPTIONS[@]}"
for OPTION in "${OPTIONS[@]}"; do
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}/$(option_uri "${OPTION}")" --data-urlencode "fields=values" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "Could not read %s: HTTP %s. Nothing was changed.\n" "${OPTION}" "${HTTP_CODE}"
        printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
        exit 1
    fi
    printf "  %s: %s\n" "${OPTION}" "$(printf '%s' "${RESPONSE}" | jq -c '.values')"
done

CHANGED=""
for i in "${!OPTIONS[@]}"; do
    OPTION="${OPTIONS[$i]}"
    VARIABLE="${VARIABLES[$i]}"
    VALUE="${!VARIABLE}"
    if [ "${VARIABLE}" = "ST_USAGE_CLIENT_SECRET" ]; then SHOWN="(hidden)"; else SHOWN="${VALUE}"; fi
    BODY=$(jq -cn --arg value "${VALUE}" '[{op: "replace", path: "/values", value: [$value]}]')
    printf "Updating %s to '%s'...\n" "${OPTION}" "${SHOWN}"
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/$(option_uri "${OPTION}")" -H "accept: */*" -H "${REFERER_HEADER}" \
      -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    printf "HTTP %s\n" "${HTTP_CODE}"
    if ! [[ "${HTTP_CODE}" =~ ^2[0-9][0-9]$ ]]; then
        printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
        if [ -n "${CHANGED}" ]; then printf "Already changed:%s\n" "${CHANGED}"; fi
        printf "Stopped at %s. The old values are listed above.\n" "${OPTION}"
        exit 1
    fi
    CHANGED="${CHANGED} ${OPTION}"
done
printf "Done: %s options set. The old values are listed above.\n" "${#OPTIONS[@]}"
