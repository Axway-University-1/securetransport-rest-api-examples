#!/bin/bash
# ==============================================================================
# Script Name: 05.files_POST_text_binary.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Text or binary. Uploads the same two lines, written with CR LF line ends, as ASCII and as BINARY (the transferMode query), reads both back and shows the bytes: ASCII turns CR LF into LF, BINARY keeps every byte.
#
# Usage:
# ./05.files_POST_text_binary.sh
#
# Risk: write
#
# Notes:
# - No copy in EndUser/API 2.0/bash: it joins 02.Files/04 and 02.Files/03 with the transferMode query.
# - Send anything that must arrive byte for byte (archives, images, signed or encrypted files) as BINARY, and say so with transferMode=BINARY. Without transferMode the file is stored as it is sent.
# - The two files are the ones this use case removes in 99, by their exact names.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

LOCAL=$(mktemp); GOT=$(mktemp)
trap 'rm -f "${LOCAL}" "${GOT}"' EXIT
printf 'a\r\nb\r\n' > "${LOCAL}"
echo "Local file, in hex: $(od -An -tx1 "${LOCAL}" | tr -d ' \n')"

for mode in ASCII BINARY; do
    if [ "${mode}" = ASCII ]; then name="${TEXT_ASCII_FILE}"; else name="${TEXT_BINARY_FILE}"; fi
    code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X POST "${ST_URL}/files/$(st_enc "${FOLDER}")?transferMode=${mode}" \
           -H "accept: application/json" -H "Referer: ${REFERER}" -F "file=@${LOCAL};filename=${name}")
    echo "Upload as ${mode}: HTTP ${code}"
    [[ "${code}" == 20* ]] || exit 1
    code=$(curl -k -s -o "${GOT}" -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/files/$(st_enc "${FOLDER}/${name}")" \
           -H "accept: application/octet-stream" -H "Referer: ${REFERER}")
    [ "${code}" = 200 ] || { echo "Read it back: HTTP ${code}"; exit 1; }
    HEX=$(od -An -tx1 "${GOT}" | tr -d ' \n')
    echo "  ${mode} on the server, in hex: ${HEX}"
    if [ "${mode}" = ASCII ]; then HEX_ASCII="${HEX}"; else HEX_BINARY="${HEX}"; fi
done
[ "${HEX_ASCII}" = "610a620a" ] && [ "${HEX_BINARY}" = "610d0a620d0a" ] || { echo "Not what was expected: ASCII 610a620a, BINARY 610d0a620d0a."; exit 1; }
echo "ASCII dropped the CR of each line end (0d). BINARY kept every byte."
