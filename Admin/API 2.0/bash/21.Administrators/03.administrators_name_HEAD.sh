#!/bin/bash
# ==============================================================================
# Script Name: 03.administrators_name_HEAD.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script checks whether an administrator exists, using the
# `/administrators/{name}` endpoint with HEAD: 200 when it does, 404 when it
# does not.
#
# Usage:
# ./03.administrators_name_HEAD.sh [ADMIN]
#
#   ADMIN  the login name (default example_admin)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
# - Requires `jq`, which URL-encodes the login name.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${ST_ADMIN_LOCAL_VARIABLES:-${SCRIPT_DIR}/../set_variables.local.sh}" ||
    { echo "Copy set_variables.local.example.sh to set_variables.local.sh and fill it in."; exit 1; }

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/administrators"
ADMIN="${1:-example_admin}"
ENCODED=$(jq -rn --arg name "${ADMIN}" '$name | @uri')

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" --head "${MAIN_URL}/${ENCODED}" \
  -H "accept: */*" -H "${REFERER_HEADER}")
if [ "${HTTP_CODE}" = "200" ]; then
    printf "The administrator %s exists.\n" "${ADMIN}"
else
    printf "The administrator %s does not exist (HTTP %s).\n" "${ADMIN}" "${HTTP_CODE}"
    exit 1
fi
