#!/bin/bash
# ==============================================================================
# Script Name: 01.mailTemplates_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the mail templates using the `/mailTemplates` endpoint: the
# XHTML files SecureTransport builds its notification e-mails from.
# It demonstrates:
# - Counting them
# - Listing them, one line each with the description
# - Searching by name, and by description (both exact)
#
# Usage:
# ./01.mailTemplates_GET.sh [NAME [DESCRIPTION]]
#
#   NAME         a template's exact name, e.g. AdhocDefault.xhtml (optional)
#   DESCRIPTION  an exact description (optional)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: the answer is {resultSet, result}; each entry has name, description
#   (null when there is none) and metadata.links.self. The list is sorted by name, ignoring case.
# - Confirmed directly: name= and description= are exact and case sensitive, with no * wildcard
#   (name=Account* finds nothing), and resultSet.totalCount still counts every template.
# - Confirmed directly: limit=-1 answers 400 "The limit should be a positive number or 0."; limit=0
#   gives the default page size.
# - The server ships templates of its own, for its notification e-mails: do not change them without
#   keeping a copy (04.mailTemplates_name_GET.sh saves one).
# - Requires `jq`, which prints one template per line.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
#   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
# - Exit codes: 0 when every answer is 200, 1 otherwise, 2 when there are more than two arguments (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/mailTemplates"
NAME="$1"
DESCRIPTION="$2"
if [ "$#" -gt 2 ]; then
    printf "Usage: ./01.mailTemplates_GET.sh [NAME [DESCRIPTION]]\n"
    exit 2
fi
LINE='"  \(.name)  \(.description // "-")"'

# st_get CURL_ARGUMENTS...: a GET of the URL given (with any curl options, such as -G --data-urlencode ...). The answer
# is left in RESPONSE. A status other than 200 ends the script with exit 1, after printing the status and the answer.
st_get() {
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "$@" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "HTTP %s\n" "${HTTP_CODE}"
        [ -n "${RESPONSE}" ] && printf '%s\n' "${RESPONSE}"
        exit 1
    fi
}

printf "Mail templates: "
st_get "${MAIN_URL}?limit=1&fields=name"
printf '%s\n' "${RESPONSE}" | jq -r '.resultSet.totalCount'

printf "\nAll of them: name, description:\n"
st_get "${MAIN_URL}?limit=100"
printf '%s\n' "${RESPONSE}" | jq -r "(.result // [])[] | ${LINE}"

if [ -n "${NAME}" ]; then
    printf "\nNamed %s:\n" "${NAME}"
    st_get -G "${MAIN_URL}" --data-urlencode "name=${NAME}"
    printf '%s\n' "${RESPONSE}" | jq -r "(.result // [])[] | ${LINE}"
fi

if [ -n "${DESCRIPTION}" ]; then
    printf "\nDescribed as %s:\n" "${DESCRIPTION}"
    st_get -G "${MAIN_URL}" --data-urlencode "description=${DESCRIPTION}"
    printf '%s\n' "${RESPONSE}" | jq -r "(.result // [])[] | ${LINE}"
fi
