#!/bin/bash
# ==============================================================================
# Script Name: 04.addressBook_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Lists, step 4: the small lists. GET /myself/addressBook and GET /secretQuestions answer a plain array, like /transfers, and have no count. The address book takes limit and offset. The list of secret questions takes no limit:
# it answers with all of them whatever you ask for. The script shows both. It only reads.
#
# Usage:
# ./04.addressBook_GET.sh
#
# Risk: read
#
# Notes:
# - Copied from EndUser/API 2.0/bash/03.Myself/08.myself_addressBook_GET.sh and 07.SecretQuestions/01.secretQuestions_GET.sh.
# - A list that ignores limit is not an error: there is nothing in the answer that tells you. Count what comes back and do not trust the limit you sent.
# - The entries of the address book are groups and people (type); on the lab the address book of a new account is its sources, such as Local and LDAP.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./04.addressBook_GET.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
st_session

eu_count() { printf '%s' "${EU_BODY}" | jq -r 'if type == "array" then length else "not a list" end' 2>/dev/null; }

eu_get "myself/addressBook"
echo "GET /myself/addressBook: HTTP ${EU_CODE}"
[ "${EU_CODE}" = "200" ] || { eu_why; exit 1; }
[ "$(eu_count)" != "not a list" ] || { echo "The answer is not a plain array."; exit 1; }
ALL=$(eu_count)
echo "A plain array of ${ALL} entries, no count: $(printf '%s' "${EU_BODY}" | jq -r '[.[] | "\(.displayName) (\(.type))"] | join(", ")')"

eu_get "myself/addressBook" "limit=1"
echo "limit=1: HTTP ${EU_CODE}, $(eu_count) entries: the address book takes a limit."
[ "${EU_CODE}" = "200" ] || { eu_why; exit 1; }
[ "$(eu_count)" = "1" ] || [ "${ALL}" = "0" ] || { echo "limit=1 was expected to give one entry."; exit 1; }

eu_get "myself/addressBook" "limit=1" "offset=1"
echo "limit=1&offset=1: HTTP ${EU_CODE}, $(eu_count) entries, the first is $(printf '%s' "${EU_BODY}" | jq -r '.[0].displayName // "-"')."
[ "${EU_CODE}" = "200" ] || { eu_why; exit 1; }

eu_get "secretQuestions"
echo "GET /secretQuestions: HTTP ${EU_CODE}"
[ "${EU_CODE}" = "200" ] || { eu_why; exit 1; }
[ "$(eu_count)" != "not a list" ] || { echo "The answer is not a plain array."; exit 1; }
QUESTIONS=$(eu_count)
echo "A plain array of ${QUESTIONS} questions, as text."
eu_get "secretQuestions" "limit=2"
echo "limit=2: HTTP ${EU_CODE}, $(eu_count) entries. This list takes no limit."
[ "${EU_CODE}" = "200" ] || { eu_why; exit 1; }
[ "$(eu_count)" = "${QUESTIONS}" ] || echo "(It gave ${QUESTIONS} before, so this release does honour a limit here.)"
