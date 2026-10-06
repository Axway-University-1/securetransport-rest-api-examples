#!/bin/bash
# ==============================================================================
# Script Name: 03.sites_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-05
# Location: Sofia
# ==============================================================================
# Description:
# This script retrieves transfer sites using the `/sites` endpoint.
# It demonstrates:
# - A GET request for all the sites of one account
# - A GET request filtered by protocol, printed as one line per site
#
# Usage:
# ./03.sites_GET.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This example uses the account "john". 02.sites_POST_ssh.sh creates two SSH
#   sites for it.
# - Requires `jq`, which prints the short listing.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

ACCOUNT="john"

printf "Get all the sites of the account '%s'...\n" "${ACCOUNT}"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/sites?account=${ACCOUNT}" \
  -H "accept: application/json" -H "${REFERER_HEADER}"

printf "\n\nGet only its SSH sites, one line each: id, name, host:port, folder...\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/sites?account=${ACCOUNT}&protocol=ssh" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '(.result // [])[] | "\(.id)  \(.name)  \(.host):\(.port)  \(.downloadFolder // .uploadFolder // "")"'
