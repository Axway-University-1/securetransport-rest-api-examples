#!/bin/bash
# ==============================================================================
# Script Name: 05.files_GET_metadata.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Reads about the file without reading the file: GET /files/<folder>/<file>?metadata=true returns its size, permissions, times, and the MD5 the server recorded when it came in.
#
# Usage:
# ./05.files_GET_metadata.sh
#
# Risk: read
#
# Notes:
# - Copied from EndUser/API 2.0/bash/02.Files/10.files_filepath_GET_metadata.sh.
# - The answer has self (the file), and parent (the folder it is in).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

result=$(curl -k -s -G -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/files/$(st_enc "${FOLDER}/${FILE_NAME}")" \
         --data-urlencode "metadata=true" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "HTTP ${code}"
[[ "${code}" == 200 ]] || exit 1
echo "${result%???}" | jq -r '.self | "  name      \(.fileName)", "  size      \(.size) bytes", "  rights    \(.permissions)", "  modified  \(.lastModifiedTime / 1000 | todate)", "  MD5       \(.customProperties.MD5 // "not recorded")"' 
