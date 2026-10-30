#!/bin/bash
# ==============================================================================
# Script Name: 06.step_PATCH_disable.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Step 6: disable the step of the composite route example_unu_comp_used that runs example_unu_rt_old. The route ran in step 05 (the server log names it), and from now on it is a route that is disabled and was used in the past. The other disabled
# route, example_unu_rt_never, is disabled and was never used. The steps of a route are addressed by position in a PATCH, so the script reads the route and finds the position of the step first.
#
# Usage:
# ./06.step_PATCH_disable.sh
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/09.CompositeRoutes/10.routes_id_PATCH.sh (a PATCH replace of /steps/N/status). A path into a list takes a position counted from 0, never an id; the position is found in the route just read, not assumed.
# - It reads the route again afterwards and prints the status of each step. Run twice, it changes nothing the second time (the step is disabled already).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./06.step_PATCH_disable.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
st_session

ROUTE_ID=$(uc_id_of routes "${COMP_USED}")
[ -n "${ROUTE_ID}" ] || { echo "The composite route ${COMP_USED} is not on the server. Run 04.routes_POST.sh first."; exit 1; }
OLD_ID=$(uc_id_of routes "${RT_OLD}")
[ -n "${OLD_ID}" ] || { echo "The simple route ${RT_OLD} is not on the server. Run 04.routes_POST.sh first."; exit 1; }

statuses() {    # the position, status and route of each step of the composite route
    uc_get "routes/${ROUTE_ID}"
    [ "${LIST_CODE}" = "200" ] || { echo "GET /routes/${ROUTE_ID}: HTTP ${LIST_CODE}: $(uc_why)"; return 1; }
    printf '%s' "${LIST_BODY}" | jq -r '.steps | to_entries[] | "  step \(.key): \(.value.status)  runs \(.value.executeRouteName)"'
}
echo "The steps of ${COMP_USED} now:"
statuses || exit 1
POSITION=$(printf '%s' "${LIST_BODY}" | jq -r --arg id "${OLD_ID}" '[.steps | to_entries[] | select(.value.executeRoute == $id)][0].key // empty')
[ -n "${POSITION}" ] || { echo "No step of ${COMP_USED} runs ${RT_OLD}."; exit 1; }
CODE=$(uc_patch "routes/${ROUTE_ID}" "$(jq -cn --arg path "/steps/${POSITION}/status" '[{op: "replace", path: $path, value: "DISABLED"}]')")
if [ "${CODE}" != "204" ]; then
    echo "PATCH /routes/${ROUTE_ID} (replace /steps/${POSITION}/status): HTTP ${CODE}. The step was not changed."
    exit 1
fi
echo "PATCH replace /steps/${POSITION}/status DISABLED: HTTP 204. The steps now:"
statuses || exit 1
STATE=$(printf '%s' "${LIST_BODY}" | jq -r --arg id "${OLD_ID}" '[.steps[] | select(.executeRoute == $id)][0].status')
if [ "${STATE}" != "DISABLED" ]; then echo "The step that runs ${RT_OLD} is ${STATE}, not DISABLED."; exit 1; fi
echo "${RT_OLD} is disabled now, and the server log still names it (step 05)."
