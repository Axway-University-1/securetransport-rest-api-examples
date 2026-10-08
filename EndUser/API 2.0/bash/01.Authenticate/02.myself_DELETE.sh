#!/bin/bash
# ==============================================================================
# Script Name: 02.myself_DELETE.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script logs out of the EndUser API using the `/myself` endpoint.
# It demonstrates ending the session created by 01.myself_POST.sh: the session
# cookie in the cookie jar is what is sent, so it is that session that ends.
#
# Usage:
# ./02.myself_DELETE.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - ST requires a Referer header on these calls.
# - Confirmed directly: a DELETE with the session cookie alone answers 200 and the
#   cookie is refused afterwards (401). An earlier version of this script sent
#   Basic authentication and no cookie; that logs out a brand new session and
#   leaves the one in the jar open, whatever the script printed.
# - Exits 1 with no session in the jar, or when the server refuses. The jar is
#   removed once the session has ended.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# 
# First we will load the variables into our context.
# Put the values for your own environment in set_variables.local.sh.
#
printf "Loading variables into our context..."
source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"

if [ ! -f "${COOKIE}" ]; then
    printf "\nThere is no session. Run 01.myself_POST.sh first.\n"
    exit 1
fi

result=$(curl -b "${COOKIE}" -w "%{http_code}" -k -s -X DELETE "${ST_URL}/myself" -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT")
http_status=${result: -3}

if [[ $http_status -ne 200 ]] ; then
        echo "Logout failure: $http_status"
        exit 1
fi
# The last 3 characters of $result are the status code -w appended, not part
# of the response body, so they are trimmed before printing it.
echo "${result%???}"
rm -f "${COOKIE}"
echo "Successfully Logged out of SecureTransport"