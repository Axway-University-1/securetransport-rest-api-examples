#!/bin/bash
# ==============================================================================
# Script Name: 01.secretQuestions_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# Which questions can I choose from? GET /secretQuestions lists them, as a plain JSON list of texts. This prints them numbered: the number is what 03 takes.
#
# Usage:
# ./01.secretQuestions_GET.sh
#
# Risk: read
#
# Notes:
# - Copied from EndUser/API 2.0/bash/07.SecretQuestions/01.secretQuestions_GET.sh.
# - The list is the server option Users.SecretQuestions, which an administrator can change.
# - Exit 3 when the service is not enabled (HTTP 503): the server option Users.SecretQuestion.Enabled is false by default.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

st_list_questions || exit $?
echo "The secret questions to choose from:"
echo "${QUESTIONS}" | jq -r 'to_entries[] | "  \(.key + 1)  \(.value)"' 
