#!/bin/bash
# ==============================================================================
# Script Name: 04.administrators_name_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads an administrator, using the `/administrators/{name}`
# endpoint: the role, the parent, the rights the role gives, the password and
# login times, and the API keys.
#
# Usage:
# ./04.administrators_name_GET.sh [ADMIN]
#
#   ADMIN  the login name (default example_admin)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The password itself never comes back: password is empty.
# - Requires `jq`, which URL-encodes the login name and prints the summary.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrators"
ADMIN="${1:-example_admin}"
ENCODED=$(jq -rn --arg name "${ADMIN}" '$name | @uri')

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENCODED}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read %s (HTTP %s):\n%s\n" "${ADMIN}" "${HTTP_CODE}" "${RESPONSE}"
    exit 1
fi
printf '%s\n' "${RESPONSE}"
printf "\nIn short:\n"
printf '%s' "${RESPONSE}" | jq -r '
  "  \(.loginName), role \(.roleName), created by \(.parent // "-")\(if .locked then ", LOCKED" else "" end)",
  "  rights: \([.administratorRights | to_entries[] | select(.value) | .key] | join(", "))",
  "  last login \(.passwordCredentials.lastLoginTime // "never"), API keys \(.apiKeys | length)"'
