#!/bin/bash
# ==============================================================================
# Script Name: 15.configurations_profiles_id_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads a configuration profile, using the
# `/configurations/profiles/{id}` endpoint.
#
# Usage:
# ./15.configurations_profiles_id_GET.sh [PROFILE_ID]
#
#   PROFILE_ID  the profile (default: the SecureTransport Server Configuration
#               profile)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A profile's id is a number, and may be negative.
# - Requires `jq`, which looks the id up.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
PROFILE_ID="$1"
if [ -z "${PROFILE_ID}" ]; then
    PROFILE_ID=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/profiles" -H "accept: application/json" \
      -H "${REFERER_HEADER}" | jq -r '[(.result // [])[] | select(.name == "SecureTransport Server Configuration")][0].id // empty')
    [ -n "${PROFILE_ID}" ] || { printf "Give the profile's id: 13.configurations_profiles_GET.sh lists them.\n"; exit 1; }
fi

curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/profiles/${PROFILE_ID}" -H "accept: application/json" -H "${REFERER_HEADER}"
printf "\n"
