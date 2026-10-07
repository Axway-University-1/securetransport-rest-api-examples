#!/bin/bash
# ==============================================================================
# Script Name: 15.files_filepath_PATCH_unshare.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script stops sharing a folder, using the `/files/{filePath}` endpoint
# with PATCH: a JSON Patch document that removes sharedDirectoryProperties.
#
# Usage:
# ./15.files_filepath_PATCH_unshare.sh FOLDER
#
#   FOLDER  the shared folder, relative to the home folder
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - Confirmed directly: a success answers 204, with no body.
# - 14.files_filepath_PATCH_share.sh shares a folder.
# - Requires `jq`, which URL-encodes the path.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

FOLDER="${1#/}"
FOLDER="${FOLDER%/}"
if [ -z "${FOLDER}" ]; then
    printf "Usage: ./15.files_filepath_PATCH_unshare.sh FOLDER\n"
    exit 2
fi
if [ ! -f "${COOKIE}" ]; then
    printf "There is no session. Run 01.Authenticate/01.myself_POST.sh first.\n"
    exit 1
fi

ENCODED=$(printf '%s' "${FOLDER}" | jq -Rr 'split("/") | map(@uri) | join("/")')

printf "Stopping the sharing of %s...\n" "${FOLDER}"
RESPONSE=$(curl -s -k -b "${COOKIE}" -X PATCH "${ST_URL}/files/${ENCODED}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d '[{"op":"remove","path":"/sharedDirectoryProperties"}]' -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf "The unshare failed (HTTP %s):\n%s\n" "${HTTP_CODE}" "${RESPONSE%$'\n'*}"
    exit 1
fi
printf "No longer shared.\n"
