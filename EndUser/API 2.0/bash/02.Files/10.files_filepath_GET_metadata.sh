#!/bin/bash
# ==============================================================================
# Script Name: 10.files_filepath_GET_metadata.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads a file's metadata instead of its content, using the
# `/files/{filePath}` endpoint with metadata=true: its size, permissions, owner,
# times, transfer status and custom properties.
#
# Usage:
# ./10.files_filepath_GET_metadata.sh FILE
#
#   FILE  the file, relative to the home folder, for example test.txt or
#         reports/2026/summary.csv
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - Without metadata=true the same call downloads the file (see
#   03.files_filepath_GET.sh).
# - The answer holds the file as "self", and the folder it is in as "parent".
# - Requires `jq`, which URL-encodes the path and prints the summary.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

FILE="${1#/}"
if [ -z "${FILE}" ]; then
    printf "Usage: ./10.files_filepath_GET_metadata.sh FILE\n"
    exit 2
fi
if [ ! -f "${COOKIE}" ]; then
    printf "There is no session. Run 01.Authenticate/01.myself_POST.sh first.\n"
    exit 1
fi

ENCODED=$(printf '%s' "${FILE}" | jq -Rr 'split("/") | map(@uri) | join("/")')
RESPONSE=$(curl -s -k -G -b "${COOKIE}" -X GET "${ST_URL}/files/${ENCODED}" --data-urlencode "metadata=true" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"

if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the metadata of %s (HTTP %s):\n%s\n" "${FILE}" "${HTTP_CODE}" "${BODY}"
    exit 1
fi
printf '%s\n' "${BODY}"
printf "\nIn short:\n"
printf '%s' "${BODY}" | jq -r '.self |
  "  name         \(.fileName)",
  "  size         \(.size) bytes",
  "  permissions  \(.permissions), owner \(.owner), group \(.group)",
  "  modified     \(.lastModifiedTime / 1000 | floor | todate)",
  "  status       \(.transferStatus // "")"'
