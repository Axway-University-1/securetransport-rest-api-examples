#!/bin/bash
# ==============================================================================
# Script Name: 03.certificates_POST_import_partner.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script imports a partner's certificate for an account, using the
# `/certificates` endpoint with a multipart/mixed body: the certificate's JSON
# in the first part, the certificate file in the second. The account then
# trusts the partner, for example to verify or encrypt files with it.
#
# Usage:
# ./03.certificates_POST_import_partner.sh ACCOUNT CERT_FILE
#
#   ACCOUNT    the account the partner certificate belongs to
#   CERT_FILE  the partner's certificate, PEM or DER, for example the
#              example_cert.pem 08.certificates_id_operations_POST_export.sh
#              writes
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It imports the certificate as example_partner.
# - Confirmed directly: an import answers 200 with the certificate's JSON, not
#   the 201 a generate answers.
# - Deleting the account deletes its certificates too.
# - A private key is imported as a PKCS#12 file with usage private, its
#   password in password; see the API reference.
# - Requires `jq`, which builds the JSON part and reads the answer.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/certificates"
ACCOUNT="$1"
CERT_FILE="$2"
if [ -z "${ACCOUNT}" ] || [ ! -f "${CERT_FILE}" ]; then
    printf "Usage: ./03.certificates_POST_import_partner.sh ACCOUNT CERT_FILE\n"
    exit 2
fi
BODY_FILE="$(mktemp)"
trap 'rm -f "${BODY_FILE}"' EXIT

# The multipart/mixed body: the JSON part, then the file part
{
    printf -- '--BOUNDARY\r\nContent-Type: application/json\r\n\r\n'
    jq -cjn --arg account "${ACCOUNT}" '{name: "example_partner", type: "x509", usage: "partner", account: $account}'
    printf -- '\r\n--BOUNDARY\r\nContent-Type: application/octet-stream\r\n\r\n'
    cat "${CERT_FILE}"
    printf -- '\r\n--BOUNDARY--\r\n'
} > "${BODY_FILE}"

printf "Importing %s as example_partner for %s...\n" "${CERT_FILE}" "${ACCOUNT}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" -H "accept: application/json" -H "${REFERER_HEADER}" \
  -H "Content-Type: multipart/mixed; boundary=BOUNDARY" --data-binary "@${BODY_FILE}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "200" ] && [ "${HTTP_CODE}" != "201" ]; then
    printf '%s\n' "${RESPONSE}"
    exit 1
fi
printf '%s' "${RESPONSE}" | jq -r '"Imported \(.name), id \(.id), subject \(.subject), expires \(.expirationTime)"'
