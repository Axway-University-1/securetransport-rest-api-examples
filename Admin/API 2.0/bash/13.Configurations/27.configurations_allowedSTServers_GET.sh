#!/bin/bash
# ==============================================================================
# Script Name: 27.configurations_allowedSTServers_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the SecureTransport servers allowed to connect, using the
# `/configurations/allowedSTServers` endpoint.
#
# Usage:
# ./27.configurations_allowedSTServers_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: a standalone server answers 404 here; the list belongs
#   to a deployment where servers connect to each other. PUT and PATCH replace
#   and change it there.
# - Requires `jq`, which prints the servers.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/allowedSTServers" -H "accept: application/json" \
  -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "No list of allowed servers here (HTTP %s).\n" "${HTTP_CODE}"
    exit 1
fi
printf '%s\n' "${RESPONSE}"
