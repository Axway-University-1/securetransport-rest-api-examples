#!/bin/bash
# ==============================================================================
# Script Name: 09.configurations_logging_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the logging configuration options, using the
# `/configurations/logging` endpoint: the log4j configuration of each part of
# the server (Admin, SSH, FTP, HTTP, AS2, PeSIT, Transaction Manager, ...).
#
# Usage:
# ./09.configurations_logging_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Each logging option belongs to a configuration profile; profileId says which.
#   13.configurations_profiles_GET.sh lists the profiles.
# - Requires `jq`, which prints one option per line.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
printf "Logging options: name, profile, propagation status:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/logging" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '(.result // [])[] | "  \(.name)  \(.profileId)  \(.propagationStatus // "-")"'
