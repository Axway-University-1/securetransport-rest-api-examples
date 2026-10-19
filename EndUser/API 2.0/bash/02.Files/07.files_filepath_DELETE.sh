#!/bin/bash
# ==============================================================================
# Script Name: 07.files_filepath_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-09-29
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes a single file using the `/files/{filepath}` endpoint.
# It demonstrates:
# - Removing a file by name from the account's home folder
# - Checking the HTTP response code (204, no body) before reporting success
#
# Usage:
# ./07.files_filepath_DELETE.sh
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
# - It checks for an active session first and, if there is none, logs in with
#   01.Authenticate/01.myself_POST.sh and then carries on.
# - The file named in FILE_NAME must exist in the account's home folder - run
#   04.files_filepath_POST.sh first if you have not uploaded one yet.
# - Confirmed directly: this call returns 204, and the file is gone from the
#   listing immediately. Deleting an account's file this way does not remove
#   any other file already sitting in the same home folder.
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
source "${ST_ENDUSER_LOCAL_VARIABLES:-${SCRIPT_DIR}/../set_variables.local.sh}" ||
    { echo "Copy set_variables.local.example.sh to set_variables.local.sh and fill it in."; exit 1; }
export ST_URL="${ST_URL:-https://${ST_SERVER}:${ST_PORT}/api/v2.0}"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
source "${SCRIPT_DIR}/../ensure_session.sh"

#
# Set the file name to delete
#
FILE_NAME="test.txt"

#
# Curl command to delete a file on SecureTransport.
#
st_ensure_session
printf "\n\nDeleting file from SecureTransport...\n"
http_status=$(curl -L -b "${COOKIE}" -w "%{http_code}" -s -k -o /dev/null -X DELETE "${ST_URL}/files/${FILE_NAME}" -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT")

if [[ $http_status -ne 204 ]] ; then
        echo "Delete File failure: $http_status"
        exit 1
fi

echo "File ${FILE_NAME} successfully deleted from SecureTransport"
