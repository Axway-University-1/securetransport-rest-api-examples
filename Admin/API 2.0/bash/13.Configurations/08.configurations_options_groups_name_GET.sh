#!/bin/bash
# ==============================================================================
# Script Name: 08.configurations_options_groups_name_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads one group of Server Configuration Options, using the
# `/configurations/options/groups/{name}` endpoint: the UI schema of its
# options, with each option's title and type.
#
# Usage:
# ./08.configurations_options_groups_name_GET.sh [GROUP]
#
#   GROUP  the group (default StorageProfiles.S3.Group)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: some groups the list returns answer 501 "Group with
#   name ... not implemented" here, for example SMTP.Group.
# - Requires `jq`, which prints the options.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
GROUP="${1:-StorageProfiles.S3.Group}"

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/options/groups/${GROUP}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the group %s (HTTP %s):\n%s\n" "${GROUP}" "${HTTP_CODE}" "${RESPONSE}"
    exit 1
fi
printf '%s' "${RESPONSE}" | jq -r '.uiSchema | "\(.title): \(.description)", (.properties // {} | to_entries[] | "  \(.key)  \(.value.type // "-")  \(.value.title // "")")'
