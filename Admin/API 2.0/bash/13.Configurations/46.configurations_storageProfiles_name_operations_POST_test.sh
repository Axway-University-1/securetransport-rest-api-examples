#!/bin/bash
# ==============================================================================
# Script Name: 46.configurations_storageProfiles_name_operations_POST_test.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script tests an S3 storage profile, using the
# `/configurations/storageProfiles/{storageProfile}/operations` endpoint with
# operation=test: the server connects to the bucket with the profile's saved
# settings.
#
# Usage:
# ./46.configurations_storageProfiles_name_operations_POST_test.sh [PROFILE]
#
#   PROFILE  the storage profile (default example_s3)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: a working profile answers 204; the server asks for the
#   bucket (HEAD /<bucket>). An unknown profile answers 404 "Storage profile
#   ... not found."
# - tests/integration/lib/dummy_servers.py has a FakeS3 that can stand in for an
#   S3 bucket to try these examples against.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
PROFILE="${1:-example_s3}"

printf "Testing the storage profile %s...\n" "${PROFILE}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}/storageProfiles/${PROFILE}/operations?operation=test" \
  -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
printf "The bucket can be reached.\n"
