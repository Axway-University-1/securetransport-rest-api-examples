#!/bin/bash
# ==============================================================================
# Script Name: 01.myself_POST.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script logs in to the EndUser API using the `/myself` endpoint.
# It demonstrates:
# - Basic authentication with the derived ST_BASIC_AUTH value
# - Storing the session in a cookie jar for reuse by the other examples
# - Checking the HTTP response code before continuing
#
# Usage:
# ./01.myself_POST.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The cookie jar is written next to the examples as myCookie.jar, and the
#   file examples read it. Run this script before them.
# - See 02.myself_DELETE.sh for logging out.
# - ST requires a Referer header on these calls.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# 
# First we will load the variables into our context.
# Copy config.example to config and set the values for your own environment.
#
printf "Loading variables into our context..."
source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
rm -f "${COOKIE}"

#
# We will start with the basic authentication. 
# This is a simple combination of username and password.
# The server will check if the provided credentials are correct.
# If they are, the server will respond with the requested data.
# If not, the server will respond with an error message.
# Check 02.myself_DELETE.sh for log out.
# 
printf "\n\nBasic authentication...\n"
result=$(curl -H "Authorization: Basic ${ST_BASIC_AUTH}" --cookie-jar "${COOKIE}" -w "%{http_code}" -k -s -X POST "${ST_URL}/myself" -H "accept: application/json" -H "Referer: Ian")
http_status=${result: -3}

if [[ $http_status -ne 200 ]] ; then
        echo "Login failure: $http_status"
        exit
fi
# The last 3 characters of $result are the status code -w appended, not part
# of the response body, so they are trimmed before printing it.
echo "${result:0:-3}"
echo "Successfully Authenticated to SecureTransport"

#
# Then we will see the same request, but with the cookie jar.
# The cookie jar is a file that stores the session information.
# This way, we can make multiple requests without the need to authenticate every time.
#
# printf "\n\nBasic authentication with cookie jar to reduce further authentications...\n"
# REFERER_HEADER="Referer: Ian"
# curl -k --cookie "${COOKIE}" -X GET "${ST_URL}/myself" -H "accept: application/json" -H "${REFERER_HEADER}"