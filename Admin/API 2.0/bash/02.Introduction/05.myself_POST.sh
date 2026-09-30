#!/bin/bash
# ==============================================================================
# Script Name: 05.myself_POST.sh
# Author: Plamen Milenkov
# Created: 2025-08-05
# Location: Sofia
# ==============================================================================
# Description:
# This script performs a POST request to the `/myself` endpoint, which is related
# to user authentication. It initiates a session or validates credentials depending
# on the API implementation.
#
# Usage:
# ./05.myself_POST.sh
#
# Notes:
# - For complete documentation, refer to folder 01.Authentication.
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/myself" -H "accept: application/json" -H "${REFERER_HEADER}"
