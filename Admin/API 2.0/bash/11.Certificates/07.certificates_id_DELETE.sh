#!/bin/bash
# ==============================================================================
# Script Name: 07.certificates_id_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes a certificate, using the `/certificates/{id}` endpoint.
#
# Usage:
# ./07.certificates_id_DELETE.sh [NAME]
#
#   NAME  the certificate's name (default example_cert, which
#         02.certificates_POST_generate.sh creates)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The certificate is looked up by name, and must be the only one with that name.
# - Only ever point it at a certificate you created: a site, a listener or a
#   partner may depend on it.
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

printf "Deleting the certificate %s, id %s...\n" "${NAME}" "${CERT_ID}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${CERT_ID}" \
  -H "accept: */*" -H "${REFERER_HEADER}")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "204" ]
