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
#   FILE        the file on the server, relative to the home folder
#   LOCAL_COPY  a local file to compare the checksum with (optional)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
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

source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

FILE="/${1#/}"
LOCAL_COPY="$2"
if [ "${FILE}" = "/" ]; then
    printf "Usage: ./01.fileOperations_POST_md5calc.sh FILE [LOCAL_COPY]\n"
    exit 2
fi
if [ ! -f "${COOKIE}" ]; then
    printf "There is no session. Run 01.Authenticate/01.myself_POST.sh first.\n"
    exit 1
fi

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
