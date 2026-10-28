#!/bin/bash
# ==============================================================================
# Script Name: 04.enduser_login_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-28
# Location: Sofia
# ==============================================================================
# Description:
# Onboarding, step 4: prove the account works. GET /myself on the End User API as the new user, with Basic authentication (the password of state.local.password). Then the same call with a wrong
# password, on purpose, to see what a refusal looks like.
#
# Usage:
# ./04.enduser_login_GET.sh [NAME]
#
#   NAME  the account to log in as (default example_onboard)
#
# Risk: read
#
# Notes:
# - Copied from EndUser/API 2.0/bash/03.Myself/01.myself_GET.sh, with Basic authentication instead of a session.
# - The End User API is on its own port: ST_ENDUSER_PORT when the settings set it (add `export ST_ENDUSER_PORT=8443` to set_variables.local.sh), otherwise the admin port minus one. That guess is wrong on
#   some installs (see .claude/skills/st-api-gotchas), and a connection that fails says so.
# - A wrong password and an unknown user are answered the same way (401): the answer does not tell which. Features/Guidance/authentication-and-sessions.md has the rest.
# - Three wrong passwords lock the account: this step sends ONE wrong password.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./04.enduser_login_GET.sh [NAME]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: NAME.\n%s\n" "$#" "${USAGE}"; exit 2; fi
NAME="${1:-${DEFAULT_NAME}}"
uc_check_name "${NAME}" "${USAGE}"
if [ ! -s "${PASSWORD_FILE}" ]; then
    echo "There is no $(basename "${PASSWORD_FILE}"): run 01.accounts_POST.sh first (it makes the password)."
    exit 2
fi
PASSWORD=$(cat "${PASSWORD_FILE}")

echo "GET ${EU_URL}/myself as ${NAME}"
result=$(curl -k -s -w "\n%{http_code}" -u "${NAME}:${PASSWORD}" -X GET "${EU_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}")
code="${result##*$'\n'}"
echo "HTTP ${code}"
if [ "${code}" = "000" ]; then
    echo "No answer from ${ST_SERVER}:${ST_ENDUSER_PORT}. The End User API has its own port: set ST_ENDUSER_PORT in set_variables.local.sh."
    exit 1
elif [ "${code}" != "200" ]; then
    echo "${result%$'\n'*}"
    echo "The new account could not log in."
    exit 1
fi
echo "${result%$'\n'*}" | jq -r '"Logged in as \(.name) (\(.type)); sharingAllowed: \(.sharingAllowed)"'

echo "Now a wrong password, on purpose:"
code=$(curl -k -s -o /dev/null -w "%{http_code}" -u "${NAME}:not-the-password" -X GET "${EU_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "HTTP ${code}"
if [ "${code}" = "401" ]; then
    echo "Refused, as it should be. The answer is the same for a wrong password and for a user that does not exist."
else
    echo "A wrong password was answered ${code}, not 401."
    exit 1
fi
