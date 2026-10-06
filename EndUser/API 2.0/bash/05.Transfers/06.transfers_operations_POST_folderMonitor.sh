#!/bin/bash
# ==============================================================================
# Script Name: 06.transfers_operations_POST_folderMonitor.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script runs a folder monitor transfer once, on demand, using the
# `/transfers/operations` endpoint with the folderMonitor operation: the files
# matching a pattern in one folder of the home folder are moved to another, as
# a transfer of their own.
#
# Usage:
# ./06.transfers_operations_POST_folderMonitor.sh FROM TO [PATTERN]
#
#   FROM     the folder to pick the files up from, relative to the home folder
#   TO       the folder to move them to, relative to the home folder
#   PATTERN  a glob for the files to move (default *)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - Both folders must exist. No transfer site is needed.
# - Confirmed directly: it answers 200, "Folder monitor executed
#   successfully", the files are moved out of FROM into TO, and the log lists
#   them under the operationIndex given, as Incoming, protocol folder.
# - Sub-folders of FROM up to subFolderMaxDepth are searched too, those
#   matching subFolderPattern. A negative depth searches the whole tree.
# - Requires `jq`, which builds the body.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

FROM="/${1#/}"
TO="/${2#/}"
PATTERN="${3:-*}"
OPERATION_INDEX="eu-folder-$(date +%s)"
if [ "${FROM}" = "/" ] || [ "${TO}" = "/" ]; then
    printf "Usage: ./06.transfers_operations_POST_folderMonitor.sh FROM TO [PATTERN]\n"
    exit 2
fi
if [ ! -f "${COOKIE}" ]; then
    printf "There is no session. Run 01.Authenticate/01.myself_POST.sh first.\n"
    exit 1
fi

BODY=$(jq -n --arg from "${FROM}" --arg to "${TO}" --arg pattern "${PATTERN}" --arg index "${OPERATION_INDEX}" \
  '{operation: "folderMonitor",
    data: {operationIndex: $index, downloadFolder: $from, uploadFolder: $to,
           filePattern: $pattern, filePatternType: "glob", fileCaseSensitive: true,
           subFolderPattern: "*", subFolderPatternType: "glob", subFolderCaseSensitive: true,
           subFolderMaxDepth: 1}}')

printf "Moving %s from %s to %s, as %s...\n" "${PATTERN}" "${FROM}" "${TO}" "${OPERATION_INDEX}"
RESPONSE=$(curl -s -k -b "${COOKIE}" -X POST "${ST_URL}/transfers/operations" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf '%s\nHTTP %s\n' "${RESPONSE%$'\n'*}" "${HTTP_CODE}"
case "${HTTP_CODE}" in
    2*) ;;
    *) exit 1 ;;
esac

sleep 2
printf "The files moved, in the log:\n"
curl -s -k -G -b "${COOKIE}" -X GET "${ST_URL}/transfers" --data-urlencode "operationIndex=${OPERATION_INDEX}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '.[] | "  \(.startTime)  \(.status)  \(.filename)"'
