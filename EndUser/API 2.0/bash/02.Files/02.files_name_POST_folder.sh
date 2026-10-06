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
# - Logging in, and keeping both the session cookie and the csrfToken header
#   the login returns, since a call that changes something needs both
# - Creating a folder: its path goes in the URL, and the body only says that it
#   is a directory
# - Logging out again
#
# Usage:
# ./02.files_name_POST_folder.sh [FOLDER]
#
#   FOLDER  the folder to create, relative to the home folder (default
#           new-folder). A nested path such as reports/2026 works, as long as
#           its parent exists.
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It logs in and out on its own, so 01.Authenticate is not needed first.
# - Do not put the folder's name in the body. The server answers 409.
# - Requires `jq`, which URL-encodes the path and builds the body.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

FOLDER="${1:-new-folder}"
FOLDER="${FOLDER#/}"
# Each part of the path is encoded on its own, so the / between them stays a /
ENCODED_FOLDER=$(printf '%s' "${FOLDER}" | jq -Rr 'split("/") | map(@uri) | join("/")')

COOKIE=$(mktemp)
HEADERS=$(mktemp)

#
# Log in. The csrfToken comes back as a response header.
#
LOGIN_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" -D "${HEADERS}" --cookie-jar "${COOKIE}" \
  -H "Authorization: Basic ${ST_BASIC_AUTH}" -X POST "${ST_URL}/myself" \
  -H "accept: application/json" -H "${REFERER_HEADER}")
CSRF_TOKEN=$(grep -i '^csrfToken:' "${HEADERS}" | awk '{print $2}' | tr -d '\r')
rm -f "${HEADERS}"

if [ "${LOGIN_CODE}" != "200" ]; then
    printf "Login failure: HTTP %s\n" "${LOGIN_CODE}"
    rm -f "${COOKIE}"
    exit 1
fi

printf "Creating the folder '%s'...\n" "${FOLDER}"
BODY=$(jq -n '{isDirectory: true, isRegularFile: false, isSymbolicLink: false, isOther: false, isShared: false}')
curl -s -k -b "${COOKIE}" -X POST "${ST_URL}/files/${ENCODED_FOLDER}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "csrfToken: ${CSRF_TOKEN}" \
  -H "Content-Type: application/json" -w "\nHTTP %{http_code}\n" -d "${BODY}"

#
# Log out, and remove the session
#
curl -s -k -o /dev/null -b "${COOKIE}" -X DELETE "${ST_URL}/myself" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "csrfToken: ${CSRF_TOKEN}"
rm -f "${COOKIE}"
