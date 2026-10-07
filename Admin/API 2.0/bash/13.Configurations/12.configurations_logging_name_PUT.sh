#!/bin/bash
# ==============================================================================
# Script Name: 12.configurations_logging_name_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script replaces a logging configuration option, using the
# `/configurations/logging/{name}` endpoint with PUT: it uploads a log4j XML
# file as a multipart form.
#
# Usage:
# ./12.configurations_logging_name_PUT.sh XML_FILE [NAME [PROFILE_ID]]
#
#   XML_FILE    the log4j configuration to upload
#   NAME        the option (default Logging.Admin.config)
#   PROFILE_ID  its profile (default: the one 09.configurations_logging_GET.sh
#               lists it with)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Each logging option belongs to a configuration profile; profileId says which, and is required.
# - Keep the XML 11.configurations_logging_name_GET.sh saved, to put back.
# - Confirmed directly: on a server where the option was never set, a PUT
#   answers 400 "Option ... is not eligible for propagation because its
#   initial configuration is not fetched yet." and nothing changes.
# - Changes the server's logging: try it on a test server first.
# - Requires `jq`, which looks the profile up.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
XML_FILE="$1"
NAME="${2:-Logging.Admin.config}"
PROFILE_ID="$3"
if [ ! -f "${XML_FILE}" ]; then
    printf "Usage: ./12.configurations_logging_name_PUT.sh XML_FILE [NAME [PROFILE_ID]]\n"
    exit 2
fi
# The profile of the option, when none is given
if [ -z "${PROFILE_ID}" ]; then
    PROFILE_ID=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/logging" -H "accept: application/json" \
      -H "${REFERER_HEADER}" | jq -r --arg name "${NAME}" '[(.result // [])[] | select(.name == $name)][0].profileId // empty')
    [ -n "${PROFILE_ID}" ] || { printf "There is no logging option %s.\n" "${NAME}"; exit 1; }
fi

printf "Uploading %s as %s, profile %s...\n" "${XML_FILE}" "${NAME}" "${PROFILE_ID}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/logging/${NAME}?profileId=${PROFILE_ID}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -F "file=@${XML_FILE};type=application/xml" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
case "${HTTP_CODE}" in
    200|204) ;;
    *) printf '%s\n' "${RESPONSE%$'\n'*}"; exit 1 ;;
esac
