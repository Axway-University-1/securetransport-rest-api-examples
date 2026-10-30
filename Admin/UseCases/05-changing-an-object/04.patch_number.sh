#!/bin/bash
# ==============================================================================
# Script Name: 04.patch_number.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Changing an object, step 4: a NUMBER. The value of a number field is a JSON number, with no quotes. PATCH replace and remove on user.failedAuthMaximum (a whole number, 0 or more) and on bandwidthLimits.inboundLimit
# (a number that is null until a limit is set), then a number sent to a field that is really text (uid). Each case shows the body sent, the answer and the field before and after.
#
# Usage:
# ./04.patch_number.sh [NAME]
#
#   NAME  the account (and NAME_route, the route) to change; it must start with example_ (default example_chg)
#
# Risk: write
#
# Notes:
# - Written for this use case, from the Admin API reference and what the lab answers. Every call is a PATCH with a list of operations.
# - The server is generous with numbers: "7" (in quotes) is accepted and stored as 7, and 2.5 is accepted and stored as 2, without a word. Do not rely on either: write a whole number with no quotes.
# - A text that is not a number is refused (400 "Cannot parse ... to Integer."), and a number below the minimum is refused too.
# - `remove` on a number that has a default puts the default back (failedAuthMaximum is 3). On a number that has none (inboundLimit) it leaves null.
# - uid looks like a number but is a text field: a number sent to it is stored as text. The script puts the old uid back at the end.
# - Exit 1 when a case does not come out as the README documents (the line NOT AS DOCUMENTED says which).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./04.patch_number.sh [NAME]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: NAME.\n%s\n" "$#" "${USAGE}"; exit 2; fi
NAME="${1:-${DEFAULT_NAME}}"
uc_check_name "${NAME}" "${USAGE}"
st_session
uc_init "${NAME}"
uc_need account
UID_BEFORE=$(uc_value "${ACCOUNT_URL}" '.uid')

uc_case "replace a number: write it with no quotes" "${ACCOUNT_URL}" '.user.failedAuthMaximum' 204 '5' \
    '[{"op":"replace","path":"/user/failedAuthMaximum","value":5}]'
uc_case "a number in quotes is accepted and converted" "${ACCOUNT_URL}" '.user.failedAuthMaximum' 204 '7' \
    '[{"op":"replace","path":"/user/failedAuthMaximum","value":"7"}]'
uc_case "a text that is not a number is refused, nothing changes" "${ACCOUNT_URL}" '.user.failedAuthMaximum' 400 '7' \
    '[{"op":"replace","path":"/user/failedAuthMaximum","value":"abc"}]'
uc_case "a decimal is accepted for a whole number: the part after the point is dropped, with no warning" "${ACCOUNT_URL}" '.user.failedAuthMaximum' 204 '2' \
    '[{"op":"replace","path":"/user/failedAuthMaximum","value":2.5}]'
uc_case "a number below the minimum is refused" "${ACCOUNT_URL}" '.user.failedAuthMaximum' 400 '2' \
    '[{"op":"replace","path":"/user/failedAuthMaximum","value":-1}]'
uc_case "remove: a number that has a default goes back to the default (3), it does not become null" "${ACCOUNT_URL}" '.user.failedAuthMaximum' 204 '3' \
    '[{"op":"remove","path":"/user/failedAuthMaximum"}]'
uc_case "a number that is null until it is set: the limit needs the policy custom, in the same patch" "${ACCOUNT_URL}" '.bandwidthLimits.inboundLimit' 204 '512' \
    '[{"op":"replace","path":"/bandwidthLimits/policy","value":"custom"},{"op":"replace","path":"/bandwidthLimits/inboundLimit","value":512}]'
uc_case "remove: a number with no default is null again" "${ACCOUNT_URL}" '.bandwidthLimits.inboundLimit' 204 'null' \
    '[{"op":"remove","path":"/bandwidthLimits/inboundLimit"}]'
uc_case "put the policy back (a text): the account has no limit again" "${ACCOUNT_URL}" '.bandwidthLimits.policy' 204 '"default"' \
    '[{"op":"replace","path":"/bandwidthLimits/policy","value":"default"}]'
uc_case "uid looks like a number but is text: a number sent to it is stored as text" "${ACCOUNT_URL}" '.uid' 204 '"60000"' \
    '[{"op":"replace","path":"/uid","value":60000}]'
uc_case "put the old uid back, as text (this is how a text is written)" "${ACCOUNT_URL}" '.uid' 204 "${UID_BEFORE}" \
    "$(jq -cn --argjson uid "${UID_BEFORE}" '[{op: "replace", path: "/uid", value: $uid}]')"
uc_done
