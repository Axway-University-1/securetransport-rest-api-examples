#!/bin/bash
# ==============================================================================
# Script Name: 02.addressBook_sources_id_HEAD.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script checks whether an address book source exists, using the
# `/addressBook/sources/{id}` endpoint with HEAD: 200 when it does, 404 when it
# does not.
#
# Usage:
# ./02.addressBook_sources_id_HEAD.sh [SOURCE]
#
#   SOURCE  the source's name (default LDAP). Its id is looked up by name.
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A source is addressed by its id, not its name.
# - Requires `jq`, which reads the id.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/addressBook/sources"

SOURCE="${1:-LDAP}"
SOURCE_ID=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" \
  --data-urlencode "name=${SOURCE}" --data-urlencode "fields=id" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.result[0].id // empty')
if [ -z "${SOURCE_ID}" ]; then
    printf "There is no address book source named %s.\n" "${SOURCE}"
    exit 1
fi

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" --head "${MAIN_URL}/${SOURCE_ID}" \
  -H "accept: */*" -H "${REFERER_HEADER}")
if [ "${HTTP_CODE}" = "200" ]; then
    printf "The source %s exists, id %s.\n" "${SOURCE}" "${SOURCE_ID}"
else
    printf "The source %s does not exist (HTTP %s).\n" "${SOURCE}" "${HTTP_CODE}"
    exit 1
fi
