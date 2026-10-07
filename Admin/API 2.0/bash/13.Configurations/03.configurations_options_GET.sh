#!/bin/bash
# ==============================================================================
# Script Name: 03.configurations_options_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the Server Configuration Options using the
# `/configurations/options` endpoint. It demonstrates:
# - Counting them
# - Searching by name, with the * wildcard
# - The ones changed from their default (isModified=true)
# - Asking for some fields only, with fields=
#
# Usage:
# ./03.configurations_options_GET.sh [PATTERN]
#
#   PATTERN  an option name, * matches anything (default AddressBook*)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - values is always a list, even for an option with one value; defaultValues
#   is the value it has when nothing is set.
# - values= searches by value, also with *.
# - Requires `jq`, which prints one option per line.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
PATTERN="${1:-AddressBook*}"

printf "Server Configuration Options: "
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/options?limit=1&fields=name" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '.resultSet.totalCount'

printf "\nThe options named %s: name = values (default):\n" "${PATTERN}"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}/options" --data-urlencode "name=${PATTERN}" \
  --data-urlencode "fields=name,values,defaultValues" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '(.result // [])[] | "  \(.name) = \(.values | join(", ")) (\(.defaultValues | join(", ")))"'

printf "\nThe first 10 options changed from their default:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/options?isModified=true&limit=10&fields=name,values" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '(.result // [])[] | "  \(.name) = \(.values | join(", "))"'
