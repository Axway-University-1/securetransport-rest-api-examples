#!/bin/bash
# ==============================================================================
# Script Name: 06.certificates_id_PATCH.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script changes a certificate, using the `/certificates/{id}` endpoint
# with PATCH: it makes the certificate visible to every administrator
# (accessLevel PUBLIC) and tags it with an additional attribute.
#
# Usage:
# ./06.certificates_id_PATCH.sh [NAME [ACCESS_LEVEL]]
#
#   NAME          the certificate's name (default example_cert)
#   ACCESS_LEVEL  PRIVATE, PUBLIC or BUSINESS_UNIT (default PUBLIC)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The certificate is looked up by name, and must be the only one with that name.
# - Confirmed directly: PATCH works on accessLevel, additionalAttributes and
#   the external store fields only. Anything else answers 400 with that list.
#   A certificate's content cannot change: generate or import a new one.
# - Confirmed directly: a success answers 204, with no body.
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
ACCESS_LEVEL="${2:-PUBLIC}"
[[ "${ACCESS_LEVEL}" =~ ^(PRIVATE|PUBLIC|BUSINESS_UNIT)$ ]] \
    || { printf "ACCESS_LEVEL is PRIVATE, PUBLIC or BUSINESS_UNIT, not %s.\n" "${ACCESS_LEVEL}"; exit 2; }
# The one certificate with that name: "1 <id>", or how many there are
read -r FOUND CERT_ID < <(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "name=${NAME}" \
  --data-urlencode "fields=id" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '.result // [] | if length == 1 then "1 \(.[0].id)" else "\(length)" end')
if [ "${FOUND}" != "1" ]; then
    printf "Found %s certificates named %s; this script acts on exactly one.\n" "${FOUND:-0}" "${NAME}"
    exit 1
fi

printf "Setting accessLevel of %s to %s, and tagging it...\n" "${NAME}" "${ACCESS_LEVEL}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/${CERT_ID}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "[{\"op\":\"replace\",\"path\":\"/accessLevel\",\"value\":\"${ACCESS_LEVEL}\"},
       {\"op\":\"add\",\"path\":\"/additionalAttributes/userVars.owner\",\"value\":\"example\"}]")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "204" ]
