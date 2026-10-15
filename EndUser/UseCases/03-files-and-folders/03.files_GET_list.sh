#!/bin/bash
# ==============================================================================
# Script Name: 03.files_GET_list.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Lists the folder, and then shapes the list: the entry names only, sorted by size, limited to the first entries, and filtered with a glob. The parameters go in the query: sortBy (fileName, lastModifiedTime or size), order (ASC or DESC), limit, offset, showdots; a glob goes in the path.
#
# Usage:
# ./03.files_GET_list.sh
#
# Risk: read
#
# Notes:
# - Copied from EndUser/API 2.0/bash/02.Files/09.files_GET_query.sh.
# - A list is limited to 100 entries and has no fixed order unless sortBy is given.
# - curl -G with --data-urlencode builds the query, and encodes the values.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

URL="${ST_URL}/files/$(st_enc "${FOLDER}")"
SHORT='(.files // [])[] | "  \(if .isDirectory then "d" else "f" end)  \(.size)  \(.fileName)"'

echo "The folder:"
curl -k -s -b "${JAR}" -X GET "${URL}" -H "accept: application/json" -H "Referer: ${REFERER}" | jq -r "${SHORT}"

echo "The largest first, at most 5, no hidden files:"
curl -k -s -G -b "${JAR}" -X GET "${URL}" --data-urlencode "sortBy=size" --data-urlencode "order=DESC" \
     --data-urlencode "limit=5" --data-urlencode "showdots=false" -H "accept: application/json" -H "Referer: ${REFERER}" | jq -r "${SHORT}"

echo "Only the .txt files (a glob in the path):"
curl -k -s -b "${JAR}" -X GET "${URL}/*.txt" -H "accept: application/json" -H "Referer: ${REFERER}" | jq -r "${SHORT}"

echo "The folder itself, without its list (metadata=true):"
curl -k -s -G -b "${JAR}" -X GET "${URL}" --data-urlencode "metadata=true" -H "accept: application/json" -H "Referer: ${REFERER}" \
     | jq -r '.self | "  \(.fileName)  permissions \(.permissions)"' 
