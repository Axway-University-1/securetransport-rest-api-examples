#!/bin/bash
# ==============================================================================
# Script Name: 01.certificates_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the certificates using the `/certificates` endpoint.
# It demonstrates:
# - Counting them, and listing a page
# - Searching by usage (private, local, partner, login, trusted) and type
# - The ones that expire within a number of days, with expirationTime.to
#
# Usage:
# ./01.certificates_GET.sh [USAGE [DAYS]]
#
#   USAGE  private, local, partner, login or trusted (default local); anything else is refused with exit 2, nothing sent
#   DAYS   list the ones that expire within this many days (default 30)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: expirationTime.from and .to are in milliseconds since
#   1970, though the API reference says a Unix timestamp. In seconds they find
#   nothing.
# - account= lists one account's certificates.
# - Requires `jq`, which prints one certificate per line.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
#   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
# - Confirmed directly: usage= takes those five words, in any case (LOCAL finds what local does), and a word it does not know
#   (ca, signer, server) is not an empty list but 403 "Insufficient permissions to perform the operation", which says nothing
#   of the usage. The script refuses such a word first.
# - Exit codes: 0 when every answer is 200, 1 otherwise, 2 when an argument is wrong (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/certificates"
USAGE="${1:-local}"
DAYS="${2:-30}"
if [ "$#" -gt 2 ]; then
    printf "Usage: ./01.certificates_GET.sh [USAGE [DAYS]]\n"
    exit 2
fi
if ! [[ "${USAGE}" =~ ^(private|local|partner|login|trusted)$ ]]; then
    printf "USAGE is private, local, partner, login or trusted, not %s.\n" "${USAGE}"
    exit 2
fi
[[ "${DAYS}" =~ ^[0-9]+$ ]] || { printf "DAYS must be a whole number: %s\n" "${DAYS}"; exit 2; }

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

printf "Certificates on the server: "
st_get "${MAIN_URL}?limit=1&fields=id"
printf '%s\n' "${RESPONSE}" | jq -r '.resultSet.totalCount'

printf "\nThe x509 %s ones: name, subject, expires:\n" "${USAGE}"
st_get "${MAIN_URL}?usage=${USAGE}&type=x509&fields=name,subject,expirationTime"
printf '%s\n' "${RESPONSE}" | jq -r '(.result // [])[] | "  \(.name)  \(.subject)  \(.expirationTime)"'

# Now and the limit, in milliseconds
NOW=$(( $(date +%s) * 1000 ))
UNTIL=$(( NOW + DAYS * 86400 * 1000 ))
printf "\nThe %s ones that expire within %s days:\n" "${USAGE}" "${DAYS}"
st_get "${MAIN_URL}?usage=${USAGE}&expirationTime.from=${NOW}&expirationTime.to=${UNTIL}&fields=name,account,expirationTime"
printf '%s\n' "${RESPONSE}" | jq -r '(.result // [])[] | "  \(.name)  \(.account // "-")  \(.expirationTime)"'
