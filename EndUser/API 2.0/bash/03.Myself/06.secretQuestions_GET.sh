#!/bin/bash
# ==============================================================================
# Script Name: 06.secretQuestions_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the secret questions a user can choose from, using the
# `/secretQuestions` endpoint. 08.myself_secretQuestion_PUT.sh sets one of them.
#
# Usage:
# ./06.secretQuestions_GET.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - When the secret question service is not configured or enabled, the answer
#   is 503, error.secretQuestion.serviceDisabled (confirmed directly). This
#   script says so and exits 3.
# - Requires `jq`, which prints one question per line.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

if [ ! -f "${COOKIE}" ]; then
    printf "There is no session. Run 01.Authenticate/01.myself_POST.sh first.\n"
    exit 1
fi

RESPONSE=$(curl -s -k -b "${COOKIE}" -X GET "${ST_URL}/secretQuestions" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"

case "${HTTP_CODE}" in
    200)
        printf "The secret questions to choose from:\n"
        printf '%s' "${BODY}" | jq -r '.[] | "  " + .'
        ;;
    503)
        printf "The secret question service is not enabled on this server:\n%s\n" "${BODY}"
        exit 3
        ;;
    *)
        printf "Could not list the secret questions (HTTP %s):\n%s\n" "${HTTP_CODE}" "${BODY}"
        exit 1
        ;;
esac
