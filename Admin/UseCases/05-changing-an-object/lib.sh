#!/bin/bash
# ==============================================================================
# Script Name: lib.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Sourced by every script of this use case. Loads ../session.sh (the settings, ST_URL, the cookie jar session.cookie.jar of this use case and st_session) and gives the helpers the steps share:
#
#   uc_check_name NAME USAGE   the name must be example_*: 99 deletes by name, and this keeps it off a real object
#   uc_init NAME               sets ACCOUNT_URL (the account NAME) and ROUTE_NAME (NAME_route); the route's id is read by uc_route_id
#   uc_need account|route      exits 1, saying to run 01 first, when the object the step changes is not there; for the route it sets ROUTE_ID and ROUTE_URL
#   uc_route_id                the id of the route: from state.local.route_id, or looked up by its exact name
#   uc_value URL FILTER        reads the object and prints one jq filter of it, in one line (what a before and an after show)
#   uc_case LABEL URL FILTER EXPECT_CODE EXPECT_AFTER BODY
#                              one PATCH, shown whole: the body as it is sent, the value before, the answer (and the server's message when it
#                              refuses), the value after. Sets UC_FAILED=1 when the answer or the value after is not what EXPECT_CODE and
#                              EXPECT_AFTER (a compact JSON text) say. CASE_CT sets the Content-Type ("none" sends none).
#   uc_done                    ends a step: exit 1 when a case did not come out as documented, 0 otherwise
#   uc_step FILTER             the JSON of one route step (an EncodingConversion with that file filter)
#   uc_option_read OPTION      the answer of GET /configurations/options?name=OPTION, without the envelope
#   uc_option_put OPTION VALUES_JSON   PUT of one option with a list of text; prints the HTTP code
#
# Usage:
# source lib.sh
#
# Risk: none
# ==============================================================================

UC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${UC_DIR}/../session.sh"

DEFAULT_NAME="example_chg"
DEFAULT_OPTION="AddressBook.Limit.MaxDisplayEntries"
ROUTE_ID_FILE="${UC_DIR}/state.local.route_id"
OPTION_FILE="${UC_DIR}/state.local.option.json"      # the whole answer for the option, as it was before step 11
ACCOUNT_COPY="${UC_DIR}/state.local.account.json"    # the account as 02 read it
ROUTE_COPY="${UC_DIR}/state.local.route.json"        # the route as 02 read it
UC_FAILED=0

# uc_check_name NAME USAGE: exits 2, with the usage, before anything is sent, when NAME is not a name this use case may touch
uc_check_name() {
    local name="$1" usage="$2"
    if [[ ! "${name}" =~ ^example_[A-Za-z0-9._-]+$ ]]; then
        printf "NAME is '%s': it must start with example_ and hold only letters, digits, '.', '_' and '-'. This use case deletes the account and the route it makes, by name, so it stays off real objects.\n" "${name}"
        printf "%s\n" "${usage}"
        exit 2
    fi
}

uc_init() {
    local name_uri
    ROUTE_NAME="${1}_route"
    name_uri=$(printf '%s' "$1" | jq -Rr @uri)
    ACCOUNT_URL="${ST_URL}/accounts/${name_uri}"
}

