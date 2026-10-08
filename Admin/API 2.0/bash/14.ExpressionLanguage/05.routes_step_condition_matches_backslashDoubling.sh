#!/bin/bash
# ==============================================================================
# Script Name: 05.routes_step_condition_matches_backslashDoubling.sh
# Author: Plamen Milenkov
# Created: 2025-09-29
# Location: Sofia
# ==============================================================================
# Description:
# This script isolates the single most error-prone thing about writing an EL
# regex: two independent escaping layers stack on top of each other, and
# getting only one of them right still produces something that looks fine.
#
#   Layer 1 - Java regex: a literal dot needs one backslash:            \.
#   Layer 2 - the EL string literal that holds that regex, per the EL
#             documentation's own rule ("every backslash must be written
#             twice"): the regex text above, written inside ${...}, becomes: \\.
#             So the EL expression text a human reads is:
#                 ${transfer.target.matches('.*\\.txt')}
#   Layer 3 - JSON, once that whole EL expression is the value of a JSON
#             field: every backslash in the EL text is itself escaped again
#             for JSON. Two backslash characters become four in the JSON
#             source text:
#                 "condition": "${transfer.target.matches('.*\\\\.txt')}"
#
# This script creates two throwaway routes so the difference is visible
# side by side:
#
#   ZZTEST_EL_doubled  - four backslashes in this script's own source (the
#                        correct, fully-escaped form above)
#   ZZTEST_EL_single   - two backslashes in this script's own source, which
#                        is valid JSON and gets stored without complaint, but
#                        is missing the EL layer's own doubling. Per the EL
#                        documentation's own worked example ("Unescaped-dot
#                        form... looser because the unescaped dot matches any
#                        character"), this changes what the expression
#                        matches once it actually runs - it is not merely
#                        cosmetic.
#
# APIs used - /routes ( POST, GET, DELETE )
#
# Usage:
# ./05.routes_step_condition_matches_backslashDoubling.sh
#
# Risk: write
#
# Notes:
# - Confirmed directly against a real server: a route with the four
#   backslash form stores a condition value containing exactly two backslash
#   characters (json-encoded back as \\\\ in a pretty-printed response,
#   which is JSON's own display convention for two real backslash
#   characters) - this script's GET step shows both stored values so the
#   difference is directly visible, not just asserted.
# - What each stored value actually MATCHES against a real file name at
#   transfer time is not tested here - that needs a live transfer, which is
#   a different kind of test than this repository's integration checks run.
#   See 04.routes_step_fileFilterExpression_regexp.sh's notes for the
#   related, but distinct, rule about a *raw* (non-EL) regex field.
# - Cleanup: every object is deleted again by the id the server answered its POST with (the `Location` header), never by looking a name up, so an object this
#   script did not create is never deleted. The cleanup also runs when a call is refused or the script is interrupted. When an object with one of these
#   names exists already the script stops before creating anything (exit 2) and says which: the ZZTEST_EL_ names are reserved for this folder, so remove
#   a leftover of an earlier run by hand.
# - Confirmed directly: a route is created with 201 and its address, ending in the route's id, in `Location`; two simple routes may have the same name, so a delete that
#   looks the id up by name could take the wrong one; the `name=` filter ignores case.
# - Requires `jq`, which reads the answers. The request bodies are written out by hand on purpose: this folder is about how an expression is written
#   inside JSON.
# - Exit codes: 0 when every call answered what was expected (201 for a creation, 200 for a read, 204 for a delete), 1 when the server refuses a call (what was
#   created is deleted all the same), 2 when an object of one of these names exists already (nothing is created or deleted).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes"

HEADERS_FILE=$(mktemp)
CREATED=()          # "id name" of every object this script created, to delete again
CLEANUP_FAILED=0

