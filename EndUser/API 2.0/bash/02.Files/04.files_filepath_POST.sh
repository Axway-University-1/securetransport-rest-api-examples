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
# ./04.files_filepath_POST.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
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
# Set the file name to upload
#
FILE_NAME="test.txt"
echo "Append to the file" >> "${FILE_NAME}"

#
# Curl command to push a file to SecureTransport.
#
curl -b "${COOKIE}" -s -k -X POST "${ST_URL}/files" -H "Content-Type: multipart/form-data" -F "file=@${FILE_NAME}" -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT"