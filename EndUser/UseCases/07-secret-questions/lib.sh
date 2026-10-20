#!/bin/bash
# ==============================================================================
# Script Name: lib.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# Sourced by every script of this use case. Loads ../session.sh (the settings, the cookie jar session.cookie.jar of this use case, st_session and st_enc), and names what the scripts take from the environment.
#
# Usage:
# source lib.sh
#
# Risk: none
# ==============================================================================

UC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${UC_DIR}/../session.sh"

# Which of the questions on offer to pick, counted from 1, and the answer to give. 03 changes the account and
# cannot be undone (a secret question cannot be cleared once set), so it does nothing without an answer.
QUESTION_NUMBER="${ST_SECRET_QUESTION_NUMBER:-1}"
SECRET_ANSWER="${ST_SECRET_ANSWER:-}"

# st_list_questions: the questions on offer into QUESTIONS (a JSON list); returns 3 when the service is off
st_list_questions() {
    local result code
    result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/secretQuestions" -H "accept: application/json" -H "Referer: ${REFERER}")
    code=${result: -3}
    case "${code}" in
        200) QUESTIONS="${result%???}"; return 0 ;;
        503) echo "The secret question service is not enabled on this server (HTTP 503). An administrator switches it on: the server option Users.SecretQuestion.Enabled."; return 3 ;;
        *)   echo "Could not list the secret questions (HTTP ${code}): ${result%???}"; return 1 ;;
    esac
}
