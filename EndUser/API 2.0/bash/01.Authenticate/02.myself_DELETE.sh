#!/bin/bash
# ==============================================================================
# Script Name: 02.myself_DELETE.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script logs out of the EndUser API using the `/myself` endpoint.
# It demonstrates ending the session created by 01.myself_POST.sh.
#
# Usage:
# ./02.myself_DELETE.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
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

result=$(curl -H "Authorization: Basic ${ST_BASIC_AUTH}" --cookie-jar "${COOKIE}" -w "%{http_code}" -k -s -X DELETE "${ST_URL}/myself" -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT")
http_status=${result: -3}

if [[ $http_status -ne 200 ]] ; then
        echo "Logout failure: $http_status"
        exit
fi
# The last 3 characters of $result are the status code -w appended, not part
# of the response body, so they are trimmed before printing it.
echo "${result:0:-3}"
echo "Successfully Logged out of SecureTransport"