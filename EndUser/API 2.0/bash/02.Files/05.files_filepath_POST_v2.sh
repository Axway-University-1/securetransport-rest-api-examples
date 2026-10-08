#!/bin/bash
# ==============================================================================
# Script Name: 05.files_filepath_POST_v2.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script uploads a number of files using the `/files` endpoint.
# It demonstrates repeating an upload in a loop, which is useful for generating
# test traffic.
#
# Usage:
# ./05.files_filepath_POST_v2.sh <NUMBER_OF_FILES>
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - Each copy is removed again after it has been uploaded.
# - Exits 2 without a whole number, and 1 at the first upload the server refuses.
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
NUMBER_OF_FILES=$1

if ! [[ "${NUMBER_OF_FILES}" =~ ^[1-9][0-9]*$ ]] ; then
        echo "Please provide the number of files to upload, a whole number above 0."
        exit 2
fi

#
# Set the file name to upload
#
FILE_NAME="${SCRIPT_DIR}/test.txt"
printf "Pushing ${NUMBER_OF_FILES} of files...\n"

for i in $(seq 1 "${NUMBER_OF_FILES}") ; do
    
    # Copy the file to a new file with a different name.
    cp "${FILE_NAME}" "${FILE_NAME}_${i}"
    
    # Curl command to push a file to SecureTransport.
    http_status=$(curl -b "${COOKIE}" -o /dev/null -w "%{http_code}" -s -k -X POST "${ST_URL}/files" -H "Content-Type: multipart/form-data" -F "file=@${FILE_NAME}_${i}" -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT")
    # the copy goes whatever the answer was
    rm -f "${FILE_NAME}_${i}"
    if [[ $http_status -lt 200 || $http_status -ge 300 ]] ; then
        echo "Upload failure for test.txt_${i}: $http_status"
        exit 1
    fi
    echo "Uploaded test.txt_${i} (HTTP ${http_status})"
done