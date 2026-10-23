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
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
# - It checks for an active session first and, if there is none, logs in with
#   01.Authenticate/01.myself_POST.sh and then carries on.
# - Confirmed directly: a correct checksum answers 201. A wrong one answers a
#   bare 500 "Error while uploading file", and File Tracking logs the upload
#   as Failed.
# - The checksum is computed with openssl, on macOS and Linux alike.
# - A parameter that is wrong is named, with what it was and what it should be, before the usage is printed (exit 2, nothing is sent): too many parameters, a
#   LOCAL_FILE that is not a file on this machine (it is looked for from the folder you run the script in), a TRANSFER_MODE that is not BINARY or ASCII (in any case).
# - Requires `jq`, which URL-encodes the folder, and `openssl`.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${ST_ENDUSER_LOCAL_VARIABLES:-${SCRIPT_DIR}/../set_variables.local.sh}" ||
    { echo "Copy set_variables.local.example.sh to set_variables.local.sh and fill it in."; exit 1; }
export ST_URL="${ST_URL:-https://${ST_SERVER}:${ST_PORT}/api/v2.0}"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
source "${SCRIPT_DIR}/../ensure_session.sh"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

# usage PROBLEM: says what is wrong with the parameters, then what they are, and stops (exit 2, nothing sent)
usage() {
    printf "Problem: %s\n\n" "$1"
    printf "Usage: ./11.files_filepath_POST_md5.sh LOCAL_FILE [FOLDER [TRANSFER_MODE]]\n"
    printf "  LOCAL_FILE     the file to upload: a path on this machine, absolute or relative to %s\n" "$(pwd)"
    printf "  FOLDER         the folder to put it in, on the server, relative to the home folder (default: the home folder)\n"
    printf "  TRANSFER_MODE  BINARY (default) or ASCII. It can be given only after FOLDER: use \"\" for the home folder\n"
    printf "For example: ./11.files_filepath_POST_md5.sh report.txt reports ASCII\n"
    exit 2
}

if [ "$#" -gt 3 ]; then
    usage "$# parameters were given ($*), and at most 3 are taken: LOCAL_FILE, FOLDER and TRANSFER_MODE, in that order. Is one of them extra?"
fi
LOCAL_FILE="$1"
FOLDER="${2:-}"
FOLDER="${FOLDER#/}"
FOLDER="${FOLDER%/}"
TRANSFER_MODE=$(printf '%s' "${3:-BINARY}" | tr '[:lower:]' '[:upper:]')
if [ -z "${LOCAL_FILE}" ]; then
    usage "LOCAL_FILE, the first parameter, is missing."
fi
if [ ! -f "${LOCAL_FILE}" ]; then
    usage "LOCAL_FILE, the first parameter, is '${LOCAL_FILE}', and there is no such file on this machine (looked in $(pwd))."
fi
if [ "${TRANSFER_MODE}" != "BINARY" ] && [ "${TRANSFER_MODE}" != "ASCII" ]; then
    usage "TRANSFER_MODE, the third parameter, is '${3}': it must be BINARY or ASCII. (The second parameter is the FOLDER, '${2:-}'.)"
fi
st_ensure_session

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
    printf "If the checksum is right, run it again: the server now and then answers 500 for an upload that works the next time.\n"
    exit 1
fi
printf "Uploaded, and the server's checksum matched.\n"
