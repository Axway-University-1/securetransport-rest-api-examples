#!/bin/bash
# ==============================================================================
# Script Name: 03.secretQuestion_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# Sets the secret question and its answer: PUT /myself/secretQuestion with the question (picked from the list by its number), the answer, and the account's own password. A secret question cannot be cleared afterwards, only replaced by running this again.
#
# Usage:
# ./03.secretQuestion_PUT.sh ANSWER [QUESTION_NUMBER]
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/03.Myself/07.myself_secretQuestion_PUT.sh, with the question picked from the list by its number.
# - THIS CHANGES THE ACCOUNT. Nothing clears a secret question (DELETE of /myself/secretQuestion is 405, an empty question or answer is 400): it stays until you run this again with another question or answer, or an administrator asks for a new one (Admin/API 2.0/bash/05.Accounts/06.accounts_name_PATCH_secretQuestion.sh). The answer is never shown again. Use a throwaway account on a lab.
# - ANSWER is the answer to the question. QUESTION_NUMBER is the number 01.secretQuestions_GET.sh prints (default 1).
# - It uses Basic authentication, not a session, on purpose: when an administrator has asked for a new question (02 exit 5) the server refuses the login and every other call, 403 error.secretQuestion.required, but still answers the list and this PUT, which lifts the block.
# - The body carries the account's password (ST_PASSWORD), as the API requires. A wrong one is refused with 400.
# - The question must be one of the list, exactly: an invented one is refused with 400.
# - A password reset can then ask for the answer (03.Myself/05.myself_password_POST_reset.sh).
# - Exit 2 without ANSWER, or with a number that is not on the list (nothing is changed), 3 when the service is switched off.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"

ANSWER="$1"
QUESTION_NUMBER="${2:-1}"
if [ -z "${ANSWER}" ] || ! [[ "${QUESTION_NUMBER}" =~ ^[1-9][0-9]*$ ]]; then
    printf "Usage: ./03.secretQuestion_PUT.sh ANSWER [QUESTION_NUMBER]\n"
    printf "  ANSWER           the answer to the secret question, in your own words\n"
    printf "  QUESTION_NUMBER  the number of the question in the list 01.secretQuestions_GET.sh prints (default 1)\n"
    printf "This changes the account, and a secret question cannot be cleared once it is set: it can only be replaced.\n"
    exit 2
fi
# Basic authentication, with no session: this has to work for an account that an administrator has asked to choose a
# new question, which the server refuses to log in, and for which the list and this PUT are the only calls it answers.
AUTH=(-u "${ST_USER}:${ST_PASSWORD}")

st_list_questions || exit $?
QUESTION=$(echo "${QUESTIONS}" | jq -r --argjson n "${QUESTION_NUMBER}" '.[$n - 1] // empty')
if [ -z "${QUESTION}" ]; then
    echo "There is no question number ${QUESTION_NUMBER}: the list has $(echo "${QUESTIONS}" | jq 'length')."
    exit 2
fi

BODY=$(jq -n --arg password "${ST_PASSWORD}" --arg question "${QUESTION}" --arg answer "${ANSWER}" \
  '{password: $password, secretQuestion: $question, secretAnswer: $answer}')
code=$(curl -k -s -o /dev/null -w "%{http_code}" "${AUTH[@]}" -X PUT "${ST_URL}/myself/secretQuestion" -H "accept: application/json" -H "Referer: ${REFERER}" -H "Content-Type: application/json" -d "${BODY}")
echo "Set the question '${QUESTION}': HTTP ${code}"
[[ "${code}" == 204 ]] || exit 1
