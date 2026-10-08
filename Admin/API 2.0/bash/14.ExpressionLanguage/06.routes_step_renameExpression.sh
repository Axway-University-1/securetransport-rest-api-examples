#!/bin/bash
# ==============================================================================
# Script Name: 06.routes_step_renameExpression.sh
# Author: Plamen Milenkov
# Created: 2025-09-29
# Location: Sofia
# ==============================================================================
# Description:
# This script demonstrates postTransformationActionRenameAsExpression - an EL
# expression that builds a new file name after a route step runs. Three
# worked examples from the EL documentation's predefined-functions appendix
# and file-name-examples table:
#
#   ${basename(transfer.target)}-${date('yyyyMMdd_HHmmss')}${extension(transfer.target)}
#       strips the extension, adds a timestamp, then re-adds the extension.
#       Note extension() includes the leading dot, so no extra '.' is needed.
#
#   ${basename(transfer.target)}-${random()}.${extension(transfer.target)}
#       appends a random ID instead of a timestamp. This one, from the EL
#       appendix's own example, writes an extra literal '.' before
#       ${extension(...)} - inconsistent with extension() already including
#       the dot (see the gotchas skill); kept here exactly as documented so
#       the inconsistency is visible, not silently corrected.
#
#   ${account.name}_${basename(transfer.target)}
#       prefixes the file name with the current account's name.
#
# APIs used - /routes ( POST, GET, DELETE )
#
# Usage:
# ./06.routes_step_renameExpression.sh
#
# Risk: write
#
# Notes:
# - Confirmed directly against a real server: this field round trips exactly
#   as sent - no backslash-doubling is needed for any of the three examples,
#   since none of them use a regex.
# - What the expression actually renames a file to is not tested here - that
#   needs a live transfer with a real file, not something this repository's
#   integration checks set up. This proves the field accepts and stores the
#   expression correctly, not what it produces.
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

create_route() {
    local suffix="$1"
    local rename_expr="$2"
    local name="ZZTEST_EL_rename_${suffix}"

    create_object "${name} with postTransformationActionRenameAsExpression: ${rename_expr}" "${name}" "{
      \"name\": \"${name}\",
      \"type\": \"SIMPLE\",
      \"conditionType\": \"ALWAYS\",
      \"steps\": [{
        \"type\": \"EncodingConversion\",
        \"status\": \"ENABLED\",
        \"conditionType\": \"ALWAYS\",
        \"usePrecedingStepFiles\": false,
        \"fileFilterExpression\": \"*\",
        \"fileFilterExpressionType\": \"GLOB\",
        \"inputCharset\": \"UTF-8\",
        \"outputCharset\": \"UTF-8\",
        \"postTransformationActionRenameAsExpression\": \"${rename_expr}\",
        \"actionOnStepFailure\": \"PROCEED\"
      }]
    }"
}

check_names_free ZZTEST_EL_rename_timestamped ZZTEST_EL_rename_randomId ZZTEST_EL_rename_accountName

create_route "timestamped" '${basename(transfer.target)}-${date('"'"'yyyyMMdd_HHmmss'"'"')}${extension(transfer.target)}'
create_route "randomId"    '${basename(transfer.target)}-${random()}.${extension(transfer.target)}'
create_route "accountName" '${account.name}_${basename(transfer.target)}'

printf "\nReading all three back...\n"
for SUFFIX in timestamped randomId accountName; do
    read_back "ZZTEST_EL_rename_${SUFFIX}" name,steps.postTransformationActionRenameAsExpression
done

# The three throwaway routes are deleted by cleanup(), when the script ends
exit 0
