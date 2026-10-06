#!/bin/bash
# ==============================================================================
# Script Name: 01.addressBook_sources_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the address book sources using the `/addressBook/sources`
# endpoint: where the end users' address book finds the people they share
# with - the local accounts, an LDAP directory, or a custom source. It
# demonstrates:
# - Listing every source
# - Filtering by type and by whether a source is enabled
# - Asking for some fields only, with fields=
#
# Usage:
# ./01.addressBook_sources_GET.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - type is LOCAL, LDAP or CUSTOM. name and parentGroup filter too.
# - A server comes with its sources; the API has no POST or DELETE for them,
#   only reading and changing (see 04 and 05 in this folder).
# - Requires `jq`, which prints one source per line.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/addressBook/sources"

printf "Every address book source:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}" -H "accept: application/json" -H "${REFERER_HEADER}"

printf "\n\nThe LDAP sources only:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?type=LDAP" -H "accept: application/json" -H "${REFERER_HEADER}"

printf "\n\nThe enabled ones, one line each: id, type, name, group:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?enabled=true&fields=id,type,name,parentGroup" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '(.result // [])[] | "  \(.id)  \(.type)  \(.name)  \(.parentGroup)"'
