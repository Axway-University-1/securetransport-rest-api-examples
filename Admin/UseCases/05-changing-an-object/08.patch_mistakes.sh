#!/bin/bash
# ==============================================================================
# Script Name: 08.patch_mistakes.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Changing an object, step 8: what goes wrong with a PATCH, and what the server says. A patch that is all or nothing, a typo in the path of an add (answered 204, changes nothing), a replace of a field that is
# not there (400 "Missing field"), a body that is not a list, an operation that does not exist, and a missing or wrong Content-Type (415). Each case shows the answer and that the field did not change.
#
# Usage:
# ./08.patch_mistakes.sh [NAME]
#
#   NAME  the account (and NAME_route, the route) to change; it must start with example_ (default example_chg)
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/05.Accounts/06.accounts_name_PATCH.sh, with the wrong requests.
# - A patch is all or nothing: two operations, the second wrong, and the first is not applied either.
# - A typo in the path of an `add` is not an error: it answers 204 and stores nothing. Read the object back, as every case here does.
# - Content-Type: without it, and with text/plain, the answer is 415 (the case sends none, with -H "Content-Type:", which makes curl leave the header out).
# - Exit 1 when a case does not come out as the README documents (the line NOT AS DOCUMENTED says which).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./08.patch_mistakes.sh [NAME]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: NAME.\n%s\n" "$#" "${USAGE}"; exit 2; fi
NAME="${1:-${DEFAULT_NAME}}"
uc_check_name "${NAME}" "${USAGE}"
st_session
uc_init "${NAME}"
uc_need account
NOTES=$(uc_value "${ACCOUNT_URL}" '.notes')
KEYS='.contact | keys'

uc_case "all or nothing: the first operation is right, the second is not, and neither is applied" "${ACCOUNT_URL}" '.notes' 400 "${NOTES}" \
    '[{"op":"replace","path":"/notes","value":"first"},{"op":"replace","path":"/nosuchfield","value":"second"}]'
uc_case "a typo in the path of an add: 204, and the object has no new field" "${ACCOUNT_URL}" "${KEYS}" 204 '["email","phone"]' \
    '[{"op":"add","path":"/contact/phon","value":"+359 2 000 0000"}]'
uc_case "replace of a field the object does not have" "${ACCOUNT_URL}" '.notes' 400 "${NOTES}" \
    '[{"op":"replace","path":"/nosuchfield","value":"x"}]'
uc_case "a body that is one operation, not a list" "${ACCOUNT_URL}" '.notes' 400 "${NOTES}" \
    '{"op":"replace","path":"/notes","value":"x"}'
uc_case "an operation that does not exist" "${ACCOUNT_URL}" '.notes' 400 "${NOTES}" \
    '[{"op":"swap","path":"/notes","value":"x"}]'
CASE_CT=none uc_case "no Content-Type" "${ACCOUNT_URL}" '.notes' 415 "${NOTES}" \
    '[{"op":"replace","path":"/notes","value":"x"}]'
CASE_CT="text/plain" uc_case "Content-Type text/plain" "${ACCOUNT_URL}" '.notes' 415 "${NOTES}" \
    '[{"op":"replace","path":"/notes","value":"x"}]'
uc_done
