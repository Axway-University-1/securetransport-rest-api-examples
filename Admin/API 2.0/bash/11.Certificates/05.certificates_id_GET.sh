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
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The certificate is looked up by name, and must be the only one with that name.
# - Confirmed directly: with includePath=true the answer is an array, the
#   certificate first and then each certificate above it.
# - The same GET with "accept: multipart/mixed" exports the file as well;
#   08.certificates_id_operations_POST_export.sh is the simpler way.
# - Requires `jq`, which reads the id and prints the summary.
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

curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${CERT_ID}" -H "accept: application/json" -H "${REFERER_HEADER}"

printf "\n\nIts SHA256 fingerprint: "
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET \
  "${MAIN_URL}/${CERT_ID}?fingerprintAlgorithm=SHA256&base64EncodedFingerprint=true&fields=fingerprint" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.fingerprint'

printf "\nIts path, from the certificate up:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${CERT_ID}?includePath=true&fields=name,subject" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.[] | "  \(.name)  \(.subject)"'
