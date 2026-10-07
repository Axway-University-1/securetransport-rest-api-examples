#!/bin/bash
# ==============================================================================
# Script Name: 07.configurations_options_groups_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the groups of Server Configuration Options, using the
# `/configurations/options/groups` endpoint: sets of related options the
# Admin UI shows together, like the SMTP or the S3 storage profile settings.
#
# Usage:
# ./07.configurations_options_groups_GET.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: the answer is a plain array, not {result: [...]}.
# - 08.configurations_options_groups_name_GET.sh reads one group.
# - Requires `jq`, which prints one group per line.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
printf "The option groups:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/options/groups" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '.[] | "  \(.name): \(.description)"'
