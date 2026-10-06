#!/bin/bash
# ==============================================================================
# Script Name: 03.addressBook_sources_id_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads one address book source, using the
# `/addressBook/sources/{id}` endpoint: its type, group, whether it is enabled,
# and its custom properties - for LDAP, the domain and the page size.
#
# Usage:
# ./03.addressBook_sources_id_GET.sh [SOURCE]
#
#   SOURCE  the source's name (default LDAP). Its id is looked up by name.
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
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

printf "The source %s:\n" "${SOURCE}"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${SOURCE_ID}" -H "accept: application/json" -H "${REFERER_HEADER}"

printf "\n\nOnly its custom properties:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${SOURCE_ID}?fields=customProperties" \
  -H "accept: application/json" -H "${REFERER_HEADER}"
printf "\n"
