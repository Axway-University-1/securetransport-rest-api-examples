#!/bin/bash
# ==============================================================================
# Script Name: 04.secretQuestion_GET_back.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# Reads the question back, and checks it is the one that was picked. The answer is not returned by any call.
#
# Usage:
# ./04.secretQuestion_GET_back.sh [QUESTION_NUMBER]
#
# Risk: read
#
# Notes:
# - Copied from EndUser/API 2.0/bash/03.Myself/06.myself_secretQuestion_GET.sh.
# - QUESTION_NUMBER is the number of the question 03 picked (default 1): it is compared with that one of the list.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"

QUESTION_NUMBER="${1:-1}"
if ! [[ "${QUESTION_NUMBER}" =~ ^[1-9][0-9]*$ ]]; then
    printf "Usage: ./04.secretQuestion_GET_back.sh [QUESTION_NUMBER]\n"
    printf "  QUESTION_NUMBER  the number of the question 03 picked, in the list 01.secretQuestions_GET.sh prints (default 1)\n"
    exit 2
fi
st_session

st_list_questions || exit $?
WANTED=$(echo "${QUESTIONS}" | jq -r --argjson n "${QUESTION_NUMBER}" '.[$n - 1] // empty')
result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/myself/secretQuestion" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
[[ "${code}" == 200 ]] || { echo "HTTP ${code}: ${result%???}"; exit 1; }
HAVE=$(echo "${result%???}" | jq -r '.secretQuestion // empty')
echo "The account's question: ${HAVE}"
if [ "${HAVE}" = "${WANTED}" ]; then
    echo "It is question number ${QUESTION_NUMBER} of the list."
else
    echo "It is not question number ${QUESTION_NUMBER} (${WANTED})."
    exit 1
fi
