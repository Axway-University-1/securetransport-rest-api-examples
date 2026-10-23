#!/bin/bash
# ==============================================================================
# Script Name: 00.run_all.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# Runs the whole use case in order (01 to 05), then 99. It stops at the first script that fails; the cleanup still runs. Without the answer and the number of the question it stops at once, before anything is done. A number that is not one of the questions the server offers (it asks, once) ends the session it opened and stops before any step.
#
# Usage:
# ./00.run_all.sh ANSWER QUESTION_NUMBER
#
# Risk: write
#
# Notes:
# - ANSWER and QUESTION_NUMBER are those of 03.secretQuestion_PUT.sh, and both are required here (exit 2, nothing is run, not even the login): the run changes the account, and a secret question cannot be cleared.
# - QUESTION_NUMBER is also checked against the questions the server really offers: one login, the list is counted, and a number past the end (exit 2) drops the session at once and runs nothing else.
# - Exit 3 from 01 means the secret question service is switched off: an administrator must switch it on.
# ==============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
ANSWER="$1"
NUMBER="$2"
if [ -z "${ANSWER}" ] || ! [[ "${NUMBER}" =~ ^[1-9][0-9]*$ ]]; then
    printf "Usage: ./00.run_all.sh ANSWER QUESTION_NUMBER\n"
    printf "  ANSWER           the answer to the secret question, in your own words\n"
    printf "  QUESTION_NUMBER  the number of the question in the list 01.secretQuestions_GET.sh prints\n"
    printf "Nothing was done: the whole run changes the account, and a secret question cannot be cleared once it is set, so both are asked for before anything starts.\n"
    exit 2
fi

# The number has to be one of the questions the server offers, which only the server can say: log in, count them, and if
# the number is past the end drop the session at once (99 ends it) and stop, before any step has run. The steps that follow
# use this same session.
source "${DIR}/lib.sh"
st_session
st_list_questions
code=$?
if [ "${code}" -ne 0 ]; then
    bash "${DIR}/99.cleanup_DELETE.sh"
    exit "${code}"
fi
COUNT=$(echo "${QUESTIONS}" | jq 'length')
if [ "${NUMBER}" -gt "${COUNT}" ]; then
    printf "There is no question number %s: the server offers %s (1 to %s). Run 01.secretQuestions_GET.sh to see them.\n" "${NUMBER}" "${COUNT}" "${COUNT}"
    printf "Nothing was changed, and the session is ended.\n"
    bash "${DIR}/99.cleanup_DELETE.sh"
    exit 2
fi
rc=0
# each step: the script, then its arguments (03 takes the answer, which may be empty: then it says how to use it)
for step in "01.secretQuestions_GET" "02.secretQuestion_GET_mine" "03.secretQuestion_PUT" "04.secretQuestion_GET_back" "05.secretQuestion_PUT_refused"; do
    case "${step}" in
        03*) args=("${ANSWER}" "${NUMBER}") ;;
        04*) args=("${NUMBER}") ;;
        *)   args=() ;;
    esac
    printf '\n=== %s %s ===\n' "${step}" "${args[*]}"
    bash "${DIR}/${step}.sh" "${args[@]}"
    code=$?
    # 02 answers 4 for an account with no question yet, and 5 when an administrator asked for a new one: the starting points, not failures
    if [ "${code}" -ne 0 ] && ! { [ "${step}" = "02.secretQuestion_GET_mine" ] && { [ "${code}" -eq 4 ] || [ "${code}" -eq 5 ]; }; }; then
        rc=1; echo "${step} failed."; break
    fi
done
printf '\n=== 99.cleanup_DELETE ===\n'
bash "${DIR}/99.cleanup_DELETE.sh"
exit ${rc}
