#!/bin/bash
# ==============================================================================
# Script Name: 02.files_POST_md5.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Uploads a file and has the server check it arrived intact. The Content-MD5 header carries the MD5 of the file; the server compares it with what it received. A right checksum gives 201, and a wrong one is refused (this shows both).
#
# Usage:
# ./02.files_POST_md5.sh
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/02.Files/11.files_filepath_POST_md5.sh.
# - The checksum is base64 of the 16 raw bytes, not the hex text md5sum prints.
# - The wrong checksum is refused with an error (500 on the lab), and any non-201 counts as a refusal. The refusal does not undo the upload: the file may be stored all the same. 03 shows it.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

LOCAL=$(mktemp)
trap 'rm -f "${LOCAL}"' EXIT
st_sample "${LOCAL}" 100000 md5
MD5=$(st_md5 "${LOCAL}")
URL="${ST_URL}/files/$(st_enc "${FOLDER}")?transferMode=BINARY"

code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X POST "${URL}" -H "accept: application/json" -H "Referer: ${REFERER}" \
       -H "Content-MD5: ${MD5}" -F "file=@${LOCAL};filename=${MD5_FILE}")
echo "With the right checksum (${MD5}): HTTP ${code}"
[[ "${code}" == 201 ]] || exit 1

WRONG=$(printf 'not the checksum' | openssl dgst -md5 -binary | openssl base64)
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X POST "${URL}" -H "accept: application/json" -H "Referer: ${REFERER}" \
       -H "Content-MD5: ${WRONG}" -F "file=@${LOCAL};filename=${MD5_FILE}")
echo "With a wrong checksum: HTTP ${code}"
[[ "${code}" == 201 ]] && { echo "The server accepted a wrong checksum."; exit 1; }
echo "Refused, as it should be. (The refusal is not proof that nothing was stored: 03 looks.)"
