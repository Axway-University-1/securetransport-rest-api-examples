#!/bin/bash
# ==============================================================================
# Script Name: 05.myself_addressBook_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Who can I send to? GET /myself/addressBook lists the groups and users the account can see. The list is long, so this narrows it with jq: how many of each type, and just the users with an e-mail.
#
# Usage:
# ./05.myself_addressBook_GET.sh
#
# Risk: read
#
# Notes:
# - Copied from EndUser/API 2.0/bash/03.Myself/08.myself_addressBook_GET.sh, with jq added.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/myself/addressBook" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "HTTP ${code}"
[[ "${code}" == 200 ]] || exit 1
BOOK="${result%???}"
echo "Entries: $(echo "${BOOK}" | jq 'length')"
echo "By type:"
echo "${BOOK}" | jq -r 'group_by(.type)[] | "  \(.[0].type): \(length)"'
echo "Users with an e-mail (first 5):"
echo "${BOOK}" | jq -r '[.[] | select(.type == "User" and .mail != "")] | .[:5][] | "  \(.displayName)  <\(.mail)>"' 
