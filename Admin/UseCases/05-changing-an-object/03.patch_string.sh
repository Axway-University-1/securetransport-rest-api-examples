#!/bin/bash
# ==============================================================================
# Script Name: 03.patch_string.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Changing an object, step 3: a STRING. The value of a text field is a JSON string, in double quotes. PATCH replace, add and remove on the notes and the contact of the account, each shown with the body sent, the answer, and the field
# before and after. Then the two mistakes that come with text: a number sent to a text field, and a list.
#
# Usage:
# ./03.patch_string.sh [NAME]
#
#   NAME  the account (and NAME_route, the route) to change; it must start with example_ (default example_chg)
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/05.Accounts/06.accounts_name_PATCH.sh, with more operations. Every call is a PATCH with a body that is a LIST of operations, Content-Type application/json and the csrfToken of the session.
# - `replace` needs the field to exist (null counts: the field is in the answer with the value null). `add` sets it. `remove` leaves the field in the answer with the value null.
# - A number sent to a text field is stored as the text of the number (5 becomes "5"). An empty string is stored as null. A list is refused (400 "Incorrect JSON format").
# - Exit 1 when a case does not come out as the README documents (the line NOT AS DOCUMENTED says which).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./03.patch_string.sh [NAME]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: NAME.\n%s\n" "$#" "${USAGE}"; exit 2; fi
NAME="${1:-${DEFAULT_NAME}}"
uc_check_name "${NAME}" "${USAGE}"
st_session
uc_init "${NAME}"
uc_need account

uc_case "replace a text that is null: the field exists, so replace works" "${ACCOUNT_URL}" '.notes' 204 '"first note"' \
    '[{"op":"replace","path":"/notes","value":"first note"}]'
uc_case "replace a text that has a value" "${ACCOUNT_URL}" '.contact.email' 204 '"changed@example.com"' \
    '[{"op":"replace","path":"/contact/email","value":"changed@example.com"}]'
uc_case "add: sets the text (here a field that is null)" "${ACCOUNT_URL}" '.contact.phone' 204 '"+359 2 000 0000"' \
    '[{"op":"add","path":"/contact/phone","value":"+359 2 000 0000"}]'
uc_case "remove: the field stays in the answer, now null" "${ACCOUNT_URL}" '.contact.phone' 204 'null' \
    '[{"op":"remove","path":"/contact/phone"}]'
uc_case "a NUMBER sent to a text field is stored as text" "${ACCOUNT_URL}" '.notes' 204 '"5"' \
    '[{"op":"replace","path":"/notes","value":5}]'
uc_case "a LIST sent to a text field is refused, and nothing changes" "${ACCOUNT_URL}" '.notes' 400 '"5"' \
    '[{"op":"replace","path":"/notes","value":["a"]}]'
uc_case "an empty string is stored as null" "${ACCOUNT_URL}" '.notes' 204 'null' \
    '[{"op":"replace","path":"/notes","value":""}]'
uc_done
