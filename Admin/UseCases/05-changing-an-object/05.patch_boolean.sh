#!/bin/bash
# ==============================================================================
# Script Name: 05.patch_boolean.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Changing an object, step 5: a BOOLEAN. The value of a true/false field is true or false, with no quotes. PATCH replace and remove on transfersWebServiceAllowed and authByEmail of the account, then the values the server
# converts ("false", 1) and the ones it refuses ("yes", null on a field that cannot be null). Each case shows the body sent, the answer and the field before and after.
#
# Usage:
# ./05.patch_boolean.sh [NAME]
#
#   NAME  the account (and NAME_route, the route) to change; it must start with example_ (default example_chg)
#
# Risk: write
#
# Notes:
# - Written for this use case, from the Admin API reference and what the lab answers. Every call is a PATCH with a list of operations.
# - The server converts "false" and "true" in quotes, and 1 and 0, into true and false. Do not rely on it: write true or false with no quotes.
# - "yes" is refused (400 "Cannot parse ... to Boolean."). null is refused on a field that must have a value (disabled), and quietly becomes false on transfersWebServiceAllowed.
# - `remove` on a boolean puts false (its default) back: it does not make it null.
# - Exit 1 when a case does not come out as the README documents (the line NOT AS DOCUMENTED says which).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./05.patch_boolean.sh [NAME]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: NAME.\n%s\n" "$#" "${USAGE}"; exit 2; fi
NAME="${1:-${DEFAULT_NAME}}"
uc_check_name "${NAME}" "${USAGE}"
st_session
uc_init "${NAME}"
uc_need account

uc_case "replace a boolean: true, with no quotes" "${ACCOUNT_URL}" '.transfersWebServiceAllowed' 204 'true' \
    '[{"op":"replace","path":"/transfersWebServiceAllowed","value":true}]'
uc_case "false in quotes is accepted and converted" "${ACCOUNT_URL}" '.transfersWebServiceAllowed' 204 'false' \
    '[{"op":"replace","path":"/transfersWebServiceAllowed","value":"false"}]'
uc_case "a word that is not true or false is refused, nothing changes" "${ACCOUNT_URL}" '.transfersWebServiceAllowed' 400 'false' \
    '[{"op":"replace","path":"/transfersWebServiceAllowed","value":"yes"}]'
uc_case "a number is converted too: 1 is true" "${ACCOUNT_URL}" '.transfersWebServiceAllowed' 204 'true' \
    '[{"op":"replace","path":"/transfersWebServiceAllowed","value":1}]'
uc_case "remove: back to the default, false (not null)" "${ACCOUNT_URL}" '.transfersWebServiceAllowed' 204 'false' \
    '[{"op":"remove","path":"/transfersWebServiceAllowed"}]'
uc_case "null on a boolean that must have a value is refused" "${ACCOUNT_URL}" '.disabled' 400 'false' \
    '[{"op":"replace","path":"/disabled","value":null}]'
uc_case "the same on a second boolean (authByEmail): true" "${ACCOUNT_URL}" '.authByEmail' 204 'true' \
    '[{"op":"replace","path":"/authByEmail","value":true}]'
uc_case "and back to false" "${ACCOUNT_URL}" '.authByEmail' 204 'false' \
    '[{"op":"replace","path":"/authByEmail","value":false}]'
uc_done
