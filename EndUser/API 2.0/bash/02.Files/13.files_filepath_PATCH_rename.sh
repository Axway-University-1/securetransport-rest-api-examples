#!/bin/bash
# ==============================================================================
# Script Name: 13.files_filepath_PATCH_rename.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script renames or moves a file or folder, using the `/files/{filePath}`
# endpoint with PATCH: a JSON Patch document that adds a newFilePath. Unlike
# PUT (12.files_filepath_PUT_rename.sh), it changes only what it names.
#
# Usage:
# ./13.files_filepath_PATCH_rename.sh FROM TO
#
#   FROM  the file or folder, relative to the home folder
#   TO    its new path, relative to the home folder. A different folder moves it.
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - The body is a list of operations (RFC 6902), even for one.
# - Confirmed directly: a success answers 204, with no body.
# - Requires `jq`, which builds the body and URL-encodes the path.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

FROM="${1#/}"
TO="${2#/}"
if [ -z "${FROM}" ] || [ -z "${TO}" ]; then
    printf "Usage: ./13.files_filepath_PATCH_rename.sh FROM TO\n"
    exit 2
fi
if [ ! -f "${COOKIE}" ]; then
    printf "There is no session. Run 01.Authenticate/01.myself_POST.sh first.\n"
    exit 1
fi

ENCODED=$(printf '%s' "${FROM}" | jq -Rr 'split("/") | map(@uri) | join("/")')
BODY=$(jq -n --arg to "${TO}" '[{op: "add", path: "/newFilePath", value: $to}]')

printf "Renaming %s to %s...\n" "${FROM}" "${TO}"
HTTP_CODE=$(curl -s -k -o /dev/null -b "${COOKIE}" -X PATCH "${ST_URL}/files/${ENCODED}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "${BODY}" -w "%{http_code}")
if [ "${HTTP_CODE}" != "204" ]; then
    printf "The rename failed (HTTP %s).\n" "${HTTP_CODE}"
    exit 1
fi
printf "Renamed.\n"
