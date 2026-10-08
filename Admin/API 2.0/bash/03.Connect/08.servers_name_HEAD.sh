#!/bin/bash
# ==============================================================================
# Script Name: 08.servers_name_HEAD.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script checks whether a specific server exists using the HTTP HEAD method.
# It uses curl's `--head` option to retrieve only the response headers.
# A 200 response code indicates the server exists; 400 or 404 means it does not (see Notes).
#
# Usage:
# ./08.servers_name_HEAD.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - HEAD requests are efficient for existence checks without retrieving full content.
# - Confirmed directly: the lab answers a HEAD of a server that does not exist with 400 and no body (a HEAD never has one),
#   not the 404 the reference leads one to expect; a GET of the same name (09.servers_name_GET.sh) is a 404 with an HTML page.
#   So the script reads the code from the answer: 200 is "Server exists.", 400 or 404 is "Server does not exist." and any
#   other code (401, 500) is "Could not check the server." - each with the status, and exit 1 for the last two.
# - Exit codes: 0 when the server exists, 1 when it does not or the check could not be made.
# ==============================================================================

echo "Loading variables into our context..."
#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

NAME="SSH_TEST_SERVER_1"

# Perform HEAD request
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" --head "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers/${NAME}" -H "accept: */*" -H "${REFERER_HEADER}"

# Check response code
RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}\n" -k -u "${ST_USER}:${ST_PASSWORD}" --head "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers/${NAME}" -H "accept: */*" -H "${REFERER_HEADER}")
case "${RESPONSE_CODE}" in
  200)
    echo "Server exists."
    ;;
  400|404)
    printf "Server does not exist. HTTP %s\n" "${RESPONSE_CODE}"
    exit 1
    ;;
  *)
    printf "Could not check the server. HTTP %s\n" "${RESPONSE_CODE}"
    exit 1
    ;;
esac
