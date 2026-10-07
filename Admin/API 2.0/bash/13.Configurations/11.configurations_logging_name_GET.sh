#!/bin/bash
# ==============================================================================
# Script Name: 11.configurations_logging_name_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads a logging configuration option, using the
# `/configurations/logging/{name}` endpoint: as JSON, its profile and status;
# as XML, the log4j configuration itself, saved to a file.
#
# Usage:
# ./11.configurations_logging_name_GET.sh [NAME [PROFILE_ID]]
#
#   NAME        the option (default Logging.Admin.config)
#   PROFILE_ID  its profile (default: the one 09.configurations_logging_GET.sh
#               lists it with)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Each logging option belongs to a configuration profile; profileId says which, and is required.
# - The XML is written to NAME.xml, in the current folder.
# - Confirmed directly: the JSON never holds the XML; ask for it with
#   "accept: application/xml". An option with no XML set answers 204, and the
#   server then uses its own default configuration.
# - Requires `jq`, which looks the profile up.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
NAME="${1:-Logging.Admin.config}"
PROFILE_ID="$2"
# The profile of the option, when none is given
if [ -z "${PROFILE_ID}" ]; then
    PROFILE_ID=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/logging" -H "accept: application/json" \
      -H "${REFERER_HEADER}" | jq -r --arg name "${NAME}" '[(.result // [])[] | select(.name == $name)][0].profileId // empty')
    [ -n "${PROFILE_ID}" ] || { printf "There is no logging option %s.\n" "${NAME}"; exit 1; }
fi
OUTPUT="${NAME}.xml"

curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/logging/${NAME}?profileId=${PROFILE_ID}" \
  -H "accept: application/json" -H "${REFERER_HEADER}"

printf "\n\nIts XML: "
HTTP_CODE=$(curl -s -o "${OUTPUT}" -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X GET \
  "${MAIN_URL}/logging/${NAME}?profileId=${PROFILE_ID}" -H "accept: application/xml" -H "${REFERER_HEADER}")
case "${HTTP_CODE}" in
    200) printf "written to %s, %s bytes.\n" "${OUTPUT}" "$(wc -c < "${OUTPUT}" | tr -d ' ')" ;;
    204) rm -f "${OUTPUT}"; printf "none set (HTTP 204): the server uses its default.\n" ;;
    *) printf "HTTP %s\n" "${HTTP_CODE}"; cat "${OUTPUT}"; rm -f "${OUTPUT}"; exit 1 ;;
esac
