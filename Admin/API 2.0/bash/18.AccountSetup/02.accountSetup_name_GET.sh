#!/bin/bash
# ==============================================================================
# Script Name: 02.accountSetup_name_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads an account with everything around it, in one call, using
# the `/accountSetup/{name}` endpoint: the account, its certificates, transfer
# sites, transfer profiles, routes and subscriptions.
#
# Usage:
# ./02.accountSetup_name_GET.sh [ACCOUNT]
#
#   ACCOUNT  the account to read (default example_setup, which
#            01.accountSetup_POST.sh creates)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - With accept: application/json the certificates' properties come back; with
#   multipart/mixed, the certificates themselves are exported.
# - The answer is the same shape 01.accountSetup_POST.sh sends, so it can be
#   kept as a template for setting up a similar account.
# - Requires `jq`, which URL-encodes the account name and prints the summary.
# - Confirmed directly: an account that does not exist is 404 "Cannot find account with name X or it is not accessible" (a name with a space is
#   looked for as it is written, so it is encoded in the path); one with a / in it cannot be addressed (404).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

ACCOUNT="${1:-example_setup}"
ENCODED=$(jq -rn --arg name "${ACCOUNT}" '$name | @uri')

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accountSetup/${ENCODED}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"

if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the setup of %s (HTTP %s):\n%s\n" "${ACCOUNT}" "${HTTP_CODE}" "${RESPONSE}"
    exit 1
fi
printf '%s\n' "${RESPONSE}"
printf "\nIn short:\n"
printf '%s' "${RESPONSE}" | jq -r '.accountSetup |
  "  account            \(.account.name) (\(.account.type)), home \(.account.homeFolder)",
  "  certificates       \((.certificates.login + .certificates.partner + .certificates.private) | length)",
  "  sites              \([.sites[]?.name] | join(", "))",
  "  transfer profiles  \([.transferProfiles[]?.name] | join(", "))",
  "  routes             \(.routes | length)",
  "  subscriptions      \([.subscriptions[]?.folder] | join(", "))"'
