#!/bin/bash
# ==============================================================================
# Script Name: 06.patch_list.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Changing an object, step 6: a LIST. The steps of the route are a list, and a path into a list ends in a POSITION, counted from 0, never in an id. PATCH add at the end (the path ends in -), add at a position
# (the item goes there and the ones after it move down), replace one item or one field of an item, remove an item by position, replace the whole list. Then the mistakes: a position past the end, an id in the path, a text where a list
# belongs, and a remove with "-". Each case shows the body sent, the answer and the list of file filters before and after.
#
# Usage:
# ./06.patch_list.sh [NAME]
#
#   NAME  the account (and NAME_route, the route) to change; it must start with example_ (default example_chg)
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/09.CompositeRoutes/10.routes_id_PATCH.sh (the position is found by reading the route), with more operations.
# - The value of `add` or `replace` on an item is a whole item (here a route step as an object). The value of `replace` on the list itself is the whole list: what you send is what is left.
# - The position of the step you want is found in the route just read (with jq), not assumed: steps are added and moved.
# - `remove` on "-" answers 204 and removes nothing. A position past the end (add /steps/9) is refused (400 "Array index 9 out of bounds"). An id in the path is refused (400 "Can't reference field ... on array").
# - Exit 1 when a case does not come out as the README documents (the line NOT AS DOCUMENTED says which).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./06.patch_list.sh [NAME]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: NAME.\n%s\n" "$#" "${USAGE}"; exit 2; fi
NAME="${1:-${DEFAULT_NAME}}"
uc_check_name "${NAME}" "${USAGE}"
st_session
uc_init "${NAME}"
uc_need route
LIST='[.steps[].fileFilterExpression]'
STEP_ID=$(curl -k -s -b "${JAR}" -X GET "${ROUTE_URL}" -H "accept: application/json" -H "Referer: ${REFERER}" | jq -r '.steps[0].id // empty')
echo "The list before: $(uc_value "${ROUTE_URL}" "${LIST}"). Positions are 0 and 1."

uc_case "add at the end: the path ends in -" "${ROUTE_URL}" "${LIST}" 204 '["*.one","*.two","*.three"]' \
    "$(jq -cn --argjson step "$(uc_step '*.three')" '[{op: "add", path: "/steps/-", value: $step}]')"
uc_case "add at a position: the item goes to 0, the others move down" "${ROUTE_URL}" "${LIST}" 204 '["*.zero","*.one","*.two","*.three"]' \
    "$(jq -cn --argjson step "$(uc_step '*.zero')" '[{op: "add", path: "/steps/0", value: $step}]')"
uc_case "replace one field of the item at position 1" "${ROUTE_URL}" "${LIST}" 204 '["*.zero","*.uno","*.two","*.three"]' \
    '[{"op":"replace","path":"/steps/1/fileFilterExpression","value":"*.uno"}]'
uc_case "replace the whole item at position 0" "${ROUTE_URL}" "${LIST}" 204 '["*.first","*.uno","*.two","*.three"]' \
    "$(jq -cn --argjson step "$(uc_step '*.first')" '[{op: "replace", path: "/steps/0", value: $step}]')"
uc_case "remove the item at position 0: the others move up" "${ROUTE_URL}" "${LIST}" 204 '["*.uno","*.two","*.three"]' \
    '[{"op":"remove","path":"/steps/0"}]'
POSITION=$(uc_value "${ROUTE_URL}" "${LIST} | index(\"*.two\")")
echo
echo "The step with the filter *.two is at position ${POSITION}: found in the route just read, with jq."
uc_case "remove the step found by its content, at that position" "${ROUTE_URL}" "${LIST}" 204 '["*.uno","*.three"]' \
    "$(jq -cn --arg path "/steps/${POSITION}" '[{op: "remove", path: $path}]')"
uc_case "a position past the end is refused" "${ROUTE_URL}" "${LIST}" 400 '["*.uno","*.three"]' \
    "$(jq -cn --argjson step "$(uc_step '*.nine')" '[{op: "add", path: "/steps/9", value: $step}]')"
uc_case "the id of an item in the path is refused: a path takes a position" "${ROUTE_URL}" "${LIST}" 400 '["*.uno","*.three"]' \
    "$(jq -cn --arg path "/steps/${STEP_ID}/status" '[{op: "replace", path: $path, value: "DISABLED"}]')"
uc_case "a text where the list belongs is refused" "${ROUTE_URL}" "${LIST}" 400 '["*.uno","*.three"]' \
    '[{"op":"replace","path":"/steps","value":"x"}]'
uc_case "remove with - answers 204 and removes nothing" "${ROUTE_URL}" "${LIST}" 204 '["*.uno","*.three"]' \
    '[{"op":"remove","path":"/steps/-"}]'
uc_case "replace the whole list with an empty one: every step is gone" "${ROUTE_URL}" "${LIST}" 204 '[]' \
    '[{"op":"replace","path":"/steps","value":[]}]'
uc_case "replace the whole list with two steps: the list is what you send" "${ROUTE_URL}" "${LIST}" 204 '["*.one","*.two"]' \
    "$(jq -cn --argjson one "$(uc_step '*.one')" --argjson two "$(uc_step '*.two')" '[{op: "replace", path: "/steps", value: [$one, $two]}]')"
uc_done
