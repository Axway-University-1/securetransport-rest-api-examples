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
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
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
# Copy config.example to config and set the values for your own environment.
#
printf "Loading variables into our context..."
source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"

#
# Set the file name to delete
#
FILE_NAME="test.txt"

#
# Curl command to delete a file on SecureTransport.
#
printf "\n\nDeleting file from SecureTransport...\n"
http_status=$(curl -L -b "${COOKIE}" -w "%{http_code}" -s -k -o /dev/null -X DELETE "${ST_URL}/files/${FILE_NAME}" -H "accept: application/json" -H "Referer: Ian")

if [[ $http_status -ne 204 ]] ; then
        echo "Delete File failure: $http_status"
        exit
fi

echo "File ${FILE_NAME} successfully deleted from SecureTransport"
