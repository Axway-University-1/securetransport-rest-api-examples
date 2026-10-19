#!/bin/bash
# ==============================================================================
# Script Name: 01.fileOperations_POST_md5calc.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script has the server compute a file's MD5 checksum, using the
# `/fileOperations` endpoint with the MD5Calc operation. It demonstrates:
# - Submitting an asynchronous file operation, which answers with an id
# - Following it with GET /fileOperations/{id} until it is DONE
# - Comparing the server's checksum with a local copy of the file
#
# Usage:
# ./01.fileOperations_POST_md5calc.sh FILE [LOCAL_COPY]
#
#   FILE        the path of the file ON THE SERVER, relative to the home folder of the
#               user, with or without a leading slash: reports/test.txt, or
#               /reports/test.txt, or test.txt for a file in the home folder itself.
#               It is not a path on your machine.
#   LOCAL_COPY  the path of a file ON YOUR MACHINE to compare the server's checksum with
#               (optional): absolute, or relative to the folder you run the script from,
#               for example ./test.txt or ~/Downloads/test.txt. It is not uploaded:
#               the script only reads it to work out its MD5.
#
# For example:
# ./01.fileOperations_POST_md5calc.sh test.txt
# ./01.fileOperations_POST_md5calc.sh reports/test.txt ./downloaded_files/test.txt
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
# - It checks for an active session first and, if there is none, logs in with
#   01.Authenticate/01.myself_POST.sh and then carries on.
# - Confirmed directly: the first answer is IN_PROGRESS with only the file
#   size; a GET a moment later is DONE with result.md5Checksum, base64 encoded,
#   the same form as the Content-MD5 header.
# - Gives up after 30 seconds.
# - Requires `jq`, and `openssl` to compare with a local copy.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${ST_ENDUSER_LOCAL_VARIABLES:-${SCRIPT_DIR}/../set_variables.local.sh}" ||
    { echo "Copy set_variables.local.example.sh to set_variables.local.sh and fill it in."; exit 1; }
export ST_URL="${ST_URL:-https://${ST_SERVER}:${ST_PORT}/api/v2.0}"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
source "${SCRIPT_DIR}/../ensure_session.sh"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

FILE="/${1#/}"
LOCAL_COPY="$2"
if [ "${FILE}" = "/" ]; then
    printf "Usage: ./01.fileOperations_POST_md5calc.sh FILE [LOCAL_COPY]\n"
    printf "  FILE        the path of the file on the server, relative to the home folder (reports/test.txt)\n"
    printf "  LOCAL_COPY  the path of a file on this machine to compare with (./test.txt)\n"
    exit 2
fi
if [ -n "${LOCAL_COPY}" ] && [ ! -f "${LOCAL_COPY}" ]; then
    printf "LOCAL_COPY must be a file on this machine, and there is none at '%s'.\n" "${LOCAL_COPY}"
    printf "(It is the path of your local copy, absolute or relative to %s. FILE is the one on the server.)\n" "$(pwd)"
    exit 2
fi
st_ensure_session

BODY=$(jq -n --arg path "${FILE}" '{operation: "MD5Calc", filePath: $path}')
printf "Asking for the MD5 checksum of %s...\n" "${FILE}"
OPERATION=$(curl -s -k -b "${COOKIE}" -X POST "${ST_URL}/fileOperations" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}")
OPERATION_ID=$(printf '%s' "${OPERATION}" | jq -r '.id // empty' 2>/dev/null)
if [ -z "${OPERATION_ID}" ]; then
    printf "No operation id came back. The response was:\n%s\n" "${OPERATION}"
    exit 1
fi

# The operation runs on the server: follow it until it is done
STATUS=$(printf '%s' "${OPERATION}" | jq -r '.status')
waited=0
while [ "${STATUS}" = "IN_PROGRESS" ] || [ "${STATUS}" = "WAITING" ]; do
    if [ "${waited}" -ge 30 ]; then
        printf "Still %s after 30 seconds. Follow it with 02.fileOperations_id_GET.sh %s\n" "${STATUS}" "${OPERATION_ID}"
        exit 1
    fi
    sleep 1
    waited=$((waited + 1))
    OPERATION=$(curl -s -k -b "${COOKIE}" -X GET "${ST_URL}/fileOperations/${OPERATION_ID}" \
      -H "accept: application/json" -H "${REFERER_HEADER}")
    STATUS=$(printf '%s' "${OPERATION}" | jq -r '.status')
done

if [ "${STATUS}" != "DONE" ]; then
    printf "The operation ended %s:\n%s\n" "${STATUS}" "${OPERATION}"
    exit 1
fi
SERVER_MD5=$(printf '%s' "${OPERATION}" | jq -r '.result.md5Checksum')
printf "%s: %s bytes, MD5 %s\n" "${FILE}" "$(printf '%s' "${OPERATION}" | jq -r '.result.fileSize')" "${SERVER_MD5}"

if [ -n "${LOCAL_COPY}" ]; then
    LOCAL_MD5=$(openssl dgst -md5 -binary "${LOCAL_COPY}" | openssl base64)
    if [ "${LOCAL_MD5}" = "${SERVER_MD5}" ]; then
        printf "It matches %s.\n" "${LOCAL_COPY}"
    else
        printf "It does NOT match %s, whose MD5 is %s.\n" "${LOCAL_COPY}" "${LOCAL_MD5}"
        exit 1
    fi
fi
