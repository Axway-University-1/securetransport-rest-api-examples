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
# - Printing the HTTP code of each delete, and exiting 1 when the server refuses one
#
# Usage:
# ./07.routes_id_DELETE.sh
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This cleans up the routes 02 to 05 in this folder create for the account
#   "john". Only ever point it at routes you created.
# - Composite route names are only unique within an account, so a composite
#   route is matched by its account as well as its name.
# - The route templates are left in place. 08.RouteTemplates created them, and 08.RouteTemplates/03.routes_DELETE_all.sh removes them.
# - The name filter ignores case and takes a * wildcard, so the exact name is picked out of what comes back. Two simple routes may share a
#   name, so a name that matches more than one route (for a composite route: more than one of the account) is NOT deleted, and the exit code is 1.
# - A route the server refuses to delete (a simple route that another route still runs, for one: 400 "Route is in use.") makes the exit
#   code 1, and the next ones are still tried.
# - Requires `jq`, which reads the ids out of the responses.
# - Confirmed directly: a delete is 204 with no body; an id that is not there is a JSON 404, "Route is not found.". Two simple routes may share a
#   name (03.routes_POST_simple_compress.sh run twice makes two, each 201), so a name that matches two is refused here, with exit 1: remove one by its id.
# - Exit codes: 0 when every route was deleted or was not there, 1 when the server refuses a lookup or a delete, or a name is ambiguous.
#   It takes no argument.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0"

if [ "$#" -ne 0 ]; then
    printf "Usage: ./07.routes_id_DELETE.sh\n"
    exit 2
fi

ACCOUNT="${ST_EXAMPLE_ACCOUNT:-john}"
FAILED=0

# The answer to a refused call: the server's own messages, or the text as it is
show_error() { printf '%s' "$1" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "$1"; }

# delete_route TYPE NAME
delete_route() {
    local type="$1" name="$2" ids count id
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}/routes" \
      --data-urlencode "type=${type}" --data-urlencode "name=${name}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "Could not look up the %s route '%s': HTTP %s\n" "${type}" "${name}" "${HTTP_CODE}"
        show_error "${RESPONSE}"
        FAILED=1
        return
    fi
    ids=$(printf '%s' "${RESPONSE}" | jq -r --arg type "${type}" --arg account "${ACCOUNT}" --arg name "${name}" \
      '(.result // [])[] | select(.name == $name and ($type == "SIMPLE" or .account == $account)) | .id')
    count=$(printf '%s' "${ids}" | grep -c .)

    if [ "${count}" -eq 0 ]; then
        printf "There is no %s route '%s'.\n" "${type}" "${name}"
        return
    fi
    if [ "${count}" -gt 1 ]; then
        printf "There are %s %s routes named '%s'; none deleted.\n" "${count}" "${type}" "${name}"
        FAILED=1
        return
    fi

    id="${ids}"
    printf "Deleting the %s route '%s' (%s)...\n" "${type}" "${name}" "${id}"
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/routes/$(jq -rn --arg n "${id}" '$n|@uri')" \
      -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    printf "HTTP %s\n" "${HTTP_CODE}"
    if [ "${HTTP_CODE}" != "204" ]; then
        show_error "${RESPONSE}"
        FAILED=1
        return
    fi
    printf "Deleted the %s route '%s'.\n" "${type}" "${name}"
}

delete_route COMPOSITE "CompositeRoute_Subscription"
delete_route COMPOSITE "CompositeRoute_WithExtension"
delete_route COMPOSITE "CompositeRoute_WithoutExtension"

delete_route SIMPLE "SimpleRoute_Compress"
delete_route SIMPLE "SimpleRoute_Decompress"
delete_route SIMPLE "SimpleRouteName"
exit "${FAILED}"
