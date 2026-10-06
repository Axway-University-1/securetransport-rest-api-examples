#!/bin/bash
# ==============================================================================
# Script Name: 04.myself_password_POST_requestLink.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script asks for a password reset email, for a user who has forgotten the
# password, using the `/myself/password?operation=requestLink` endpoint. The
# email carries a security token; 05.myself_password_POST_reset.sh sets a new
# password with it.
#
# Usage:
# ./04.myself_password_POST_requestLink.sh EMAIL [USERNAME]
#
#   EMAIL     the email address of the account
#   USERNAME  the account's login name, which the server may also require
#             (default ST_USER)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced. Only
#   ST_SERVER, ST_PORT and ST_USER are used: the user has no password to log in
#   with, so there is no session and no credentials are sent.
# - The operation goes in the query string and in the body, as the API requires.
# - Not confirmed on a real server: it sends a real email. The server must be
#   set up to send mail, and the account must have that email address.
# - Requires `jq`, which builds the body.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

EMAIL="$1"
USERNAME="${2:-${ST_USER}}"
if [ -z "${EMAIL}" ]; then
    printf "Usage: ./04.myself_password_POST_requestLink.sh EMAIL [USERNAME]\n"
    exit 2
fi

BODY=$(jq -n --arg email "${EMAIL}" --arg username "${USERNAME}" \
  '{operation: "requestLink", email: $email, username: $username}')

printf "Asking for a password reset email to %s...\n" "${EMAIL}"
curl -s -k -X POST "${ST_URL}/myself/password?operation=requestLink" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "${BODY}" -w "\nHTTP %{http_code}\n"
