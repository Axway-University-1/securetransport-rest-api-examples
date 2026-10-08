#!/bin/bash
# ==============================================================================
# Script Name: 03.zones_name_HEAD.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script checks that a zone exists using the `/zones/{name}` endpoint.
# It demonstrates:
# - A HEAD call, which answers with the status only: 200 it exists, 404 it does not
#
# Usage:
# ./03.zones_name_HEAD.sh [NAME]
#
#   NAME  the zone (default example_zone, which 02 creates)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: 200 for `Private` and for a zone of ours, 404 with no body for a zone that does not exist or whose name differs only in
#   case. A name with a space is URL-encoded by this script and found.
# - Requires `jq`, which URL-encodes the name.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/zones"
NAME="${1:-example_zone}"
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" --head "${MAIN_URL}/${ENCODED}" \
  -H "accept: */*" -H "${REFERER_HEADER}")
if [ "${HTTP_CODE}" = "200" ]; then
    printf "The zone %s exists.\n" "${NAME}"
else
    printf "The zone %s does not exist (HTTP %s).\n" "${NAME}" "${HTTP_CODE}"
    exit 1
fi
