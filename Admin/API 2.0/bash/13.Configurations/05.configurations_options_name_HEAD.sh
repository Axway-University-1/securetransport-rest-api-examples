#!/bin/bash
# ==============================================================================
# Script Name: 05.configurations_options_name_HEAD.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script checks whether a Server Configuration Option exists, using the
# `/configurations/options/{name}` endpoint with HEAD: 200 when it does, 404
# when it does not.
#
# Usage:
# ./05.configurations_options_name_HEAD.sh [NAME]
#
#   NAME  the option (default AddressBook.Enabled)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
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

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" --head "${MAIN_URL}/options/${NAME}" \
  -H "accept: */*" -H "${REFERER_HEADER}")
if [ "${HTTP_CODE}" = "200" ]; then
    printf "The option %s exists.\n" "${NAME}"
else
    printf "The option %s does not exist (HTTP %s).\n" "${NAME}" "${HTTP_CODE}"
    exit 1
fi
