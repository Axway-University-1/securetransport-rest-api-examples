#!/bin/bash
# ==============================================================================
# Script Name: 09.files_GET_query.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists files with the query parameters of the `/files` and
# `/files/{filePath}` endpoints. It demonstrates:
# - Sorting and paging: sortBy, order, limit and offset
# - Leaving out hidden files, the ones starting with a dot (showdots=false)
# - Reading a folder's own metadata without its file list (metadata=true)
# - Listing only the files that match a glob pattern, such as *.txt
#
# Usage:
# ./09.files_GET_query.sh [FOLDER [PATTERN]]
#
#   FOLDER   the folder to list, relative to the home folder (default: the
#            home folder itself)
#   PATTERN  a glob for the pattern listing (default *.txt)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - sortBy is fileName, lastModifiedTime or size; order is ASC or DESC.
# - A file path holding a glob character is listed, not downloaded (confirmed
#   directly: /files/*.txt answers with the matching files).
# - Requires `jq`, which prints the short listings and URL-encodes the path.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

FOLDER="${1:-}"
FOLDER="${FOLDER#/}"
FOLDER="${FOLDER%/}"
PATTERN="${2:-*.txt}"
if [ ! -f "${COOKIE}" ]; then
    printf "There is no session. Run 01.Authenticate/01.myself_POST.sh first.\n"
    exit 1
fi

# /files for the home folder, /files/<folder> for another. Each part of the
# path is encoded on its own, so the / between them stays a /
# A * is put back after encoding: it is the glob, and the probe that confirmed
# glob listings sent it as it is. A ? stays encoded: it would start a query.
encode() { printf '%s' "$1" | jq -Rr 'split("/") | map(@uri | gsub("%2A"; "*")) | join("/")'; }
if [ -z "${FOLDER}" ]; then
    LIST_URL="${ST_URL}/files"
    PATTERN_URL="${ST_URL}/files/$(encode "${PATTERN}")"
else
    LIST_URL="${ST_URL}/files/$(encode "${FOLDER}")"
    PATTERN_URL="${ST_URL}/files/$(encode "${FOLDER}/${PATTERN}")"
fi
# One line per entry: d for a folder, f for a file
SHORT='(.files // [])[] | "  \(if .isDirectory then "d" else "f" end)  \(.size)  \(.fileName)"'

printf "The 5 largest, biggest first, without hidden files:\n"
curl -s -k -G -b "${COOKIE}" -X GET "${LIST_URL}" \
  --data-urlencode "sortBy=size" --data-urlencode "order=DESC" \
  --data-urlencode "limit=5" --data-urlencode "offset=0" --data-urlencode "showdots=false" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r "${SHORT}"

printf "\nThe next 5, by name:\n"
curl -s -k -G -b "${COOKIE}" -X GET "${LIST_URL}" \
  --data-urlencode "sortBy=fileName" --data-urlencode "order=ASC" \
  --data-urlencode "limit=5" --data-urlencode "offset=5" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r "${SHORT}"

printf "\nThe folder's own metadata, without its file list:\n"
curl -s -k -G -b "${COOKIE}" -X GET "${LIST_URL}" --data-urlencode "metadata=true" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '.self | "  \(.fileName)  permissions \(.permissions)  shared \(.isShared)"'

printf "\nOnly the files matching %s:\n" "${PATTERN}"
curl -s -k -b "${COOKIE}" -X GET "${PATTERN_URL}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r "${SHORT}"
