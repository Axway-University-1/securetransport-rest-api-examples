#!/bin/bash
# ==============================================================================
# Script Name: 02.myself_GET_narrowed.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# The same answer, narrowed with jq. The server sends the whole object, and /myself ignores a fields= query, so the narrowing is done on this side: one value, a few, or the names of all of them.
#
# Usage:
# ./02.myself_GET_narrowed.sh
#
# Risk: read
#
# Notes:
# - Copied from EndUser/API 2.0/bash/03.Myself/01.myself_GET.sh, with jq added.
# - jq -r prints a text value without its quotes, which is what a script wants to put in a variable.
# - A field the account has no value for is null: // "none" gives a readable default.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

ME=$(curl -k -s -b "${JAR}" -X GET "${ST_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}")
[ -n "${ME}" ] && echo "${ME}" | jq -e . >/dev/null 2>&1 || { echo "No JSON came back."; exit 1; }

echo "One value:        $(echo "${ME}" | jq -r .name)"
echo "A few, as JSON:   $(echo "${ME}" | jq -c '{name, type, uid, gid}')"
echo "With a default:   language = $(echo "${ME}" | jq -r '.language // "none"')"
echo "A nested value:   e-mail = $(echo "${ME}" | jq -r '.contact.email // "none"')"
echo "Every field name: $(echo "${ME}" | jq -r 'keys | join(", ")')"

# Does the server narrow it? Ask for one field, and count what comes back
ALL=$(echo "${ME}" | jq 'keys | length')
ASKED=$(curl -k -s -b "${JAR}" -X GET "${ST_URL}/myself?fields=name" -H "accept: application/json" -H "Referer: ${REFERER}" | jq 'keys | length')
echo "Fields in the whole answer: ${ALL}; with ?fields=name: ${ASKED}"
[ "${ALL}" = "${ASKED}" ] && echo "So /myself ignores fields=: narrow with jq."
