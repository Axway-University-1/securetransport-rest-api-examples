#!/bin/bash
# ==============================================================================
# Script Name: 10.whole_server_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# The same on the whole server, read only: the map (every list, not filtered by a prefix), the server log search for the routes that only disabled steps run, and the unused objects grouped by type. It prints the cost, so that it can be set
# beside the cost of the demo set (step 07): the number of calls grows with the number of objects, in pages of 100, and the log search costs one call for each route that is disabled everywhere. It changes nothing on the server and deletes nothing.
#
# Usage:
# ./10.whole_server_GET.sh
#
# Risk: read
#
# Notes:
# - Copied from steps 07, 08 and 09 of this use case. The files go to state.local.mapall/.
# - On a server with many objects it takes minutes, not seconds: every list is read in pages of 100, certificates included (a few hundred trusted CA certificates are read to find the few that have an owner). Run it when the server is quiet.
# - What it reports is a list of candidates. Read "What to check before you delete" in the README before you delete anything.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./10.whole_server_GET.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
st_session

echo "This is read only: it changes and deletes nothing. It reads every list of the server in pages of 100."
START=$(date +%s)
echo "The map of the whole server:"
uc_build_map "" "${MAP_ALL_DIR}" || exit 1
echo "The routes that only disabled steps run, searched in the server log by id:"
uc_log_search "${MAP_ALL_DIR}" || exit 1
echo
uc_print_unused "${MAP_ALL_DIR}" || exit 1
echo
printf "The whole server took %s s.\n" "$(( $(date +%s) - START ))"
