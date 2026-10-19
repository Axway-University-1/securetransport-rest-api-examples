#!/bin/bash
# ==============================================================================
# Script Name: 02.files_name_POST_folder.sh
# Author: Plamen Milenkov
# Created: 2026-10-05
# Location: Sofia
# ==============================================================================
# Description:
# This script creates a folder in the home folder of the user, using the
# `/files/{name}` endpoint. It demonstrates:
# - Checking first whether the folder is there, since creating one that exists
#   is answered 409 with a message that says nothing
# - Creating a folder: its path goes in the URL, and the body only says that it
#   is a directory
#
# Usage:
# ./02.files_name_POST_folder.sh [FOLDER]
#
#   FOLDER  the folder to create, relative to the home folder (default
#           new-folder). A nested path such as reports/2026 works, as long as
#           its parent exists.
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
# - It checks for an active session first and, if there is none, logs in with
#   01.Authenticate/01.myself_POST.sh and then carries on.
# - Do not put the folder's name in the body. The server answers 409.
# - Requires `jq`, which URL-encodes the path and builds the body.
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

FOLDER="${1:-new-folder}"
FOLDER="${FOLDER#/}"
# Each part of the path is encoded on its own, so the / between them stays a /
ENCODED_FOLDER=$(printf '%s' "${FOLDER}" | jq -Rr 'split("/") | map(@uri) | join("/")')
st_ensure_session

# A folder that is already there is answered 409 "Error occurred while creating file: null",
# which says nothing: look first, and say it plainly
if [ "$(curl -s -k -o /dev/null -w "%{http_code}" -b "${COOKIE}" -G "${ST_URL}/files/${ENCODED_FOLDER}" --data-urlencode "metadata=true" \
        -H "accept: application/json" -H "${REFERER_HEADER}")" = "200" ]; then
    printf "The folder '%s' already exists. Nothing to create.\n" "${FOLDER}"
    exit 0
fi

printf "Creating the folder '%s'...\n" "${FOLDER}"
BODY=$(jq -n '{isDirectory: true, isRegularFile: false, isSymbolicLink: false, isOther: false, isShared: false}')
RESPONSE=$(curl -s -k -b "${COOKIE}" -X POST "${ST_URL}/files/${ENCODED_FOLDER}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -w "\nHTTP %{http_code}\n" -d "${BODY}")
printf '%s\n' "${RESPONSE}"
CREATE_CODE=$(printf '%s\n' "${RESPONSE}" | tail -n 1 | awk '{print $2}')
[[ "${CREATE_CODE}" == 20* ]] || exit 1
