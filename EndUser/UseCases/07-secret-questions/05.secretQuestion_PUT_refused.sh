#!/bin/bash
# ==============================================================================
# Script Name: 05.secretQuestion_PUT_refused.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# What a refused change looks like. Three attempts that must fail, each with its 400: a question that is not on the list, a wrong password, and an empty answer. None of them changes the account.
#
# Usage:
# ./05.secretQuestion_PUT_refused.sh
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/03.Myself/07.myself_secretQuestion_PUT.sh, with bodies that are meant to be refused.
# - The first two answer {"errors":[{"code":"error.secretQuestion.notFound" / "error.password.invalid", "detail":...}]}; the empty answer answers {"message":"Error validating request","validationErrors":["secretAnswer may not be empty"]}: two shapes of error for one call.
# - A wrong password in the body is a 400 here, not a failed login: it does not count towards locking the account (checked).
# - It sends nothing that would be accepted, so the account is as it was.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

st_list_questions || exit $?
QUESTION=$(echo "${QUESTIONS}" | jq -r '.[0]')
failures=0
# attempt LABEL PASSWORD QUESTION ANSWER: a PUT that has to be refused with 400
attempt() {
    local label="$1" body result code
    body=$(jq -n --arg password "$2" --arg question "$3" --arg answer "$4" '{password: $password, secretQuestion: $question, secretAnswer: $answer}')
    result=$(curl -k -s -w "\n%{http_code}" -b "${JAR}" -X PUT "${ST_URL}/myself/secretQuestion" -H "accept: application/json" -H "Referer: ${REFERER}" -H "Content-Type: application/json" -d "${body}")
    code="${result##*$'\n'}"
    echo "${label}: HTTP ${code}: $(echo "${result%$'\n'*}" | jq -r '(.errors[0].code // .validationErrors[0] // .message) // empty' 2>/dev/null)"
    [[ "${code}" == 400 ]] || failures=$((failures + 1))
}
attempt "A question that is not on the list" "${ST_PASSWORD}" "Is this question on the list?" "an answer"
attempt "A wrong password"                   "not-the-password" "${QUESTION}" "an answer"
attempt "An empty answer"                    "${ST_PASSWORD}" "${QUESTION}" ""
[ "${failures}" -eq 0 ] || { echo "${failures} attempt(s) were not refused with 400."; exit 1; }
echo "All three were refused, and the account is unchanged."
