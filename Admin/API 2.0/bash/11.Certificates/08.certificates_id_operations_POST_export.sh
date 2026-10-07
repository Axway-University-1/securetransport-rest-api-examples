#!/bin/bash
# ==============================================================================
# Script Name: 08.certificates_id_operations_POST_export.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script exports a certificate to a file, using the
# `/certificates/{id}/operations` endpoint with operation=export: PEM, DER
# (crt), or PKCS#12 with its private key.
#
# Usage:
# ./08.certificates_id_operations_POST_export.sh [NAME [FORMAT]]
#
#   NAME    the certificate's name (default example_cert)
#   FORMAT  pem, crt or pkcs12 (default pem)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The certificate is looked up by name, and must be the only one with that name.
# - The file is NAME.pem, NAME.crt or NAME.p12, in the current folder.
# - pkcs12 holds the private key too, encrypted with EXPORT_PASSWORD, read from
#   the environment: export EXPORT_PASSWORD='a password' first. It is chosen
#   freely; nothing checks it.
# - Confirmed directly: the body must be a multipart form, even for pem and
#   crt, whose exportPassword may be empty. Without one: 400 "Entity is
#   empty." includePath=true adds the certificates above it to a pem.
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
FORMAT="${2:-pem}"
case "${FORMAT}" in
    pem) EXTENSION="pem" ;;
    crt) EXTENSION="crt" ;;
    pkcs12) EXTENSION="p12"
        [ -n "${EXPORT_PASSWORD}" ] || { printf "Set EXPORT_PASSWORD first: it protects the private key.\n"; exit 2; } ;;
    *) printf "FORMAT is pem, crt or pkcs12, not %s.\n" "${FORMAT}"; exit 2 ;;
esac
# The one certificate with that name: "1 <id>", or how many there are
read -r FOUND CERT_ID < <(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "name=${NAME}" \
  --data-urlencode "fields=id" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '.result // [] | if length == 1 then "1 \(.[0].id)" else "\(length)" end')
if [ "${FOUND}" != "1" ]; then
    printf "Found %s certificates named %s; this script acts on exactly one.\n" "${FOUND:-0}" "${NAME}"
    exit 1
fi
OUTPUT="${NAME}.${EXTENSION}"

printf "Exporting %s as %s to %s...\n" "${NAME}" "${FORMAT}" "${OUTPUT}"
HTTP_CODE=$(curl -s -o "${OUTPUT}" -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X POST \
  "${MAIN_URL}/${CERT_ID}/operations?operation=export&format=${FORMAT}" \
  -H "accept: application/octet-stream" -H "${REFERER_HEADER}" -F "exportPassword=${EXPORT_PASSWORD}")
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "200" ]; then
    cat "${OUTPUT}"; printf "\n"
    rm -f "${OUTPUT}"
    exit 1
fi
printf "Wrote %s, %s bytes.\n" "${OUTPUT}" "$(wc -c < "${OUTPUT}" | tr -d ' ')"
