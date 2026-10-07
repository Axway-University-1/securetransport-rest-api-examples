#!/bin/bash
# ==============================================================================
# Script Name: 12.certificates_requests_id_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads a certificate signing request, using the
# `/certificates/requests/{id}` endpoint.
#
# Usage:
# ./12.certificates_requests_id_GET.sh [REQUEST_ID]
#
#   REQUEST_ID  the request's id (default: the one request for
#               CN=example_csr,O=Example, which 09 creates)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: the answer is the request's JSON only, never the CSR;
#   asking for anything but JSON answers 406. Keep the CSR
#   09.certificates_requests_POST.sh writes.
# - Requires `jq`, which looks the id up.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/certificates/requests"
REQUEST_ID="$1"
if [ -z "${REQUEST_ID}" ]; then
    REQUEST_ID=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "subject=CN=example_csr,O=Example" \
      -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.result // [] | if length == 1 then .[0].id else empty end')
    if [ -z "${REQUEST_ID}" ]; then
        printf "No single request for CN=example_csr,O=Example; give the request's id.\n"
        exit 1
    fi
fi

curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${REQUEST_ID}" -H "accept: application/json" -H "${REFERER_HEADER}"
printf "\n"
