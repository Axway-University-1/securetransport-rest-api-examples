#!/bin/bash
# ==============================================================================
# Script Name: 06.accounts_name_PATCH_secretQuestion.sh
# Author: Plamen Milenkov
# Created: 2026-10-21
# Location: Sofia
# ==============================================================================
# Description:
# This script makes an end user choose a new secret question, using the `/accounts/{name}` endpoint with PATCH.
# It sets `forceSecretQuestionChange` of the account's secret question. While it is set, the user's own call
# GET /myself/secretQuestion answers `error.secretQuestion.required` ("You have to set a new secret question")
# until they set one with PUT /myself/secretQuestion: the nearest an administrator gets to taking a question away.
#
# Usage:
# ./06.accounts_name_PATCH_secretQuestion.sh [NAME [true|false]]
#
#   NAME   the user account (default example_user, the one 02.accounts_POST.sh creates)
#   true|false  force the change (default true), or take the requirement away again
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
# - Nothing clears a secret question. Confirmed directly (5.5-20260924): the end user's DELETE of /myself/secretQuestion is 405,
#   and a PUT with an empty or null question or answer is 400. Here the administrator's PATCH `remove` of /user/secretQuestion, a `replace`
#   of it or of its secretQuestion with null, and a PUT of the whole account without it all answer 204 and change nothing: the question reads back as it was.
#   The only field that takes is forceSecretQuestionChange, which this script sets. A full PUT of the account resets it to false.
# - While it is set the account's login and nearly every call answer 403 error.secretQuestion.required (confirmed): only GET /secretQuestions and the
#   PUT /myself/secretQuestion that sets the new question are answered, with Basic authentication. That PUT lifts it; so does running this again with false.
# - The service must be on (the server option Users.SecretQuestion.Enabled); the question the user then chooses has to be on the list (GET /secretQuestions).
# - The answer is never returned by any call. secretAnswerGuessFailures counts the wrong guesses at it.
# - It reads the account first and says what it found. An account that has no secret question, or that is not a user account (a service account has no `user` object), is left alone (exit 0).
# - Requires `jq`, which reads the account and builds the patch.
# - Exit codes: 0 when the flag is set as asked (or there is no question), 1 when the account cannot be read or the server refuses the patch, 2 when the second argument is not true or false.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${ST_ADMIN_LOCAL_VARIABLES:-${SCRIPT_DIR}/../set_variables.local.sh}" ||
    { echo "Copy set_variables.local.example.sh to set_variables.local.sh and fill it in."; exit 1; }

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts"
NAME="${1:-example_user}"
FORCE="${2:-true}"
if [ "${FORCE}" != "true" ] && [ "${FORCE}" != "false" ]; then
    printf "Usage: ./06.accounts_name_PATCH_secretQuestion.sh [NAME [true|false]]\n"
    exit 2
fi
NAME_URI=$(jq -rn --arg name "${NAME}" '$name | @uri')
ACCOUNT_URL="${MAIN_URL}/${NAME_URI}"

# read: the secret question object of the account, printed on one line; stops the script when the account cannot be read
read_question() {
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${ACCOUNT_URL}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "Could not read the account %s: HTTP %s\n" "${NAME}" "${HTTP_CODE}"
        printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
        exit 1
    fi
    QUESTION=$(printf '%s' "${RESPONSE}" | jq -c '.user.secretQuestion // empty')
}

read_question
if [ -z "${QUESTION}" ]; then
    printf "%s has no secret question (or is not a user account): nothing to force.\n" "${NAME}"
    exit 0
fi
printf "The secret question of %s now: %s\n" "${NAME}" "${QUESTION}"

BODY=$(jq -cn --argjson force "${FORCE}" '[{op: "replace", path: "/user/secretQuestion/forceSecretQuestionChange", value: $force}]')
printf "Setting forceSecretQuestionChange to %s...\n" "${FORCE}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${ACCOUNT_URL}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi

read_question
printf "Read back: %s\n" "${QUESTION}"
if [ "$(printf '%s' "${QUESTION}" | jq -r '.forceSecretQuestionChange')" != "${FORCE}" ]; then
    printf "The flag did not take.\n"
    exit 1
fi
