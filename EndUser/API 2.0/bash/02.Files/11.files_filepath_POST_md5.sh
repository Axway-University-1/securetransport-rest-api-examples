#!/bin/bash
# ==============================================================================
# Script Name: 11.files_filepath_POST_md5.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script uploads a file into a folder, and has the server check it arrived
# intact, using the `/files/{filePath}` endpoint. It demonstrates:
# - A multipart upload into a folder: the folder goes in the URL
# - The Content-MD5 header: the file's MD5 checksum, base64 encoded, which the
#   server compares with what it received
# - The transferMode query parameter, BINARY or ASCII
#
# Usage:
# ./11.files_filepath_POST_md5.sh LOCAL_FILE [FOLDER [TRANSFER_MODE]]
#
#   LOCAL_FILE     the file to upload
#   FOLDER         the folder to put it in, relative to the home folder (default:
#                  the home folder). It must exist: see 02.files_name_POST_folder.sh.
#   TRANSFER_MODE  BINARY (default) or ASCII
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - Confirmed directly: a correct checksum answers 201. A wrong one answers a
#   bare 500 "Error while uploading file", and File Tracking logs the upload
#   as Failed.
# - The checksum is computed with openssl, on macOS and Linux alike.
# - Requires `jq`, which URL-encodes the folder, and `openssl`.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

LOCAL_FILE="$1"
FOLDER="${2:-}"
FOLDER="${FOLDER#/}"
FOLDER="${FOLDER%/}"
TRANSFER_MODE="${3:-BINARY}"
if [ -z "${LOCAL_FILE}" ] || [ ! -f "${LOCAL_FILE}" ]; then
    printf "Usage: ./11.files_filepath_POST_md5.sh LOCAL_FILE [FOLDER [TRANSFER_MODE]]\n"
    exit 2
fi
if [ ! -f "${COOKIE}" ]; then
    printf "There is no session. Run 01.Authenticate/01.myself_POST.sh first.\n"
    exit 1
fi

# The MD5 checksum of the file, as base64 of the 16 raw bytes
MD5=$(openssl dgst -md5 -binary "${LOCAL_FILE}" | openssl base64)

if [ -z "${FOLDER}" ]; then
    URL="${ST_URL}/files"
else
    URL="${ST_URL}/files/$(printf '%s' "${FOLDER}" | jq -Rr 'split("/") | map(@uri) | join("/")')"
fi

printf "Uploading %s to /%s, MD5 %s...\n" "$(basename "${LOCAL_FILE}")" "${FOLDER}" "${MD5}"
RESPONSE=$(curl -s -k -b "${COOKIE}" -X POST "${URL}?transferMode=${TRANSFER_MODE}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-MD5: ${MD5}" \
  -F "file=@${LOCAL_FILE}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"

if [ "${HTTP_CODE}" != "201" ]; then
    printf "The upload failed (HTTP %s). A wrong checksum also answers 500:\n%s\n" "${HTTP_CODE}" "${BODY}"
    exit 1
fi
printf "Uploaded, and the server's checksum matched.\n"