# uc_need account|route: exits 1, with what to run first, when the object this step changes is not there (a HEAD, no change)
uc_need() {
    local url code
    if [ "$1" = "route" ]; then
        ROUTE_ID=$(uc_route_id)
        [ -n "${ROUTE_ID}" ] || { echo "There is no route ${ROUTE_NAME}. Run 01.object_POST.sh first."; exit 1; }
        url="${ST_URL}/routes/${ROUTE_ID}"
        ROUTE_URL="${url}"
    else
        url="${ACCOUNT_URL}"
    fi
    code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" --head "${url}" -H "accept: */*" -H "Referer: ${REFERER}")
    case "${code}" in
        200) ;;
        404) echo "There is no $1 for ${NAME}. Run 01.object_POST.sh first."; exit 1 ;;
        *) echo "Could not tell whether the $1 of ${NAME} exists (HTTP ${code}). Nothing was changed."; exit 1 ;;
    esac
}

uc_uid() {
    echo $((50000 + $(printf '%s' "$1" | cksum | cut -d' ' -f1) % 9999))
}

uc_route_id() {
    if [ -s "${ROUTE_ID_FILE}" ]; then
        cat "${ROUTE_ID_FILE}"
        return
    fi
    curl -k -s -b "${JAR}" -G "${ST_URL}/routes" --data-urlencode "name=${ROUTE_NAME}" --data-urlencode "fields=id,name" -H "accept: application/json" -H "Referer: ${REFERER}" \
        | jq -r --arg name "${ROUTE_NAME}" '[(.result // [])[] | select(.name == $name)] | if length == 1 then .[0].id else empty end'
}

uc_value() {
    curl -k -s -b "${JAR}" -X GET "$1" -H "accept: application/json" -H "Referer: ${REFERER}" | jq -c "$2" 2>/dev/null || echo "(not readable)"
}

uc_case() {
    local label="$1" url="$2" filter="$3" expect_code="$4" expect_after="$5" body="$6" result code answer after ctype=(-H "Content-Type: application/json")
    case "${CASE_CT:-}" in
        "") ;;
        none) ctype=(-H "Content-Type:") ;;
        *) ctype=(-H "Content-Type: ${CASE_CT}") ;;
    esac
    printf '\n--- %s\n' "${label}"
    printf '  body:    %s\n' "${body}"
    printf '  before:  %s\n' "$(uc_value "${url}" "${filter}")"
    result=$(curl -k -s -w "\n%{http_code}" -b "${JAR}" -X PATCH "${url}" -H "accept: application/json" -H "Referer: ${REFERER}" "${ctype[@]}" \
             -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)" -d "${body}")
    code="${result##*$'\n'}"
    answer="${result%$'\n'*}"
    printf '  answer:  HTTP %s\n' "${code}"
    if [ -n "${answer}" ]; then
        printf '%s\n' "$(printf '%s' "${answer}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s' "${answer}")" | sed 's/^/           /'
    fi
    after=$(uc_value "${url}" "${filter}")
    printf '  after:   %s\n' "${after}"
    if [ "${code}" != "${expect_code}" ] || [ "${after}" != "${expect_after}" ]; then
        printf '  NOT AS DOCUMENTED: this use case expects HTTP %s and %s. The server answered HTTP %s and %s. The server may be another release than the one the README was checked on.\n' \
            "${expect_code}" "${expect_after}" "${code}" "${after}"
        UC_FAILED=1
    fi
}

uc_done() {
    if [ "${UC_FAILED}" -ne 0 ]; then
        echo
        echo "At least one case did not come out as documented: see NOT AS DOCUMENTED above."
        exit 1
    fi
    exit 0
}

uc_step() {
    jq -cn --arg filter "$1" '{type: "EncodingConversion", status: "ENABLED", conditionType: "ALWAYS", usePrecedingStepFiles: false,
        fileFilterExpression: $filter, fileFilterExpressionType: "GLOB", inputCharset: "UTF-8", outputCharset: "UTF-8", actionOnStepFailure: "PROCEED"}'
}

uc_option_read() {
    curl -k -s -b "${JAR}" -G "${ST_URL}/configurations/options" --data-urlencode "name=$1" -H "accept: application/json" -H "Referer: ${REFERER}" | jq -c '.result[0] // empty'
}

uc_option_put() {
    local body
    body=$(jq -cn --arg name "$1" --argjson values "$2" '[{name: $name, values: $values}]')
    curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X PUT "${ST_URL}/configurations/options" -H "accept: application/json" -H "Referer: ${REFERER}" \
        -H "Content-Type: application/json" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)" -d "${body}"
}
