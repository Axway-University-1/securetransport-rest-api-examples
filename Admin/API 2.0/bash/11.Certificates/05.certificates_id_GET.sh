#!/bin/bash
# ==============================================================================
# Script Name: 05.certificates_id_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads a certificate, using the `/certificates/{id}` endpoint.
# It demonstrates:
# - The whole certificate, as JSON
# - Its SHA256 fingerprint, base64 encoded, with fingerprintAlgorithm=
# - Its path to the root, with includePath=true
#
# Usage:
# ./05.certificates_id_GET.sh [NAME]
#
#   NAME  the certificate's name (default example_cert)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The certificate is looked up by name, and must be the only one with that name.
# - Confirmed directly: with includePath=true the answer is an array, the
#   certificate first and then each certificate above it.
# - The same GET with "accept: multipart/mixed" exports the file as well;
#   08.certificates_id_operations_POST_export.sh is the simpler way.
# - Requires `jq`, which reads the id and prints the summary.
# - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
#   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
# - Exit codes: 0 when every answer is 200 and exactly one object is found, 1 otherwise, 2 when there are too many arguments (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/certificates"
NAME="${1:-example_cert}"
if [ "$#" -gt 1 ]; then
    printf "Usage: ./05.certificates_id_GET.sh [NAME]\n"
    exit 2
fi

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

# The one certificate with that name: "1 <id>", or how many there are
st_get -G "${MAIN_URL}" --data-urlencode "name=${NAME}" --data-urlencode "fields=id"
read -r FOUND CERT_ID < <(printf '%s\n' "${RESPONSE}" | jq -r '.result // [] | if length == 1 then "1 \(.[0].id)" else "\(length)" end')
if [ "${FOUND}" != "1" ]; then
    printf "Found %s certificates named %s; this script acts on exactly one.\n" "${FOUND:-0}" "${NAME}"
    exit 1
fi

st_get "${MAIN_URL}/${CERT_ID}"
printf '%s' "${RESPONSE}"

printf "\n\nIts SHA256 fingerprint: "
st_get "${MAIN_URL}/${CERT_ID}?fingerprintAlgorithm=SHA256&base64EncodedFingerprint=true&fields=fingerprint"
printf '%s\n' "${RESPONSE}" | jq -r '.fingerprint'

printf "\nIts path, from the certificate up:\n"
st_get "${MAIN_URL}/${CERT_ID}?includePath=true&fields=name,subject"
printf '%s\n' "${RESPONSE}" | jq -r '.[] | "  \(.name)  \(.subject)"'
