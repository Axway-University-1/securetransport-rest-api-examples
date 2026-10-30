#!/bin/bash
# ==============================================================================
# Script Name: 10.put_fragment.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Changing an object, step 10: what a PUT with only some of the fields does. It resets every field it leaves out: here the two steps of the route are gone, with the answer 204 and no warning. Then the way back: the
# saved copy cannot be PUT (its step ids no longer exist), so the steps are put back with a PATCH that replaces the list.
#
# Usage:
# ./10.put_fragment.sh [NAME]
#
#   NAME  the account (and NAME_route, the route) to change; it must start with example_ (default example_chg)
#
# Risk: write
#
# Notes:
# - Written for this use case. The fragment is name, type, conditionType and description: the minimum that looks like a route. Every field left out is reset (the same happens to accounts, subscriptions and sites: not tried here for them).
# - The way back is the copy kept by 02 (or read at the start of this step if 02 was not run): PUT of it is 404 "Some Route steps are not found" (the ids are gone), PATCH replace of /steps with the steps minus their ids works.
# - Exit 1 when a case does not come out as the README documents (the line NOT AS DOCUMENTED says which).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./10.put_fragment.sh [NAME]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: NAME.\n%s\n" "$#" "${USAGE}"; exit 2; fi
NAME="${1:-${DEFAULT_NAME}}"
uc_check_name "${NAME}" "${USAGE}"
st_session
uc_init "${NAME}"
uc_need route

read_route() { curl -k -s -b "${JAR}" -X GET "${ROUTE_URL}" -H "accept: application/json" -H "Referer: ${REFERER}"; }
put_route() {
    local result code
    printf '\n--- %s\n' "$1"
    printf '  body:    %s\n' "$(printf '%s' "$3" | cut -c1-200)$([ "${#3}" -gt 200 ] && echo " ... (${#3} characters)")"
    result=$(curl -k -s -w "\n%{http_code}" -b "${JAR}" -X PUT "${ROUTE_URL}" -H "accept: application/json" -H "Referer: ${REFERER}" \
             -H "Content-Type: application/json" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)" --data-binary "$3")
    PUT_CODE="${result##*$'\n'}"
    printf '  answer:  HTTP %s\n' "${PUT_CODE}"
    [ -z "${result%$'\n'*}" ] || printf '%s\n' "$(printf '%s' "${result%$'\n'*}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s' "${result%$'\n'*}")" | sed 's/^/           /'
    if [ "${PUT_CODE}" != "$2" ]; then
        printf '  NOT AS DOCUMENTED: this use case expects HTTP %s. The server answered HTTP %s.\n' "$2" "${PUT_CODE}"
        UC_FAILED=1
    fi
}

SAVED=$(read_route)
LIST='[.steps[].fileFilterExpression]'
echo "Read and kept: ${NAME}_route has the filters $(printf '%s' "${SAVED}" | jq -c "${LIST}")."
FRAGMENT=$(printf '%s' "${SAVED}" | jq -c '{name, type, conditionType, description: "a fragment"}')
put_route "a PUT with only name, type, conditionType and description" 204 "${FRAGMENT}"
echo "  filters now: $(uc_value "${ROUTE_URL}" "${LIST}")"
if [ "$(uc_value "${ROUTE_URL}" "${LIST}")" = "[]" ]; then
    echo "  THE STEPS ARE GONE. The server answered 204 and said nothing about it."
else
    echo "  NOT AS DOCUMENTED: the steps are still there."
    UC_FAILED=1
fi

put_route "the way back, first try: PUT the copy that was read" 404 "$(printf '%s' "${SAVED}" | jq -c 'del(.metadata)')"
echo "  filters now: $(uc_value "${ROUTE_URL}" "${LIST}") (the ids in the copy name steps that no longer exist)"
uc_case "the way back: PATCH replace of the list, the steps without their ids" "${ROUTE_URL}" "${LIST}" 204 "$(printf '%s' "${SAVED}" | jq -c "${LIST}")" \
    "$(printf '%s' "${SAVED}" | jq -c '[{op: "replace", path: "/steps", value: [.steps[] | del(.id, .precedingStep, .metadata)]}]')"
uc_case "and the description" "${ROUTE_URL}" '.description' 204 "$(printf '%s' "${SAVED}" | jq -c '.description')" \
    "$(printf '%s' "${SAVED}" | jq -c '[{op: "replace", path: "/description", value: .description}]')"
uc_done
