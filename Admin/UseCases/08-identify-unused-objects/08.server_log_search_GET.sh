#!/bin/bash
# ==============================================================================
# Script Name: 08.server_log_search_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Part A, the routes that are disabled now: a simple route that is run only by DISABLED steps may be a route that nobody ever used, or a route that ran in the past and was disabled later. The configuration cannot tell. The server log can: for each such route
# the script searches the log for the route's id (one call for each route: that is the cost of the question) and writes what it found to state.local.map/logsearch.tsv. Needs step 07.
#
# Usage:
# ./08.server_log_search_GET.sh [PREFIX]
#
#   PREFIX  the prefix that step 07 was run with (default example_unu_)
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/28.ServerLogs/01.logs_server_GET.sh (the message filter). The search is by ID: the log names a composite route by name, and a simple route only by id (see 05). A search by the name would find the creation of the route and
#   the administrator's own requests, and tell nothing about its use.
# - The log records every request that the administrator makes, and the request holds the text that was asked for, so every search finds itself. An entry that holds "/api/v2.0/" is the request, not the route, and is not counted. (Without that, a route that never ran
#   would be "found" by the search for it.)
# - The search sees only the log the server has kept: a route last used before the oldest entry looks unused.
# - A route with no ENABLED step and not named in the log is reported as unused by step 09. A route that is run by an enabled step is not searched: it is used.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./08.server_log_search_GET.sh [PREFIX]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: PREFIX.\n%s\n" "$#" "${USAGE}"; exit 2; fi
if [ "$#" -ge 1 ]; then PREFIX="$1"; else PREFIX="${PREFIX_DEFAULT}"; fi
uc_check_prefix "${PREFIX}" "${USAGE}"
if [ ! -s "${MAP_DIR}/routes.json" ] || [ "$(cat "${MAP_DIR}/prefix" 2>/dev/null)" != "${PREFIX}" ]; then
    echo "There is no map for the prefix ${PREFIX}. Run 07.map_relationships_GET.sh ${PREFIX} first."
    exit 1
fi
st_session

echo "The routes that only disabled steps run, searched in the server log by id:"
uc_log_search "${MAP_DIR}" || exit 1
if [ ! -s "${MAP_DIR}/logsearch.tsv" ]; then echo "  There is none: every route that a step runs is run by an enabled step, or no step runs it."; fi
