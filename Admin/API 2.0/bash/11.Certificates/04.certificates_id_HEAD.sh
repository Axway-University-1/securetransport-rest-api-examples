#!/bin/bash
# ==============================================================================
# Script Name: 04.certificates_id_HEAD.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script checks whether a certificate exists, using the
# `/certificates/{id}` endpoint with HEAD: 200 when it does, 404 when it
# does not.
#
# Usage:
# ./04.certificates_id_HEAD.sh [NAME]
#
#   NAME  the certificate's name (default example_cert)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The certificate is looked up by name, and must be the only one with that name.
# - Requires `jq`, which reads the id.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/certificates"
NAME="${1:-example_cert}"
# The one certificate with that name: "1 <id>", or how many there are
read -r FOUND CERT_ID < <(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "name=${NAME}" \
  --data-urlencode "fields=id" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '.result // [] | if length == 1 then "1 \(.[0].id)" else "\(length)" end')
if [ "${FOUND}" != "1" ]; then
    printf "Found %s certificates named %s; this script acts on exactly one.\n" "${FOUND:-0}" "${NAME}"
    exit 1
fi

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" --head "${MAIN_URL}/${CERT_ID}" \
  -H "accept: */*" -H "${REFERER_HEADER}")
if [ "${HTTP_CODE}" = "200" ]; then
    printf "The certificate %s exists, id %s.\n" "${NAME}" "${CERT_ID}"
else
    printf "The certificate %s, id %s, does not exist (HTTP %s).\n" "${NAME}" "${CERT_ID}" "${HTTP_CODE}"
    exit 1
fi
