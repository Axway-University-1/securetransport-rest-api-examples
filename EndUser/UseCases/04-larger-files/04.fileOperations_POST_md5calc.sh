#!/bin/bash
# ==============================================================================
# Script Name: 04.fileOperations_POST_md5calc.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Asks the server for the MD5 of a file it already holds, and compares it with the local copy. POST /fileOperations starts an MD5Calc operation, and GET /fileOperations/<id> is followed until it is DONE.
#
# Usage:
# ./04.fileOperations_POST_md5calc.sh
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/04.FileOperations/01.fileOperations_POST_md5calc.sh.
# - It is an operation because a big file takes time: the status goes IN_PROGRESS, then DONE (or an error), and it waits at most 30 seconds.
# - It needs 02 to have uploaded the file first.
# - The same helper (st_md5calc in lib.sh) is how 03 and 07 check what the server holds.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

LOCAL=$(mktemp)
trap 'rm -f "${LOCAL}"' EXIT
st_sample "${LOCAL}" 100000 md5
st_md5calc "/${FOLDER}/${MD5_FILE}" || exit 1
echo "The server: ${SERVER_SIZE} bytes, MD5 ${SERVER_MD5}"
echo "Here:       $(wc -c < "${LOCAL}" | tr -d ' ') bytes, MD5 $(st_md5 "${LOCAL}")"
[ "${SERVER_MD5}" = "$(st_md5 "${LOCAL}")" ] && echo "They match." || { echo "They do NOT match."; exit 1; }
