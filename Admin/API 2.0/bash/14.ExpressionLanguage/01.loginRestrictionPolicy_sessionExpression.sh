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
# APIs used - /myself ( ST login and logout )
#             /loginRestrictionPolicies ( POST, GET, PATCH, DELETE )
#
# Usage:
# ./01.loginRestrictionPolicy_sessionExpression.sh
#
# Notes:
# - Confirmed directly against a real server: POST /loginRestrictionPolicies
#   requires "type" (ALLOW_THEN_DENY or DENY_THEN_ALLOW) and a policy starts
#   with rules: [].
# - The rule's own JSON has an "expression" field alongside "type" (ALLOW or
#   DENY), "isEnabled", "clientAddress" and "description" - the EL expression
#   is one field among several on the rule object, not the whole rule.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

POLICY="ZZTEST_EL_sessionLimit"

printf "Creating a throwaway login restriction policy...\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/loginRestrictionPolicies" \
-H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
-d "{\"name\":\"${POLICY}\",\"type\":\"ALLOW_THEN_DENY\"}"

printf "\n\nAdding a rule that only allows login while fewer than 4 sessions are active...\n"
# The rule is appended at index 0 of the (currently empty) rules array. See
# 05.Accounts/06.accounts_name_PATCH.sh's own notes on appending to an array -
# "/rules/-" would be the safe form on an array that might not be empty; here
# it is always empty because the policy was just created.
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "https://${ST_SERVER}:${ST_PORT}/api/v2.0/loginRestrictionPolicies/${POLICY}" \
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
    }]"

printf "\n\nReading the policy back...\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/loginRestrictionPolicies/${POLICY}" \
-H "accept: application/json" -H "${REFERER_HEADER}"

printf "\n\nCleaning up the throwaway policy...\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "https://${ST_SERVER}:${ST_PORT}/api/v2.0/loginRestrictionPolicies/${POLICY}" \
-H "accept: application/json" -H "${REFERER_HEADER}"
