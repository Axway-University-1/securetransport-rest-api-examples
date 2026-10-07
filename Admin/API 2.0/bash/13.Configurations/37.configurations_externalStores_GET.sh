#!/bin/bash
# ==============================================================================
# Script Name: 37.configurations_externalStores_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the external stores, using the
# `/configurations/externalStores` endpoint: the secret vaults (HashiCorp Vault,
# Azure Key Vault, ...) the server fetches passwords and keys from at run time.
#
# Usage:
# ./37.configurations_externalStores_GET.sh [NAME]
#
#   NAME  list only the store with this exact name
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: a name pattern ending in *, such as example*, answers
#   404 "External Stores configuration is not valid" as soon as it matches a
#   store: the pattern is matched against the server options that hold the
#   stores, and also matches each store's companion option
#   TM.ExternalStores.<name>.encryptedFields. Use an exact name, or none.
# - Confirmed directly: fields= is ignored; every field comes back.
# - Requires `jq`, which prints one store per line.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
NAME="$1"
FILTER=()
[ -n "${NAME}" ] && FILTER=(--data-urlencode "name=${NAME}")
printf "External stores: name, address, cache timeout:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}/externalStores" "${FILTER[@]}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '(.result // [])[] | "  \(.name)  \(.baseUrl)\(.uri)  \(.cacheTimeout)s"'
