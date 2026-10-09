#!/bin/bash
# ==============================================================================
# Script Name: 08.transferSites_dynamicProperties.sh
# Author: Plamen Milenkov
# Created: 2025-09-29
# Location: Sofia
# ==============================================================================
# Description:
# This script demonstrates the DXAGENT_TRANSFERSAPI_* pattern: a transfer
# site's own field holds a template like ${DXAGENT_TRANSFERSAPI_SERVER}
# instead of a fixed value, so the same site can be reused for many partners
# or file patterns - the actual value is supplied later, per request, in
# customProperties on a transfer operation (POST /transfers/operations),
# which this script does not call - only the site side of the pattern is
# shown here.
#
# APIs used - /sites ( POST, GET, DELETE )
#
# Usage:
# ./08.transferSites_dynamicProperties.sh
#
# Risk: write
#
# Notes:
# - Confirmed directly against a real server: a site's host and
#   downloadPattern fields accept and store the literal template text
#   verbatim - "${DXAGENT_TRANSFERSAPI_SERVER}" is not evaluated or rejected
#   at creation time, it is just a string until a real transfer request
#   supplies the matching customProperties key.
# - "${DXAGENT_TRANSFERSAPI_FOO}" is a generic placeholder shape from the EL
#   documentation - FOO is any name of your choosing, matched against
#   whatever key you send as customProperties.FOO on the actual pull/push
#   request. This example uses SERVER and FILE to match the fields they fill.
# - This site's account "john" must already exist, the same assumption
#   06.TransferSites/01.sites_POST.sh makes.
# - Cleanup: every object is deleted again by the id the server answered its POST with (the `Location` header), never by looking a name up, so an object this
#   script did not create is never deleted. The cleanup also runs when a call is refused or the script is interrupted. When an object with one of these
#   names exists already the script stops before creating anything (exit 2) and says which: the ZZTEST_EL_ names are reserved for this folder, so remove
#   a leftover of an earlier run by hand.
# - Confirmed directly: a site is created with 201 and its address, ending in the site's id, in `Location`; the same name on the same account is 409 "Entry already exist.";
#   the `name=` filter ignores case and takes a * wildcard.
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

MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/sites"
ACCOUNT="${ST_EXAMPLE_ACCOUNT:-john}"
ACCOUNT_JSON=$(jq -n --arg account "${ACCOUNT}" '$account')

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
            printf "A site named %s exists already:\n%s\n" "${name}" "${found}"
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

NAME="ZZTEST_EL_dynamicSite"

check_names_free "${NAME}"

create_object "${NAME} with templated host and downloadPattern fields..." "${NAME}" "{
  \"name\": \"${NAME}\",
  \"type\": \"http\",
  \"protocol\": \"http\",
  \"account\": ${ACCOUNT_JSON},
  \"host\": \"\${DXAGENT_TRANSFERSAPI_SERVER}\",
  \"port\": \"443\",
  \"downloadPattern\": \"\${DXAGENT_TRANSFERSAPI_FILE}\",
  \"uploadFolder\": \"/\",
  \"userName\": ${ACCOUNT_JSON}
}"

printf "\nReading it back - both fields should still hold the literal template text:\n"
read_back "${NAME}" name,host,downloadPattern

# The throwaway site is deleted by cleanup(), when the script ends
exit 0
