#!/bin/bash
# ==============================================================================
# Script Name: 02.no_credentials_GET_myself.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# The same call with no credentials and no session. The server refuses it with 401: nothing but an authenticated call gets an answer.
#
# Usage:
# ./02.no_credentials_GET_myself.sh
#
# Risk: read
#
# Notes:
# - It sends no password at all, so it cannot lock the administrator. A wrong password is not shown here for that reason: repeated failures can lock the account.
# - The script succeeds (exit 0) when the server answers 401, and fails when it answers anything else.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"

code=$(curl -k -s -o /dev/null -w "%{http_code}" -X GET "${ST_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "HTTP ${code}"
if [[ "${code}" == 401 ]]; then
    echo "Refused, as expected: a call needs credentials or a session."
else
    echo "Expected 401."
    exit 1
fi
