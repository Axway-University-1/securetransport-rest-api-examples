#!/bin/bash
# ==============================================================================
# Script Name: 01.sharing_GET_myself.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# May this account share folders? GET /myself says so in sharingAllowed. It is true only for an account that has an e-mail address: without one, a share is refused with a 400 that says "Shared folders functionality is disabled", which sounds like a server setting and is not.
#
# Usage:
# ./01.sharing_GET_myself.sh
#
# Risk: read
#
# Notes:
# - Copied from EndUser/API 2.0/bash/03.Myself/01.myself_GET.sh, narrowed to the two fields that matter here.
# - Exit 0 when sharing is allowed, 3 when it is not (an administrator sets the e-mail address of the account).
# - A session keeps the answer it started with. After an administrator sets the address, end the session (./99.cleanup_DELETE.sh) and log in again, or this still says false (confirmed on the lab: the same session answered false, a new one true).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "HTTP ${code}"
[[ "${code}" == 200 ]] || exit 1
allowed=$(echo "${result%???}" | jq -r '.sharingAllowed')
email=$(echo "${result%???}" | jq -r '.contact.email // ""')
echo "sharingAllowed: ${allowed}; e-mail address of the account: ${email:-none}"
if [ "${allowed}" != "true" ]; then
    echo "This account may not share folders: it has no e-mail address. Ask an administrator to set one."
    st_session_note
    exit 3
fi
