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
# ./03.files_filepath_GET.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - The file named in FILE_NAME must exist in the account's home folder.
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
# Copy config.example to config and set the values for your own environment.
#
printf "Loading variables into our context..."
source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"

# 
# Curl command to pull a file from SecureTransport.
# It is assumed a session login took place prior to this via 01.Authenticate/stLogin.sh
# Session cookies are read from a file called myCookie.jar
#

# 
# Set the file name to download
#
FILE_NAME="download_file.txt"

#
# Curl command to pull a file from SecureTransport.
#
printf "\n\nPulling file from SecureTransport...\n"
http_status=$(curl -L -b "${COOKIE}" -w "%{http_code}" -s -k -o "${FILE_NAME}" -X GET "${ST_URL}/files/${FILE_NAME}" -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT")

if [[ $http_status -ne 200 ]] ; then
        echo "Get File failure: $http_status"
        cat "${FILE_NAME}"
        rm -f "${FILE_NAME}"
        exit
fi

echo "File successfully retrieved and saved as ${FILE_NAME}"