#!/bin/bash
# ==============================================================================
# Script Name: 13.certificates_requests_id_POST_complete.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script completes a certificate signing request, using the
# `/certificates/requests/{id}` endpoint with POST: it uploads the
# certificate the certificate authority signed, and the server pairs it with
# the private key it kept. The result is a new certificate; the request is
# gone.
#
# Usage:
# ./13.certificates_requests_id_POST_complete.sh SIGNED_CERT [REQUEST_ID]
#
#   SIGNED_CERT  the certificate the CA signed, PEM or DER
#   REQUEST_ID  the request's id (default: the one request for
#               CN=example_csr,O=Example, which 09 creates)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The certificate is named example_csr_cert (alias).
# - Confirmed directly: the answer is 200 with the new certificate's JSON. A
#   certificate signed by a CA the server does not trust is accepted, and reads
#   "Not chained to a trusted root": import the CA as a trusted certificate
#   first.
# - 07.certificates_id_DELETE.sh example_csr_cert removes the certificate.
# - Requires `jq`, which looks the id up and reads the answer.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/certificates/requests"
SIGNED_CERT="$1"
shift
if [ ! -f "${SIGNED_CERT}" ]; then
    printf "Usage: ./13.certificates_requests_id_POST_complete.sh SIGNED_CERT [REQUEST_ID]\n"
    exit 2
fi
REQUEST_ID="$1"
if [ -z "${REQUEST_ID}" ]; then
    REQUEST_ID=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "subject=CN=example_csr,O=Example" \
      -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.result // [] | if length == 1 then .[0].id else empty end')
    if [ -z "${REQUEST_ID}" ]; then
        printf "No single request for CN=example_csr,O=Example; give the request's id.\n"
        exit 1
    fi
fi

printf "Completing the request %s with %s...\n" "${REQUEST_ID}" "${SIGNED_CERT}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}/${REQUEST_ID}" -H "accept: application/json" -H "${REFERER_HEADER}" \
  -F "alias=example_csr_cert" -F "certificateFile=@${SIGNED_CERT}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf '%s\n' "${RESPONSE}"
    exit 1
fi
printf '%s' "${RESPONSE}" | jq -r '"The new certificate \(.name), id \(.id), expires \(.expirationTime)"'
