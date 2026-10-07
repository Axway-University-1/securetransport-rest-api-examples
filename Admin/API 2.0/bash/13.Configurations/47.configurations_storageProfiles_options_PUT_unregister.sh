#!/bin/bash
# ==============================================================================
# Script Name: 47.configurations_storageProfiles_options_PUT_unregister.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script removes the S3 storage profile example_s3, using the
# `/configurations/options` endpoint with PUT: it takes example_s3 out of the
# option StorageProfiles.S3.Registry, which removes the profile's own options.
#
# Usage:
# ./47.configurations_storageProfiles_options_PUT_unregister.sh
#
# Risk: config
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The other profiles in the registry stay.
# - Confirmed directly: an empty registry is set with [""]; an empty list
#   answers 400 "Invalid argument length."
# - Requires `jq`, which reads the registry.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
PROFILE="example_s3"
REGISTRY=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/options/StorageProfiles.S3.Registry" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -c --arg profile "${PROFILE}" '[(.values // [])[] | select(. != "" and . != $profile)] | if length == 0 then [""] else . end')

printf "Removing %s; the registry becomes %s\n" "${PROFILE}" "${REGISTRY}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/options" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "[{\"name\":\"StorageProfiles.S3.Registry\",\"values\":${REGISTRY}}]" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
