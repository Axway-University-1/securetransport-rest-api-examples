#!/bin/bash
# ==============================================================================
# Script Name: 07.map_relationships_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Part A, the map and its cost: read every object that the rules need and keep it in state.local.map/. Seven kinds: accounts, applications, certificates, sites, transfer profiles, routes (the full objects: a composite route says which template and which
# subscriptions, and its steps say which simple route they run and with what status; a simple route's steps name sites) and subscriptions (which application, which site and transfer profile in each transfer configuration). Prints the cost: calls, objects, seconds.
#
# Usage:
# ./07.map_relationships_GET.sh [PREFIX]
#
#   PREFIX  read only the objects whose name starts with it (default example_unu_). The server filters (name=PREFIX*), so the cost is that of the demo set.
#           "" is not a prefix: step 10 reads the whole server.
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash (the GET list of accounts, applications, certificates, sites, transferProfiles, routes and subscriptions); every list is read in pages of 100 with limit and offset (use case 06).
# - Nothing is changed. A subscription has no name, so with a prefix it is read for each account (account=NAME, an exact match): one call for each account. Without a prefix one list of all subscriptions is enough.
# - With a prefix, an object that does not match is not read, so a reference from it is not seen: an object of the prefix that something else names would look unused. For a demo set that nothing else names, that is right.
# - fields= keeps the lists small (accounts: the name; certificates: id, name, usage, owner). The routes and the subscriptions are read whole: fields= cannot name "subscriptions" on a route.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./07.map_relationships_GET.sh [PREFIX]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: PREFIX.\n%s\n" "$#" "${USAGE}"; exit 2; fi
if [ "$#" -ge 1 ]; then PREFIX="$1"; else PREFIX="${PREFIX_DEFAULT}"; fi
uc_check_prefix "${PREFIX}" "${USAGE}"
st_session

echo "Reading the objects whose name starts with ${PREFIX}:"
uc_build_map "${PREFIX}" "${MAP_DIR}" || exit 1
printf "%s accounts, %s applications, %s certificates, %s sites, %s transfer profiles, %s routes (%s templates, %s composite, %s simple), %s subscriptions.\n" \
    "$(jq length "${MAP_DIR}/accounts.json")" "$(jq length "${MAP_DIR}/applications.json")" "$(jq length "${MAP_DIR}/certificates.json")" "$(jq length "${MAP_DIR}/sites.json")" \
    "$(jq length "${MAP_DIR}/profiles.json")" "$(jq length "${MAP_DIR}/routes.json")" "$(jq '[.[] | select(.type == "TEMPLATE")] | length' "${MAP_DIR}/routes.json")" \
    "$(jq '[.[] | select(.type == "COMPOSITE")] | length' "${MAP_DIR}/routes.json")" "$(jq '[.[] | select(.type == "SIMPLE")] | length' "${MAP_DIR}/routes.json")" "$(jq length "${MAP_DIR}/subscriptions.json")"
