#!/bin/bash
# ==============================================================================
# Script Name: 05.myself_password_POST_reset.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script sets a new password for a user who has forgotten the old one,
# using the `/myself/password?operation=reset` endpoint and the security token
# from the email 04.myself_password_POST_requestLink.sh asked for.
#
# Usage:
# ./05.myself_password_POST_reset.sh TOKEN NEW_PASSWORD [SECRET_ANSWER [USERNAME]]
#
#   TOKEN          the security token from the password reset email
#   NEW_PASSWORD   the password to set
#   SECRET_ANSWER  the answer to the account's secret question, when the secret
#                  question service is enabled and the user has set one. See
#                  07.myself_secretQuestion_GET.sh, which reads the question
#                  with the same token.
#   USERNAME       the account's login name, which the server may also require
#                  (default ST_USER)
#
# Risk: write - resets the end user's password
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced. Only
#   ST_SERVER, ST_PORT and ST_USER are used: the token authenticates the user,
#   so there is no session and no credentials are sent.
# - The operation goes in the query string and in the body, as the API requires.
# - Not confirmed on a real server: the token only comes by email.
# - Requires `jq`, which builds the body.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

TOKEN="$1"
NEW_PASSWORD="$2"
SECRET_ANSWER="$3"
USERNAME="${4:-${ST_USER}}"
if [ -z "${TOKEN}" ] || [ -z "${NEW_PASSWORD}" ]; then
    printf "Usage: ./05.myself_password_POST_reset.sh TOKEN NEW_PASSWORD [SECRET_ANSWER [USERNAME]]\n"
    exit 2
fi

# The secret answer is only sent when one was given
BODY=$(jq -n --arg token "${TOKEN}" --arg new "${NEW_PASSWORD}" --arg answer "${SECRET_ANSWER}" \
  --arg username "${USERNAME}" \
  '{operation: "reset", token: $token, newPassword: $new, username: $username}
   + (if $answer == "" then {} else {secretAnswer: $answer} end)')

printf "Resetting the password of %s...\n" "${USERNAME}"
curl -s -k -X POST "${ST_URL}/myself/password?operation=reset" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "${BODY}" -w "\nHTTP %{http_code}\n"
