#!/bin/bash
# ==============================================================================
# Script Name: 99.cleanup_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Removes what this use case made: the files lst_01.txt to lst_20.txt in the folder example_uc_lists, then the folder, and ends the session. It can be run twice.
#
# Usage:
# ./99.cleanup_DELETE.sh
#
# Risk: write
#
# Notes:
# - Written for this use case. The files are found by listing the folder and removed by their exact names (lst_NN.txt); anything else in the folder is left, and then the folder cannot be removed: the script says so.
# - A folder that is not there is said, and is not an error.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./99.cleanup_DELETE.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
st_session

STATUS=0
ENC=$(st_enc "${FOLDER}")
eu_get "files/${ENC}"
if [ "${EU_CODE}" = "404" ]; then
    echo "There is no folder ${FOLDER}: nothing to delete."
elif [ "${EU_CODE}" != "200" ]; then
    echo "Could not read the folder ${FOLDER} (HTTP ${EU_CODE}): delete it by hand."
    STATUS=1
else
    REMOVED=0
    for NAME in $(printf '%s' "${EU_BODY}" | jq -r '.files[].fileName | select(test("^lst_[0-9][0-9]\\.txt$"))'); do
        code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X DELETE "${ST_URL}/files/${ENC}/${NAME}" -H "accept: application/json" -H "Referer: ${REFERER}")
        case "${code}" in
            200|204) REMOVED=$((REMOVED + 1)) ;;
            *) echo "The file ${FOLDER}/${NAME} could not be deleted (HTTP ${code}): delete it by hand."; STATUS=1 ;;
        esac
    done
    echo "Deleted ${REMOVED} files from ${FOLDER}."
    code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X DELETE "${ST_URL}/files/${ENC}" -H "accept: application/json" -H "Referer: ${REFERER}")
    case "${code}" in
        200|204) echo "The folder ${FOLDER} was deleted." ;;
        *) echo "The folder ${FOLDER} could not be deleted (HTTP ${code}): is anything else in it?"; STATUS=1 ;;
    esac
fi

if [ -f "${JAR}" ]; then
    curl -k -s -o /dev/null -b "${JAR}" -X DELETE "${ST_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}"
fi
rm -f "${JAR}" "${CSRF_FILE}"
echo "Cleaned up."
exit ${STATUS}
