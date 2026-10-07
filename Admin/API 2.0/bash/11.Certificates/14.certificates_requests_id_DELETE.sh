#!/bin/bash
# ==============================================================================
# Script Name: 14.certificates_requests_id_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes a certificate signing request, and the private key the
# server kept for it, using the `/certificates/requests/{id}` endpoint.
#
# Usage:
# ./14.certificates_requests_id_DELETE.sh [REQUEST_ID]
#
#   REQUEST_ID  the request's id (default: the one request for
#               CN=example_csr,O=Example, which 09 creates)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A certificate the CA signs for a deleted request can no longer be
#   completed: its private key is gone.
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

printf "Deleting the request %s...\n" "${REQUEST_ID}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${REQUEST_ID}" \
  -H "accept: */*" -H "${REFERER_HEADER}")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "204" ]
