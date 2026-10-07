#!/bin/bash
# ==============================================================================
# Script Name: 10.configurations_logging_name_HEAD.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script checks whether a logging configuration option exists, using the
# `/configurations/logging/{name}` endpoint with HEAD: 200 when it does, 404
# when it does not.
#
# Usage:
# ./10.configurations_logging_name_HEAD.sh [NAME [PROFILE_ID]]
#
#   NAME        the option (default Logging.Admin.config)
#   PROFILE_ID  its profile (default: the one 09.configurations_logging_GET.sh
#               lists it with)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Each logging option belongs to a configuration profile; profileId says which, and is required.
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

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" --head \
  "${MAIN_URL}/logging/${NAME}?profileId=${PROFILE_ID}" -H "accept: */*" -H "${REFERER_HEADER}")
if [ "${HTTP_CODE}" = "200" ]; then
    printf "The logging option %s exists in profile %s.\n" "${NAME}" "${PROFILE_ID}"
else
    printf "The logging option %s does not exist in profile %s (HTTP %s).\n" "${NAME}" "${PROFILE_ID}" "${HTTP_CODE}"
    exit 1
fi
