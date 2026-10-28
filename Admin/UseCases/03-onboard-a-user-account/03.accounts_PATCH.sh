#!/bin/bash
# ==============================================================================
# Script Name: 03.accounts_PATCH.sh
# Author: Plamen Milenkov
# Created: 2026-10-28
# Location: Sofia
# ==============================================================================
# Description:
# Onboarding, step 3: change one thing. PATCH /accounts/{name} with a JSON Patch that replaces /contact/email, then a read to see that it changed. A PATCH changes only what it names.
#
# Usage:
# ./03.accounts_PATCH.sh [NAME] [EMAIL]
#
#   NAME   the account to change (default example_onboard)
#   EMAIL  the new email address (default NAME_changed@example.com)
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/05.Accounts/06.accounts_name_PATCH.sh. Features/Guidance/changing-configuration.md explains what replace, add and remove do.
# - `replace` needs the field to exist (the account has an email from step 01). A write in a session carries the csrfToken header.
# - Exit 1 when the server refuses, or when the address is not the new one afterwards.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./03.accounts_PATCH.sh [NAME] [EMAIL]"
if [ "$#" -gt 2 ]; then printf "%s parameters were given, and at most 2 are taken: NAME and EMAIL.\n%s\n" "$#" "${USAGE}"; exit 2; fi
NAME="${1:-${DEFAULT_NAME}}"
EMAIL="${2:-${NAME}_changed@example.com}"
uc_check_name "${NAME}" "${USAGE}"
st_session

NAME_URI=$(printf '%s' "${NAME}" | jq -Rr @uri)
read_email() { curl -k -s -b "${JAR}" -X GET "${ST_URL}/accounts/${NAME_URI}" -H "accept: application/json" -H "Referer: ${REFERER}" | jq -r '.contact.email // "none"'; }
BEFORE=$(read_email)
echo "The email address of ${NAME} is ${BEFORE}."
BODY=$(jq -cn --arg email "${EMAIL}" '[{op: "replace", path: "/contact/email", value: $email}]')
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X PATCH "${ST_URL}/accounts/${NAME_URI}" -H "accept: application/json" -H "Referer: ${REFERER}" \
       -H "Content-Type: application/json" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)" -d "${BODY}")
echo "PATCH: HTTP ${code}"
[ "${code}" = "204" ] || { echo "The server did not accept the change. The address was not changed."; exit 1; }
AFTER=$(read_email)
if [ "${AFTER}" = "${EMAIL}" ]; then
    echo "Read back: ${AFTER}. Changed, and nothing else was touched."
else
    echo "Read back: ${AFTER}, not ${EMAIL}: the change did not take."
    exit 1
fi
