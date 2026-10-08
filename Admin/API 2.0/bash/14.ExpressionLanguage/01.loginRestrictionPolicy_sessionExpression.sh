#!/bin/bash
# ==============================================================================
# Script Name: 01.loginRestrictionPolicy_sessionExpression.sh
# Author: Plamen Milenkov
# Created: 2025-09-29
# Location: Sofia
# ==============================================================================
# Description:
# This script demonstrates SecureTransport's Expression Language (EL) used in
# a login restriction rule: a session-count guard written as
#   ${currentSessions <= 3}
# Login restriction rules are the one place in the product where a raw EL
# expression is a first class field on its own - most other places embed EL
# inside a string field on a bigger object (a route condition, a rename
# pattern), which the other scripts in this folder demonstrate instead.
#
# It creates a throwaway policy, adds the rule, shows it, then deletes the
# whole policy - a fresh policy always starts with an empty rules array and
# is not attached to anything (no business unit, not the default policy), so
# it has no effect on any real login while it exists.
#
# APIs used - /loginRestrictionPolicies ( POST, GET, PATCH, DELETE )
#
# Usage:
# ./01.loginRestrictionPolicy_sessionExpression.sh
#
# Risk: write
#
# Notes:
# - Confirmed directly against a real server: POST /loginRestrictionPolicies
#   requires "type" (ALLOW_THEN_DENY or DENY_THEN_ALLOW) and a policy starts
#   with rules: [].
# - The rule's own JSON has an "expression" field alongside "type" (ALLOW or
#   DENY), "isEnabled", "clientAddress" and "description" - the EL expression
#   is one field among several on the rule object, not the whole rule.
# - Cleanup: the policy is deleted again whatever happens, also when a call is refused or the script is interrupted, but only the policy this script
#   created. When a policy named ZZTEST_EL_sessionLimit exists already the script stops before creating anything (exit 2) and says so: the ZZTEST_EL_
#   names are reserved for this folder, so remove a leftover of an earlier run by hand.
# - Confirmed directly: a policy is created with 201 (the address in `Location` ends with its name) and a second one with the same name is 409. The rule is
#   added with PATCH (204) and a rule with no clientAddress or a type other than ALLOW or DENY is 400 with the reasons in `validationErrors`. The `name=`
#   filter of the list ignores case.
# - Requires `jq`, which reads the answers. The request bodies are written out by hand on purpose: this folder is about how an expression is written
#   inside JSON (see 05).
# - Exit codes: 0 when every call answered what was expected (201, 204, 200, 204), 1 when the server refuses a call (the policy is deleted all the same),
#   2 when a policy of that name exists already (nothing is created or deleted).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

POLICY="ZZTEST_EL_sessionLimit"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/loginRestrictionPolicies"
CREATED=""
CLEANUP_FAILED=0

# Deletes the policy this script created, when it did. Runs whenever the script ends: after a refusal, an interruption, or the last step.
cleanup() {
    if [ -n "${CREATED}" ]; then
        CREATED=""
        printf "\nCleaning up the throwaway policy...\n"
        RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${POLICY}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
        HTTP_CODE="${RESPONSE##*$'\n'}"
        printf "deleted %s: HTTP %s\n" "${POLICY}" "${HTTP_CODE}"
        if [ "${HTTP_CODE}" != "204" ]; then
            printf '%s\n' "${RESPONSE%$'\n'*}"
            CLEANUP_FAILED=1
        fi
    fi
}
finish() {
    cleanup
    [ "${CLEANUP_FAILED}" = "0" ] || exit 1
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# show_refusal: what the server said, when it did not say what was expected
show_refusal() {
    printf '%s' "$1" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "$1"
}

# Nothing this script did not create is ever deleted: it stops when a policy of this name is there already
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "name=${POLICY}" --data-urlencode "fields=id,name" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not look for %s (HTTP %s), so nothing was created.\n" "${POLICY}" "${HTTP_CODE}"
    exit 1
fi
FOUND=$(printf '%s' "${RESPONSE}" | jq -r --arg name "${POLICY}" '(.result // [])[] | select((.name // "" | ascii_downcase) == ($name | ascii_downcase)) | "  \(.name) (id \(.id))"')
if [ -n "${FOUND}" ]; then
    printf "A login restriction policy named %s exists already:\n%s\n" "${POLICY}" "${FOUND}"
    printf "Nothing was created and nothing was deleted: this script only deletes what it created. Remove it first, or leave it.\n"
    exit 2
fi

printf "Creating a throwaway login restriction policy...\n"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" \
-H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
-d "{\"name\":\"${POLICY}\",\"type\":\"ALLOW_THEN_DENY\"}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "201" ]; then
    show_refusal "${RESPONSE}"
    exit 1
fi
CREATED="yes"

printf "\nAdding a rule that only allows login while fewer than 4 sessions are active...\n"
# The rule is appended at index 0 of the (currently empty) rules array. See
# 05.Accounts/06.accounts_name_PATCH.sh's own notes on appending to an array -
# "/rules/-" would be the safe form on an array that might not be empty; here
# it is always empty because the policy was just created.
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/${POLICY}" \
-H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
-d "[{
      \"op\": \"add\",
      \"path\": \"/rules/0\",
      \"value\": {
        \"name\": \"sessions fewer than 4\",
        \"isEnabled\": true,
        \"type\": \"ALLOW\",
        \"clientAddress\": \"*\",
        \"expression\": \"\${currentSessions <= 3}\",
        \"description\": \"Only allow if less than 4 sessions\"
      }
    }]" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    show_refusal "${RESPONSE}"
    exit 1
fi

printf "\nReading the policy back...\n"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${POLICY}" \
-H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s\n" "${HTTP_CODE}"
    show_refusal "${RESPONSE}"
    exit 1
fi
printf '%s\n' "${RESPONSE}"

# The throwaway policy is deleted by cleanup(), when the script ends
exit 0