# Deletes what this script created, by the id the server answered the POST with: never an object it did not create.
# Runs whenever the script ends: after a refusal, after an interruption, and after the last step.
cleanup() {
    local entry id name code
    rm -f "${HEADERS_FILE}"
    if [ "${#CREATED[@]}" -gt 0 ]; then
        printf "\nCleaning up the throwaway objects...\n"
    fi
    for entry in "${CREATED[@]}"; do
        id="${entry%% *}"
        name="${entry#* }"
        RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${id}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
        code="${RESPONSE##*$'\n'}"
        printf "deleted %s (%s): HTTP %s\n" "${name}" "${id}" "${code}"
        if [ "${code}" != "204" ]; then
            printf '%s\n' "${RESPONSE%$'\n'*}"
            CLEANUP_FAILED=1
        fi
    done
    CREATED=()
}
finish() {
    cleanup
    [ "${CLEANUP_FAILED}" = "0" ] || exit 1
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# show_refusal ANSWER: what the server said, when it did not say what was expected
show_refusal() {
    printf '%s' "$1" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "$1"
}

# check_names_free NAME...: nothing this script did not create is ever deleted, so it stops (exit 2) when one of these names is there already.
# The name filter ignores case, so a name that differs by case is there too.
check_names_free() {
    local name found taken=0
    for name in "$@"; do
        RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "name=${name}" --data-urlencode "fields=id,name" \
          -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
        HTTP_CODE="${RESPONSE##*$'\n'}"
        RESPONSE="${RESPONSE%$'\n'*}"
        if [ "${HTTP_CODE}" != "200" ]; then
            printf "Could not look for %s (HTTP %s), so nothing was created.\n" "${name}" "${HTTP_CODE}"
            exit 1
        fi
        found=$(printf '%s' "${RESPONSE}" | jq -r --arg name "${name}" '(.result // [])[] | select((.name // "" | ascii_downcase) == ($name | ascii_downcase)) | "  \(.name) (id \(.id))"')
        if [ -n "${found}" ]; then
            printf "A route named %s exists already:\n%s\n" "${name}" "${found}"
            taken=1
        fi
    done
    if [ "${taken}" = "1" ]; then
        printf "Nothing was created and nothing was deleted: this script only deletes what it created. Remove them first, or leave them.\n"
        exit 2
    fi
}

# create_object DESCRIPTION NAME BODY: POST the body, expect 201, and remember the id from the Location header for the cleanup
create_object() {
    printf "\nCreating %s\n" "$1"
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
      -d "$3" -D "${HEADERS_FILE}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    printf "HTTP %s\n" "${HTTP_CODE}"
    if [ "${HTTP_CODE}" != "201" ]; then
        show_refusal "${RESPONSE}"
        exit 1
    fi
    OBJECT_ID=$(sed -n 's/^[Ll]ocation: *//p' "${HEADERS_FILE}" | tr -d '\r' | sed 's#.*/##')
    if [ -z "${OBJECT_ID}" ]; then
        # No address came back. The name was free before this script, so the one object with it is ours
        OBJECT_ID=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "name=$2" --data-urlencode "fields=id,name" \
          -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r --arg name "$2" '[(.result // [])[] | select(.name == $name)] | if length == 1 then .[0].id else empty end')
    fi
    if [ -z "${OBJECT_ID}" ]; then
        printf "The server created %s but did not say where, and its id could not be found: delete it by hand.\n" "$2"
        exit 1
    fi
    CREATED+=("${OBJECT_ID} $2")
}

# read_back NAME FIELDS: print the object as the server holds it, found by its name
read_back() {
    printf "\n%s:\n" "$1"
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?name=$1&fields=$2" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "HTTP %s\n" "${HTTP_CODE}"
        show_refusal "${RESPONSE}"
        exit 1
    fi
    printf '%s\n' "${RESPONSE}"
}

check_names_free ZZTEST_EL_doubled ZZTEST_EL_single

create_object "ZZTEST_EL_doubled - the correctly escaped form (4 backslashes in this script's source)..." ZZTEST_EL_doubled \
'{"name":"ZZTEST_EL_doubled","type":"SIMPLE","conditionType":"EL","condition":"${transfer.target.matches('"'"'.*\\\\.txt'"'"')}"}'

create_object "ZZTEST_EL_single - missing the EL layers own doubling (2 backslashes in this script's source)..." ZZTEST_EL_single \
'{"name":"ZZTEST_EL_single","type":"SIMPLE","conditionType":"EL","condition":"${transfer.target.matches('"'"'.*\\.txt'"'"')}"}'

printf "\nReading both back - compare the number of backslashes in each condition value:\n"
read_back ZZTEST_EL_doubled name,condition
read_back ZZTEST_EL_single name,condition

# The two throwaway routes are deleted by cleanup(), when the script ends
exit 0
