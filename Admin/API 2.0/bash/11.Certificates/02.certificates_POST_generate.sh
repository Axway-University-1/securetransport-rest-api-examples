#!/bin/bash
# ==============================================================================
# Script Name: 02.certificates_POST_generate.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script generates a new certificate on the server, using the
# `/certificates` endpoint: the server creates the key pair and signs the
# certificate with its own certificate authority (CA).
#
# Usage:
# ./02.certificates_POST_generate.sh [DAYS]
#
#   DAYS  how many days the certificate is valid (default 365)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It generates example_cert, a local x509 certificate - one the server itself
#   uses, for example for a TLS listener. usage private with account set makes
#   an account's own key pair instead.
# - caPassword is the password of the server's CA, which signs the
#   certificate: any other value answers 400 "Specify a valid CA Password."
#   CA_PASSWORD is read from the environment, so export it first:
#     export CA_PASSWORD='the CA password'
# - Confirmed directly: the answer is 201 multipart/mixed, the certificate's
#   JSON in its first part; the new id is also in the Location header, which is
#   where this script reads it.
# - Requires `jq`, which builds the body.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/certificates"
NAME="example_cert"
DAYS="${1:-365}"
[[ "${DAYS}" =~ ^[1-9][0-9]*$ ]] || { printf "DAYS must be a whole number: %s\n" "${DAYS}"; exit 2; }
if [ -z "${CA_PASSWORD}" ]; then
    printf "Set CA_PASSWORD to the password of the server's certificate authority first.\n"
    exit 2
fi
HEADERS_FILE="$(mktemp)"
trap 'rm -f "${HEADERS_FILE}"' EXIT

BODY=$(jq -n --arg name "${NAME}" --argjson days "${DAYS}" --arg ca "${CA_PASSWORD}" \
  '{name: $name, type: "x509", usage: "local", subject: "CN=\($name),O=Example", keySize: 2048,
    signAlgorithm: "SHA256withRSA", validityPeriod: $days, caPassword: $ca}')

printf "Generating %s, valid %s days...\n" "${NAME}" "${DAYS}"
HTTP_CODE=$(curl -s -o /dev/null -D "${HEADERS_FILE}" -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "201" ] || exit 1
printf "The new certificate's id: %s\n" "$(grep -i '^location:' "${HEADERS_FILE}" | tr -d '\r' | sed 's#.*/##')"
