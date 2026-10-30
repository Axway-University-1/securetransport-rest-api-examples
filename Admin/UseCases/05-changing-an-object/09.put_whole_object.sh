#!/bin/bash
# ==============================================================================
# Script Name: 09.put_whole_object.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Changing an object, step 9: PUT replaces the whole object, so send back the whole object you read. Read the route, change ONE field of your copy with jq, PUT the copy, read again and prove that only that field differs. Then the
# variations: without metadata, and without the route's own id (refused: the steps still carry theirs).
#
# Usage:
# ./09.put_whole_object.sh [NAME]
#
#   NAME  the account (and NAME_route, the route) to change; it must start with example_ (default example_chg)
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/09.CompositeRoutes/09.routes_id_PUT.sh. The PUT answers 204 with no body.
# - The copy keeps the id of the route and the id of every step: a step with its id on a route without its own id is refused (400 "Cannot attach a route step to another route").
# - metadata (links to related objects) may be sent or left out: both are 204.
# - The proof is a comparison of the whole object before and after, with the description taken out of both: nothing else may differ.
# - Exit 1 when a case does not come out as the README documents (the line NOT AS DOCUMENTED says which).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./09.put_whole_object.sh [NAME]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: NAME.\n%s\n" "$#" "${USAGE}"; exit 2; fi
NAME="${1:-${DEFAULT_NAME}}"
uc_check_name "${NAME}" "${USAGE}"
st_session
uc_init "${NAME}"
uc_need route

read_route() { curl -k -s -b "${JAR}" -X GET "${ROUTE_URL}" -H "accept: application/json" -H "Referer: ${REFERER}"; }
# put_route LABEL EXPECT_CODE BODY: one PUT, with the answer; sets UC_FAILED when it is not EXPECT_CODE
put_route() {
    local result code
    printf '\n--- %s\n' "$1"
    result=$(curl -k -s -w "\n%{http_code}" -b "${JAR}" -X PUT "${ROUTE_URL}" -H "accept: application/json" -H "Referer: ${REFERER}" \
             -H "Content-Type: application/json" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)" --data-binary "$3")
    code="${result##*$'\n'}"
    printf '  answer:  HTTP %s\n' "${code}"
    [ -z "${result%$'\n'*}" ] || printf '%s\n' "$(printf '%s' "${result%$'\n'*}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s' "${result%$'\n'*}")" | sed 's/^/           /'
    if [ "${code}" != "$2" ]; then
        printf '  NOT AS DOCUMENTED: this use case expects HTTP %s. The server answered HTTP %s.\n' "$2" "${code}"
        UC_FAILED=1
    fi
}

BEFORE=$(read_route)
echo "Read: ${NAME}_route has $(printf '%s' "${BEFORE}" | jq '.steps | length') steps, and the description \"$(printf '%s' "${BEFORE}" | jq -r .description)\"."
NEW=$(printf '%s' "${BEFORE}" | jq -c '.description = "changed by a PUT of the whole object"')
put_route "the object exactly as read, with one field changed" 204 "${NEW}"
AFTER=$(read_route)
echo "  description now: $(printf '%s' "${AFTER}" | jq -r .description)"
echo "  filters now:     $(printf '%s' "${AFTER}" | jq -c '[.steps[].fileFilterExpression]')"
if [ "$(printf '%s' "${BEFORE}" | jq -S -c 'del(.description)')" = "$(printf '%s' "${AFTER}" | jq -S -c 'del(.description)')" ]; then
    echo "  Compared with the copy: only the description differs."
else
    echo "  NOT AS DOCUMENTED: something besides the description differs from the copy that was read."
    UC_FAILED=1
fi

put_route "the same, without metadata" 204 "$(printf '%s' "${NEW}" | jq -c 'del(.metadata) | .description = "no metadata"')"
put_route "without the id of the route, with the id of each step: refused, nothing changes" 400 "$(printf '%s' "${NEW}" | jq -c 'del(.metadata, .id) | .description = "no id"')"
echo "  description now: $(read_route | jq -r .description) (the one of the PUT before)"
uc_done
