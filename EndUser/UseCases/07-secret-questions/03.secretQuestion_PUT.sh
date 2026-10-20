#!/bin/bash
# ==============================================================================
# Script Name: 03.secretQuestion_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# Sets the secret question and its answer: PUT /myself/secretQuestion with the question (one on the list), the answer, and the account's own password. It does nothing unless you give the answer, because a secret question cannot be cleared afterwards.
#
# Usage:
# ST_SECRET_ANSWER='an answer' [ST_SECRET_QUESTION_NUMBER=2] ./03.secretQuestion_PUT.sh
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/03.Myself/07.myself_secretQuestion_PUT.sh, with the question picked from the list by its number.
# - THIS CHANGES THE ACCOUNT AND CANNOT BE UNDONE: DELETE of /myself/secretQuestion is 405, so the question stays until you set another one (the answer is never shown again). Use a throwaway account on a lab.
# - The body carries the account's password (ST_PASSWORD), as the API requires. A wrong one is refused with 400.
# - The question must be one of the list, exactly: an invented one is refused with 400.
# - A password reset can then ask for the answer (03.Myself/05.myself_password_POST_reset.sh).
# - Exit 2 without ST_SECRET_ANSWER or with a number that is not on the list (nothing is sent), 3 when the service is not enabled.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
if [ -z "${SECRET_ANSWER}" ]; then
    echo "Not changing anything: give the answer you want to set, with  export ST_SECRET_ANSWER='an answer'"
    echo "This changes the account, and a secret question cannot be cleared once it is set."
    exit 2
fi
[[ "${QUESTION_NUMBER}" =~ ^[1-9][0-9]*$ ]] || { echo "ST_SECRET_QUESTION_NUMBER must be a whole number above 0: ${QUESTION_NUMBER}"; exit 2; }
st_session

st_list_questions || exit $?
QUESTION=$(echo "${QUESTIONS}" | jq -r --argjson n "${QUESTION_NUMBER}" '.[$n - 1] // empty')
if [ -z "${QUESTION}" ]; then
    echo "There is no question number ${QUESTION_NUMBER}: the list has $(echo "${QUESTIONS}" | jq 'length')."
    exit 2
fi

BODY=$(jq -n --arg password "${ST_PASSWORD}" --arg question "${QUESTION}" --arg answer "${SECRET_ANSWER}" \
  '{password: $password, secretQuestion: $question, secretAnswer: $answer}')
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X PUT "${ST_URL}/myself/secretQuestion" -H "accept: application/json" -H "Referer: ${REFERER}" -H "Content-Type: application/json" -d "${BODY}")
echo "Set the question '${QUESTION}': HTTP ${code}"
[[ "${code}" == 204 ]] || exit 1
