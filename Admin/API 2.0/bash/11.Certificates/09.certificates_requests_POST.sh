#!/bin/bash
# ==============================================================================
# Script Name: 09.certificates_requests_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script generates a certificate signing request (CSR) on the server,
# using the `/certificates/requests` endpoint. The server keeps the private
# key; the CSR goes to a certificate authority, and the certificate it signs
# comes back with 13.certificates_requests_id_POST_complete.sh.
#
# Usage:
# ./09.certificates_requests_POST.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The request is for CN=example_csr,O=Example, a local certificate - one the
#   server itself uses. usage private, with account, is for an account's key.
# - The CSR is written to example_csr.req, in the current folder.
# - Confirmed directly: the answer is 201 multipart/mixed, the request's JSON
#   then the CSR. That is the only place the CSR is: a GET of the request
#   answers its JSON alone.
# - Requires `jq`, which reads the id.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/certificates/requests"
OUTPUT="example_csr.req"
RESPONSE_FILE="$(mktemp)"
trap 'rm -f "${RESPONSE_FILE}"' EXIT

printf "Generating a request for %s...\n" "CN=example_csr,O=Example"
HTTP_CODE=$(curl -s -o "${RESPONSE_FILE}" -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d '{"subject":"CN=example_csr,O=Example","usage":"local","keySize":2048,"signAlgorithm":"SHA256withRSA"}')
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "201" ]; then
    cat "${RESPONSE_FILE}"; printf "\n"
    exit 1
fi

# The JSON part holds the id; the second part is the CSR itself
tr -d '\r' < "${RESPONSE_FILE}" | sed -n '/-----BEGIN CERTIFICATE REQUEST-----/,/-----END CERTIFICATE REQUEST-----/p' > "${OUTPUT}"
printf "The request's id: %s\n" "$(tr -d '\r' < "${RESPONSE_FILE}" | grep -m 1 '"id"' | sed 's/.*"id" *: *"\([^"]*\)".*/\1/')"
printf "Wrote the CSR to %s; send it to your certificate authority.\n" "${OUTPUT}"
