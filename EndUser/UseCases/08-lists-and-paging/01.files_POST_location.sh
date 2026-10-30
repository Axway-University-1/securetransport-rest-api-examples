#!/bin/bash
# ==============================================================================
# Script Name: 01.files_POST_location.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Lists, step 1: something to list, and the Location header. Makes the folder example_uc_lists in your home folder and COUNT small files in it (lst_01.txt, lst_02.txt, ...). A POST that creates answers 201 with no body: the address of
# the new file is in the Location header. A new folder answers 201 with no Location at all. The script prints both and reads the first file back by its Location.
#
# Usage:
# ./01.files_POST_location.sh [COUNT]
#
#   COUNT  how many files to upload, 1 to 20 (default 7)
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/02.Files/02.files_name_POST_folder.sh and 04.files_filepath_POST.sh.
# - The Location of a file is its path with every / written %2F: .../files/%2Fexample_uc_lists%2Flst_01.txt. Use it as it is.
# - A folder that is there already is used as it is. A file that is there already is replaced (201 again, and the same Location).
# - Every upload is a transfer: they appear in 05-checking-transfers and in the list that 03 reads, for an account that may use the transfers web service.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./01.files_POST_location.sh [COUNT]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: COUNT.\n%s\n" "$#" "${USAGE}"; exit 2; fi
COUNT="${1:-7}"
if [[ ! "${COUNT}" =~ ^[1-9][0-9]?$ ]] || [ "${COUNT}" -gt "${MAX_FILES}" ]; then
    printf "COUNT is '%s': it must be a whole number from 1 to %s.\n%s\n" "${COUNT}" "${MAX_FILES}" "${USAGE}"
    exit 2
fi
st_session

HEADERS=$(mktemp)
LOCAL=$(mktemp)
trap 'rm -f "${HEADERS}" "${LOCAL}"' EXIT
ENC=$(st_enc "${FOLDER}")
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -G "${ST_URL}/files/${ENC}" --data-urlencode "metadata=true" -H "accept: application/json" -H "Referer: ${REFERER}")
if [ "${code}" = "200" ]; then
    echo "The folder '${FOLDER}' is there already: it is used as it is."
else
    BODY=$(jq -n '{isDirectory: true, isRegularFile: false, isSymbolicLink: false, isOther: false, isShared: false}')
    code=$(curl -k -s -o /dev/null -w "%{http_code}" -D "${HEADERS}" -b "${JAR}" -X POST "${ST_URL}/files/${ENC}" -H "accept: application/json" -H "Referer: ${REFERER}" -H "Content-Type: application/json" -d "${BODY}")
    echo "Create the folder '${FOLDER}': HTTP ${code}"
    [ "${code}" = "201" ] || exit 1
    LOCATION=$(tr -d '\r' < "${HEADERS}" | sed -n 's/^[Ll]ocation: *//p')
    echo "  Location: ${LOCATION:-none. A new folder has no Location header.}"
fi

FIRST_LOCATION=""
for n in $(seq 1 "${COUNT}"); do
    NAME=$(printf 'lst_%02d.txt' "${n}")
    printf 'File %s of the use case that lists and pages.\n' "${n}" > "${LOCAL}"
    code=$(curl -k -s -o /dev/null -w "%{http_code}" -D "${HEADERS}" -b "${JAR}" -X POST "${ST_URL}/files/${ENC}" -F "file=@${LOCAL};filename=${NAME}" -H "accept: application/json" -H "Referer: ${REFERER}")
    LOCATION=$(tr -d '\r' < "${HEADERS}" | sed -n 's/^[Ll]ocation: *//p')
    echo "Upload ${FOLDER}/${NAME}: HTTP ${code}"
    [ "${code}" = "201" ] || exit 1
    echo "  Location: ${LOCATION}"
    case "${LOCATION}" in
        */files/*"${NAME}") ;;
        *) echo "  The Location does not end with the name of the file (${NAME})."; exit 1 ;;
    esac
    [ "${n}" -ne 1 ] || FIRST_LOCATION="${LOCATION}"
done

code=$(curl -k -s -o "${LOCAL}" -w "%{http_code}" -b "${JAR}" "${FIRST_LOCATION}" -H "accept: application/octet-stream" -H "Referer: ${REFERER}")
echo "GET of the first Location: HTTP ${code}, $(wc -c < "${LOCAL}" | tr -d ' ') bytes."
[ "${code}" = "200" ] || exit 1
