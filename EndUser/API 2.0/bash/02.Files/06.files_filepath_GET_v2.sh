#!/bin/bash
# ==============================================================================
# Script Name: 06.files_filepath_GET_v2.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script downloads a number of files using the `/files/{filepath}`
# endpoint. It is the counterpart of 05.files_filepath_POST_v2.sh and downloads
# the files that script uploaded.
#
# Usage:
# ./06.files_filepath_GET_v2.sh <NUMBER_OF_FILES>
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - Run 05.files_filepath_POST_v2.sh first, so that the files exist.
# - Exits 2 without a whole number, and 1 at the first download the server refuses.
# - The body is written straight to disk with curl's own -o, and the status
#   code captured separately with -w. Capturing both into one shell variable
#   and writing that to the file - as an earlier version of this script did -
#   silently appended the status code's digits to the end of every
#   downloaded file's content.
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
        echo "Please provide the number of files to download, a whole number above 0."
        exit 2
fi

# 
# Set the file name to download
#
FILE_NAME_BASE="test.txt"
DOWNLOAD_FOLDER="downloaded_files"


mkdir -p "${DOWNLOAD_FOLDER}"

for i in $(seq 1 "${NUMBER_OF_FILES}") ; do
        FILE_NAME="${FILE_NAME_BASE}_${i}"
        http_status=$(curl -L -b "${COOKIE}" -w "%{http_code}" -s -k -o "${DOWNLOAD_FOLDER}/${FILE_NAME}" -X GET "${ST_URL}/files/${FILE_NAME}" -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT")

        if [[ $http_status -ne 200 ]] ; then
                echo "Get File failure: $http_status"
                cat "${DOWNLOAD_FOLDER}/${FILE_NAME}"
                rm -f "${DOWNLOAD_FOLDER}/${FILE_NAME}"
                exit 1
        fi

        echo "File successfully retrieved and saved as ${DOWNLOAD_FOLDER}/${FILE_NAME}"
        
        # Remove the file if you don't need it to keep the system clean.
        rm -f "${DOWNLOAD_FOLDER}/${FILE_NAME}"
done

echo "Files successfully retrieved and saved in ${DOWNLOAD_FOLDER}"