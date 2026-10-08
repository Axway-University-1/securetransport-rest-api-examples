#!/bin/bash
# ==============================================================================
# Script Name: 04.files_filepath_POST.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script uploads a single file using the `/files` endpoint.
# It demonstrates a multipart form upload with curl.
#
# Usage:
# ./04.files_filepath_POST.sh [FILE_NAME]
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - FILE_NAME is a file next to this script (default test.txt). A temporary copy
#   of it with one more line is what is uploaded, under the same name, so the
#   file in the repository is never changed. An earlier version appended the line
#   to the file itself, a little more at every run.
# - Exits 2 for a file that is not there, 1 when the server refuses.
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

#
# Set the file name to upload
#
FILE_NAME="${1:-test.txt}"
if [[ "${FILE_NAME}" == */* ]] || [ ! -f "${SCRIPT_DIR}/${FILE_NAME}" ]; then
    printf "\nThere is no file named %s next to this script.\n" "${FILE_NAME}"
    exit 2
fi
TEMP_FILE=$(mktemp)
trap 'rm -f "${TEMP_FILE}"' EXIT
cp "${SCRIPT_DIR}/${FILE_NAME}" "${TEMP_FILE}"
echo "Append to the file" >> "${TEMP_FILE}"

#
# Curl command to push a file to SecureTransport, under the name of the original.
#
result=$(curl -b "${COOKIE}" -w "\n%{http_code}" -s -k -X POST "${ST_URL}/files" -H "Content-Type: multipart/form-data" -F "file=@${TEMP_FILE};filename=${FILE_NAME}" -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT")
http_status=${result##*$'\n'}
printf '%s\n' "${result%$'\n'*}"
if [[ $http_status -lt 200 || $http_status -ge 300 ]] ; then
    printf "Upload failure: %s\n" "${http_status}"
    exit 1
fi
printf "File %s uploaded (HTTP %s)\n" "${FILE_NAME}" "${http_status}"