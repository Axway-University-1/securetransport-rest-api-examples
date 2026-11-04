#!/bin/bash
# ==============================================================================
# Script Name: 02.validation_path_POST.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# This script asks the server about a path on the server's own file system, with `POST /api/v1.4/validation/path` of the Admin API 1.4: is the path valid, does it
# exist, is it a folder, is it a file. The API 2.0 has no such call. It is what the Administration Tool uses to check a folder you type in.
#
# Usage:
# ./02.validation_path_POST.sh PATH [ASK]
#
#   PATH  the path to ask about, for example /data/inbox
#   ASK   what to ask, a comma separated list of validate, exist, isDirectory and isFile (default: all four)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
# - The call is a POST with form data (not JSON), and it changes nothing. The answer holds only what was asked: `isExist` for exist, `isDirectory` for isDirectory, `isFile` for
#   isFile, and always relativePath, isValid and absolutePath.
# - Confirmed directly on 5.5-20260924: the path is looked up on the SERVER, not on the machine that runs this script. A path that does not exist answers 200 with
#   isExist false. A relative path is not refused here (unlike validPath in 01): absolutePath shows where the server would put it, under its own install folder.
#   An empty path is 400 "may not be empty".
# - Unlike 01.validation_validPath_POST.sh, this call does not check the list of unsafe paths.
# - The script exits 0 when the server answers 200, 1 for any other answer, 2 for wrong use.
# - Requires `jq` to read the answer.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${ST_ADMIN_LOCAL_VARIABLES:-${SCRIPT_DIR}/../set_variables.local.sh}" ||
    { echo "Copy set_variables.local.example.sh to set_variables.local.sh and fill it in."; exit 1; }

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v1.4/validation/path"
USAGE="Usage: ./02.validation_path_POST.sh PATH [ASK]"
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ -z "$1" ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
CHECKED_PATH="$1"
ASK="${2:-validate,exist,isDirectory,isFile}"
QUESTIONS=()
IFS=',' read -r -a WANTED <<< "${ASK}"
for WORD in "${WANTED[@]}"; do
    case "${WORD}" in
        validate|exist|isDirectory|isFile) QUESTIONS+=(--data-urlencode "${WORD}=true") ;;
        *) printf "ASK has '%s': only validate, exist, isDirectory and isFile.\n%s\n" "${WORD}" "${USAGE}"; exit 2 ;;
    esac
done

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" --data-urlencode "inputPath=${CHECKED_PATH}" "${QUESTIONS[@]}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "The server refused the question (HTTP %s): " "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors[0] // .message // .)' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
printf "%s (HTTP 200)\n" "${CHECKED_PATH}"
printf '%s' "${RESPONSE}" | jq -r 'to_entries[] | "  \(.key): \(.value)"'
