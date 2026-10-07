#!/bin/bash
# ==============================================================================
# Script Name: 11.certificates_requests_id_HEAD.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script checks whether a certificate signing request exists, using the
# `/certificates/requests/{id}` endpoint with HEAD: 200 when it does, 404
# when it does not.
#
# Usage:
# ./11.certificates_requests_id_HEAD.sh [REQUEST_ID]
#
#   REQUEST_ID  the request's id (default: the one request for
#               CN=example_csr,O=Example, which 09 creates)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: a completed request is gone, 404.
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

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" --head "${MAIN_URL}/${REQUEST_ID}" \
  -H "accept: */*" -H "${REFERER_HEADER}")
if [ "${HTTP_CODE}" = "200" ]; then
    printf "The request %s exists.\n" "${REQUEST_ID}"
else
    printf "The request %s does not exist (HTTP %s).\n" "${REQUEST_ID}" "${HTTP_CODE}"
    exit 1
fi
