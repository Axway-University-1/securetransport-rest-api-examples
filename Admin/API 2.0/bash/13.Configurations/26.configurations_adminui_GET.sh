#!/bin/bash
# ==============================================================================
# Script Name: 26.configurations_adminui_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads the Admin UI configuration, using the
# `/configurations/adminui` endpoint: which pages and dashboard cards the
# Admin UI shows.
#
# Usage:
# ./26.configurations_adminui_GET.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - adminUiConfig is a JSON document inside a string; jq's fromjson reads it.
# - PUT and PATCH exist, for the Admin UI's own use only.
# - Requires `jq`, which prints the pages.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/adminui" -H "accept: application/json" \
  -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s:\n%s\n" "${HTTP_CODE}" "${RESPONSE}"
    exit 1
fi
printf '%s\n' "${RESPONSE}"
printf "\nIn short:\n"
printf '%s' "${RESPONSE}" | jq -r '.adminUiConfig | fromjson | .pages | to_entries[] | "  \(.key): \(if .value.enabledPage == false then "hidden" else "shown" end)"'
