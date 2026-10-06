#!/bin/bash
# ==============================================================================
# Script Name: 09.myself_addressBook_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script searches the address book, the people and groups the user can
# share folders with, using the `/myself/addressBook` endpoint. It demonstrates:
# - A wildcard search over the name, the email and the group (searchFor)
# - Keeping to users only (type=USER), sorted by email, a page at a time
#
# Usage:
# ./09.myself_addressBook_GET.sh [SEARCH [LIMIT]]
#
#   SEARCH  what to look for, for example jo* (default: everything)
#   LIMIT   how many entries to return (default 20)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - The answer is a plain JSON array, not a {result: [...]} envelope.
# - With an LDAP address book, the wildcard only works at the end of the search.
#   The minimum search length is in the account's addressBookSettings (see
#   01.myself_GET.sh).
# - The exact-match filters displayName, mail and parentGroup are case
#   sensitive; searchFor is not.
# - Requires `jq`, which prints one entry per line.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

SEARCH="$1"
LIMIT="${2:-20}"
if [ ! -f "${COOKIE}" ]; then
    printf "There is no session. Run 01.Authenticate/01.myself_POST.sh first.\n"
    exit 1
fi

# Only add searchFor when there is something to search for
SEARCH_FILTER=()
[ -n "${SEARCH}" ] && SEARCH_FILTER=(--data-urlencode "searchFor=${SEARCH}")

printf "The address book%s: id, type, name, email\n" "${SEARCH:+, searching for ${SEARCH}}"
RESPONSE=$(curl -s -k -G -b "${COOKIE}" -X GET "${ST_URL}/myself/addressBook" \
  "${SEARCH_FILTER[@]}" --data-urlencode "type=USER" --data-urlencode "orderBy=email" \
  --data-urlencode "limit=${LIMIT}" --data-urlencode "offset=0" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"

if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the address book (HTTP %s):\n%s\n" "${HTTP_CODE}" "${BODY}"
    exit 1
fi
printf '%s' "${BODY}" | jq -r '.[] | "  \(.id)  \(.type)  \(.displayName)  \(.mail)"'
printf "%s entr(ies).\n" "$(printf '%s' "${BODY}" | jq 'length')"
