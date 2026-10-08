#!/bin/bash
# ==============================================================================
# Script Name: 01.businessUnits_POST.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script creates a business unit using the `/businessUnits` endpoint.
#
# Usage:
# ./01.businessUnits_POST.sh [NAME [BASE_FOLDER]]
#
#   NAME         the business unit (default Finance)
#   BASE_FOLDER  its base folder, an absolute path (default /home/fin)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The baseFolder is the root under which the accounts of this business unit
#   are created.
# - Finance and /home/fin are the defaults, and 03 to 07 in this folder act on Finance too. A unit that
#   exists is never changed: the server refuses a name or a base folder that is in use (see below) and the
#   script exits 1. 07.businessUnits_name_DELETE.sh NAME removes the unit again.
# - Requires `jq`, which builds the request body.
# - Confirmed directly: a success is 201 with no body and the unit's address in `Location`. A name that exists
#   is 400 (not 409) "Business unit name already exists. Business unit base folder is already in use or it is
#   not valid.", a base folder that is not absolute 400 "Base folder is not valid: Folder name is not absolute:
#   home/x", an empty name 400 "name cannot be empty", no baseFolder 400 "baseFolder must not be null". A name
#   with a space is accepted (and needs encoding in a path: the other scripts of this folder do that).
# - Exit codes: 0 when the unit was created (201), 1 when the server refuses, 2 when an argument is wrong
#   (nothing is sent).
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

#
# First we will load the variables into our context.
# Put your own values in set_variables.local.sh, which set_variables.sh
# loads and which git ignores.
#
source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
USAGE="Usage: ./01.businessUnits_POST.sh [NAME [BASE_FOLDER]]"
NAME="${1:-Finance}"
BASE_FOLDER="${2:-/home/fin}"
HEADERS_FILE=$(mktemp)
trap 'rm -f "${HEADERS_FILE}"' EXIT

if [ "$#" -gt 2 ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
if [ -z "${NAME// /}" ]; then
    printf "NAME must not be empty.\n%s\n" "${USAGE}"
    exit 2
fi
if [[ "${BASE_FOLDER}" != /* ]]; then
    printf "BASE_FOLDER must be an absolute path, starting with /, not %s.\n%s\n" "${BASE_FOLDER}" "${USAGE}"
    exit 2
fi

BODY=$(jq -cn --arg name "${NAME}" --arg folder "${BASE_FOLDER}" '{name: $name, baseFolder: $folder}')

# Create a Business Unit
printf "Creating the business unit %s, base folder %s...\n" "${NAME}" "${BASE_FOLDER}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/businessUnits" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -D "${HEADERS_FILE}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "201" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
printf "It is at %s\n" "$(sed -n 's/^[Ll]ocation: *//p' "${HEADERS_FILE}" | tr -d '\r')"
