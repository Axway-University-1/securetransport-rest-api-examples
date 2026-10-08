#!/bin/bash
# ==============================================================================
# Script Name: 03.files_filepath_GET.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script downloads a single file using the `/files/{filepath}` endpoint.
# It demonstrates:
# - Requesting a file by name
# - Checking the HTTP response code before writing the result
#
# Usage:
# ./03.files_filepath_GET.sh [FILE_NAME]
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - The file named in FILE_NAME (default test.txt, the one 04 uploads) must exist
#   in the account's home folder. It is saved as downloaded_files/<FILE_NAME>, a
#   folder git ignores, so it can never overwrite a file of these examples.
# - Exits 1 when the server refuses.
# - The body is written straight to disk with curl's own -o, and the status
#   code captured separately with -w. Capturing both into one shell variable
#   and writing that to the file - as an earlier version of this script did -
#   silently appends the status code's digits to the end of every downloaded
#   file's content.
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
# Curl command to pull a file from SecureTransport.
# It is assumed a session login took place prior to this via 01.Authenticate/01.myself_POST.sh
# Session cookies are read from a file called myCookie.jar
#

# 
# Set the file name to download
#
FILE_NAME="${1:-test.txt}"
LOCAL_FILE="${SCRIPT_DIR}/downloaded_files/$(basename "${FILE_NAME}")"
mkdir -p "$(dirname "${LOCAL_FILE}")"

# Each part of the path is encoded on its own, so the / between them stays a /
ENCODED_NAME=$(printf '%s' "${FILE_NAME#/}" | jq -Rr 'split("/") | map(@uri) | join("/")')

#
# Curl command to pull a file from SecureTransport.
#
printf "\n\nPulling file from SecureTransport...\n"
http_status=$(curl -L -b "${COOKIE}" -w "%{http_code}" -s -k -o "${LOCAL_FILE}" -X GET "${ST_URL}/files/${ENCODED_NAME}" -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT")

if [[ $http_status -ne 200 ]] ; then
        echo "Get File failure: $http_status"
        cat "${LOCAL_FILE}"
        rm -f "${LOCAL_FILE}"
        exit 1
fi

echo "File successfully retrieved and saved as ${LOCAL_FILE}"