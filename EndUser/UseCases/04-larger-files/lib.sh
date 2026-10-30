#!/bin/bash
# ==============================================================================
# Script Name: lib.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Sourced by every script of this use case. Loads ../session.sh (the settings, the
# cookie jar session.cookie.jar of this use case, st_session and st_enc), the names it works with, and two helpers for a sample file and its MD5.
#
# Usage:
# source lib.sh
#
# Risk: none
# ==============================================================================

UC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${UC_DIR}/../session.sh"

# What this use case creates: one folder in the home folder, and the files in it.
# 99.cleanup_DELETE.sh removes exactly these names and nothing else.
FOLDER="example_uc_large"
MD5_FILE="example_md5.bin"
CHUNKED_FILE="example_chunked.bin"
MULTIPART_FILE="example_multipart.bin"
BULK_FILES="example_bulk_1.txt example_bulk_2.txt example_bulk_3.txt"
WRONG_FILE="example_md5_wrong.bin"
TEXT_ASCII_FILE="example_text_ascii.txt"
TEXT_BINARY_FILE="example_text_binary.txt"
ORDER_FILE="example_order.bin"
LOCALNAME_FILE="example_localname.bin"

# st_sample FILE BYTES [TAG]: writes a file of that many bytes, the same every time for the same TAG, so that a
# script can tell what the server should say about it
st_sample() { yes "example content, ${3:-sample}" 2>/dev/null | head -c "$2" > "$1"; }
# st_md5 FILE: the MD5 of the file as base64 of its 16 raw bytes, the form the server uses
st_md5() { openssl dgst -md5 -binary "$1" | openssl base64; }

# st_md5calc PATH: asks the server for the MD5 of the file at PATH (POST /fileOperations, then GET /fileOperations/<id>
# until it is DONE, at most 30 seconds). On success sets SERVER_SIZE and SERVER_MD5 and returns 0; otherwise says why and returns 1.
st_md5calc() {
    local body operation id status waited=0
    body=$(jq -n --arg path "$1" '{operation: "MD5Calc", filePath: $path}')
    operation=$(curl -k -s -b "${JAR}" -X POST "${ST_URL}/fileOperations" -H "accept: application/json" -H "Referer: ${REFERER}" -H "Content-Type: application/json" -d "${body}")
    id=$(echo "${operation}" | jq -r '.id // empty' 2>/dev/null)
    if [ -z "${id}" ]; then
        echo "No operation id came back: ${operation}"
        return 1
    fi
    status=$(echo "${operation}" | jq -r '.status')
    while [ "${status}" = "IN_PROGRESS" ] || [ "${status}" = "WAITING" ]; do
        [ "${waited}" -ge 30 ] && { echo "Still ${status} after 30 seconds."; return 1; }
        sleep 1
        waited=$((waited + 1))
        operation=$(curl -k -s -b "${JAR}" -X GET "${ST_URL}/fileOperations/${id}" -H "accept: application/json" -H "Referer: ${REFERER}")
        status=$(echo "${operation}" | jq -r '.status')
    done
    [ "${status}" = "DONE" ] || { echo "The operation ended ${status}: ${operation}"; return 1; }
    SERVER_SIZE=$(echo "${operation}" | jq -r '.result.fileSize')
    SERVER_MD5=$(echo "${operation}" | jq -r '.result.md5Checksum')
}

# st_put_file LOCAL NAME [MD5]: uploads LOCAL into the folder as NAME, as BINARY, with the Content-MD5 MD5 when one is given.
# Prints the HTTP code.
st_put_file() {
    local args=()
    [ -n "$3" ] && args=(-H "Content-MD5: $3")
    curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X POST "${ST_URL}/files/$(st_enc "${FOLDER}")?transferMode=BINARY" \
         -H "accept: application/json" -H "Referer: ${REFERER}" "${args[@]}" -F "file=@$1;filename=$2"
}
