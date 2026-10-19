#!/bin/bash
# ==============================================================================
# Script Name: 06.configurations_options_name_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads one Server Configuration Option, using the
# `/configurations/options/{name}` endpoint: its values, its default, its
# description, and whether it can be changed.
#
# Usage:
# ./06.configurations_options_name_GET.sh [NAME]
#
#   NAME  the option (default AddressBook.Enabled)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
# - encrypted options, passwords for example, come back empty.
# - Requires `jq`, which prints the summary.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${ST_ADMIN_LOCAL_VARIABLES:-${SCRIPT_DIR}/../set_variables.local.sh}" ||
    { echo "Copy set_variables.local.example.sh to set_variables.local.sh and fill it in."; exit 1; }

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
NAME="${1:-AddressBook.Enabled}"

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/options/${NAME}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read %s (HTTP %s):\n%s\n" "${NAME}" "${HTTP_CODE}" "${RESPONSE}"
    exit 1
fi
printf '%s\n' "${RESPONSE}"
printf "\nIn short:\n"
printf '%s' "${RESPONSE}" | jq -r '
  "  \(.name) = \(.values | join(", ")), default \(.defaultValues | join(", "))",
  "  \(if .readOnly then "read only" else "can be changed" end)\(if .encrypted then ", encrypted" else "" end)\(if .isLocal then ", local to this server" else "" end)"'
