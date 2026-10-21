#!/bin/bash
# ==============================================================================
# Script Name: lib.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# Sourced by every script of this use case. Loads ../session.sh (the settings, the cookie jar session.cookie.jar of this use case, st_session and st_enc), and lists the questions.
#
# Usage:
# source lib.sh
#
# Risk: none
# ==============================================================================

UC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${UC_DIR}/../session.sh"

# How the calls authenticate: with the session (the cookie jar). 03 uses Basic authentication instead, see there.
AUTH=(-b "${JAR}")

# st_list_questions: the questions on offer into QUESTIONS (a JSON list); returns 3 when the service is off
st_list_questions() {
    local result code
    result=$(curl -k -s -w "%{http_code}" "${AUTH[@]}" -X GET "${ST_URL}/secretQuestions" -H "accept: application/json" -H "Referer: ${REFERER}")
    code=${result: -3}
    case "${code}" in
        200) QUESTIONS="${result%???}"; return 0 ;;
        503) echo "The secret question service is switched off on this server (HTTP 503). An administrator must switch it on: the server option Users.SecretQuestion.Enabled has to be true."; return 3 ;;
        *)   echo "Could not list the secret questions (HTTP ${code}): ${result%???}"; return 1 ;;
    esac
}
