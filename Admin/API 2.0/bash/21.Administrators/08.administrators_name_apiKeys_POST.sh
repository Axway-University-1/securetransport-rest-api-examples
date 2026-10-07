#!/bin/bash
# ==============================================================================
# Script Name: 08.administrators_name_apiKeys_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script creates an API key for an administrator, using the
# `/administrators/{name}/api-keys` endpoint. An API key authenticates every
# request on its own, in the SECURETRANSPORT-API-KEY header: no login, no
# session, no password - for scripts and integrations.
#
# Usage:
# ./08.administrators_name_apiKeys_POST.sh [DAYS [PERMISSIONS]]
#
#   DAYS         how many days the key is valid (default 30)
#   PERMISSIONS  read, write and delete, comma separated (default read).
#                read is GET and HEAD; write is POST, PUT and PATCH; delete is
#                DELETE.
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The administrator is example_admin, which 02.administrators_POST.sh creates.
# - The key itself is in this answer only. Keep it: the server stores only a
#   hash, and the list (09.administrators_name_apiKeys_GET.sh) never shows it.
# - Confirmed directly: an administrator holds at most 2 keys (a third answers
#   409); validityDays or expiresAt (RFC 2822), not both (400).
# - 10.administrators_name_apiKeys_keyId_DELETE.sh revokes keys.
# - Requires `jq`, which builds the body and reads the key.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrators"
ADMIN="example_admin"
DAYS="${1:-30}"
PERMISSIONS="${2:-read}"
[[ "${DAYS}" =~ ^[1-9][0-9]*$ ]] || { printf "DAYS must be a whole number: %s\n" "${DAYS}"; exit 2; }

BODY=$(jq -n --argjson days "${DAYS}" --arg permissions "${PERMISSIONS}" \
  '{validityDays: $days, permissions: ($permissions | split(","))}')

printf "Creating a %s day key for %s, permissions %s...\n" "${DAYS}" "${ADMIN}" "${PERMISSIONS}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}/${ADMIN}/api-keys" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "201" ]; then
    printf "HTTP %s:\n%s\n" "${HTTP_CODE}" "${RESPONSE}"
    exit 1
fi
printf '%s' "${RESPONSE}" | jq -r '"Key id \(.id), valid until \(.expiresAt), permissions \(.permissions | join(", "))"'
printf "The key, shown this once: %s\n" "$(printf '%s' "${RESPONSE}" | jq -r '.key')"
