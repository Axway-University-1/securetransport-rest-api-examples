#!/bin/bash
# ==============================================================================
# Script Name: 03.files_POST_md5_refused.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# What to do when an upload is refused. Uploads with a wrong Content-MD5 (the server answers 500), then looks at what the server holds anyway, asks it for the MD5 of that file and compares it with the local one, deletes it, and sends it again with the right checksum, ending verified.
#
# Usage:
# ./03.files_POST_md5_refused.sh
#
# Risk: write
#
# Notes:
# - No copy in EndUser/API 2.0/bash: it joins calls that are there (02.Files/11, 02.Files/10, 02.Files/07, 04.FileOperations/01).
# - The 500 does not say whether the file was stored. On the lab it is stored, in full: a refusal is not proof of an empty folder, and a "stored" file is not proof it is right. The MD5 the server computes (st_md5calc in lib.sh) is.
# - A 500 now and then is not always a wrong checksum: the same steps are the way out of any refused upload. Look, compare, delete, send again, compare.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

LOCAL=$(mktemp)
trap 'rm -f "${LOCAL}"' EXIT
st_sample "${LOCAL}" 100000 refused
RIGHT=$(st_md5 "${LOCAL}")
WRONG=$(printf 'not the checksum' | openssl dgst -md5 -binary | openssl base64)
NAME_URL="${ST_URL}/files/$(st_enc "${FOLDER}/${WRONG_FILE}")"

code=$(st_put_file "${LOCAL}" "${WRONG_FILE}" "${WRONG}")
echo "1. Upload with a wrong checksum: HTTP ${code}"
[[ "${code}" == 2* ]] && { echo "The server accepted a wrong checksum, so there is nothing to recover from."; exit 1; }

code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X GET "${NAME_URL}?metadata=true" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "2. Is the file there? GET its metadata: HTTP ${code}"
if [ "${code}" = 200 ]; then
    st_md5calc "/${FOLDER}/${WRONG_FILE}" || exit 1
    echo "3. The server holds ${SERVER_SIZE} bytes, MD5 ${SERVER_MD5}. Here: $(wc -c < "${LOCAL}" | tr -d ' ') bytes, MD5 ${RIGHT}."
    [ "${SERVER_MD5}" = "${RIGHT}" ] && echo "   The content is whole. The refusal was about the checksum header only."
    code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X DELETE "${NAME_URL}" -H "accept: application/json" -H "Referer: ${REFERER}")
    echo "4. Delete it before sending it again: HTTP ${code}"
    [[ "${code}" == 204 ]] || exit 1
else
    echo "3. Nothing is stored under that name, so there is nothing to delete."
fi

code=$(st_put_file "${LOCAL}" "${WRONG_FILE}" "${RIGHT}")
echo "5. Send it again with the right checksum: HTTP ${code}"
[[ "${code}" == 201 ]] || exit 1
st_md5calc "/${FOLDER}/${WRONG_FILE}" || exit 1
[ "${SERVER_MD5}" = "${RIGHT}" ] || { echo "6. The server's MD5 is ${SERVER_MD5}, not ${RIGHT}: the file is not the one that was sent."; exit 1; }
echo "6. Verified: the server holds ${SERVER_SIZE} bytes with the MD5 of the local file."
