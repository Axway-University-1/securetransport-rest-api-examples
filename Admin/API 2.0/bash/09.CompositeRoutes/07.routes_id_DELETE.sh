#!/bin/bash
# ==============================================================================
# Script Name: 07.routes_id_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-05
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes routes using the `/routes/{id}` endpoint.
# A route is deleted by its id, not its name, so it demonstrates:
# - Looking up the id of a route by name
# - Deleting the composite routes first, and only then the simple routes they
#   run, since a simple route in use cannot be deleted
#
# Usage:
# ./07.routes_id_DELETE.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This cleans up the routes 02 to 05 in this folder create for the account
#   "john". Only ever point it at routes you created.
# - Composite route names are only unique within an account, so a composite
#   route is matched by its account as well as its name.
# - The route templates are left in place. 08.RouteTemplates created them.
# - Requires `jq`, which reads the ids out of the responses.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0"

ACCOUNT="john"

# delete_route TYPE NAME
delete_route() {
    local type="$1" name="$2" id
    id=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/routes?type=${type}&name=${name}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" \
      | jq -r --arg type "${type}" --arg account "${ACCOUNT}" \
        '[(.result // [])[] | select($type == "SIMPLE" or .account == $account)][0].id // empty')

    if [ -z "${id}" ]; then
        printf "There is no %s route '%s'.\n" "${type}" "${name}"
        return
    fi

    printf "Deleting the %s route '%s' (%s)...\n" "${type}" "${name}" "${id}"
    curl -s -o /dev/null -w "HTTP %{http_code}\n" -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/routes/${id}" \
      -H "accept: */*" -H "${REFERER_HEADER}"
}

delete_route COMPOSITE "CompositeRoute_Subscription"
delete_route COMPOSITE "CompositeRoute_WithExtension"
delete_route COMPOSITE "CompositeRoute_WithoutExtension"

delete_route SIMPLE "SimpleRoute_Compress"
delete_route SIMPLE "SimpleRoute_Decompress"
delete_route SIMPLE "SimpleRouteName"
