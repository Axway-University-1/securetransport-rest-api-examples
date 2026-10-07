#!/bin/bash
# ==============================================================================
# Script Name: 01.certificates_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the certificates using the `/certificates` endpoint.
# It demonstrates:
# - Counting them, and listing a page
# - Searching by usage (private, local, partner, login, trusted) and type
# - The ones that expire within a number of days, with expirationTime.to
#
# Usage:
# ./01.certificates_GET.sh [USAGE [DAYS]]
#
#   USAGE  private, local, partner, login or trusted (default local)
#   DAYS   list the ones that expire within this many days (default 30)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: expirationTime.from and .to are in milliseconds since
#   1970, though the API reference says a Unix timestamp. In seconds they find
#   nothing.
# - account= lists one account's certificates.
# - Requires `jq`, which prints one certificate per line.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/certificates"
USAGE="${1:-local}"
DAYS="${2:-30}"
[[ "${DAYS}" =~ ^[0-9]+$ ]] || { printf "DAYS must be a whole number: %s\n" "${DAYS}"; exit 2; }

printf "Certificates on the server: "
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?limit=1&fields=id" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '.resultSet.totalCount'

printf "\nThe x509 %s ones: name, subject, expires:\n" "${USAGE}"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?usage=${USAGE}&type=x509&fields=name,subject,expirationTime" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '(.result // [])[] | "  \(.name)  \(.subject)  \(.expirationTime)"'

# Now and the limit, in milliseconds
NOW=$(( $(date +%s) * 1000 ))
UNTIL=$(( NOW + DAYS * 86400 * 1000 ))
printf "\nThe %s ones that expire within %s days:\n" "${USAGE}" "${DAYS}"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET \
  "${MAIN_URL}?usage=${USAGE}&expirationTime.from=${NOW}&expirationTime.to=${UNTIL}&fields=name,account,expirationTime" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '(.result // [])[] | "  \(.name)  \(.account // "-")  \(.expirationTime)"'
