#!/bin/bash
# ==============================================================================
# Script Name: 13.configurations_profiles_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the configuration profiles, using the
# `/configurations/profiles` endpoint: the server's own configuration and the
# default configuration of each protocol.
#
# Usage:
# ./13.configurations_profiles_GET.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - node is the server or edge the profile applies to; protocol is null for the
#   server's own profile.
# - Requires `jq`, which prints one profile per line.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
printf "Configuration profiles: id, name, protocol, active:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/profiles" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '(.result // [])[] | "  \(.id)  \(.name)  \(.protocol // "-")  \(.active // "-")"'
