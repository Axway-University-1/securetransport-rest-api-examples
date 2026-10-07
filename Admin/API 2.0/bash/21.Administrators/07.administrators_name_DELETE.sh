#!/bin/bash
# ==============================================================================
# Script Name: 07.administrators_name_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes an administrator, using the `/administrators/{name}`
# endpoint.
#
# Usage:
# ./07.administrators_name_DELETE.sh
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It deletes example_admin, which 02.administrators_POST.sh creates. Only ever
#   point it at an administrator you created.
# - Its API keys go with it.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrators"
ADMIN="example_admin"

printf "Deleting the administrator %s...\n" "${ADMIN}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${ADMIN}" \
  -H "accept: */*" -H "${REFERER_HEADER}")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "204" ]
