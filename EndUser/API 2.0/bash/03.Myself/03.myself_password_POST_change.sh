#!/bin/bash
# ==============================================================================
# Script Name: 03.myself_password_POST_change.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script changes the logged-in user's password, using the
# `/myself/password?operation=change` endpoint. It demonstrates:
# - Sending the operation twice, as the API requires: in the query string and
#   in the body
# - Logging in again with the new password, since the change ends the session
#
# Usage:
# ./03.myself_password_POST_change.sh NEW_PASSWORD
#
# Risk: write - changes the password of the end user it logs in as
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# - The old password is ST_PASSWORD. Afterwards, put the new one in
#   set_variables.local.sh, or the next login fails.
# - Confirmed directly: the session ends with the change, and the next call
#   with the old cookie answers 401. This script logs in again, so the cookie
#   jar is ready for the other examples.
# - A wrong old password answers 400 "Old password is not correct." The new one
#   must also meet the account's password policy (see 01.myself_GET.sh).
# - Requires `jq`, which builds the body.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

NEW_PASSWORD="$1"
if [ -z "${NEW_PASSWORD}" ]; then
    printf "Usage: ./03.myself_password_POST_change.sh NEW_PASSWORD\n"
    exit 2
fi
if [ ! -f "${COOKIE}" ]; then
    printf "There is no session. Run 01.Authenticate/01.myself_POST.sh first.\n"
    exit 1
fi

BODY=$(jq -n --arg old "${ST_PASSWORD}" --arg new "${NEW_PASSWORD}" \
  '{operation: "change", oldPassword: $old, newPassword: $new}')

printf "Changing the password of %s...\n" "${ST_USER}"
RESPONSE=$(curl -s -k -b "${COOKIE}" -X POST "${ST_URL}/myself/password?operation=change" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf '%s\nHTTP %s\n' "${RESPONSE%$'\n'*}" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "200" ] || exit 1

#
# The change ended the session: log in again with the new password
#
printf "Logging in again with the new password...\n"
LOGIN_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" --cookie-jar "${COOKIE}" \
  -u "${ST_USER}:${NEW_PASSWORD}" -X POST "${ST_URL}/myself" \
  -H "accept: application/json" -H "${REFERER_HEADER}")
if [ "${LOGIN_CODE}" != "200" ]; then
    printf "The login with the new password failed (HTTP %s).\n" "${LOGIN_CODE}"
    exit 1
fi
printf "Logged in. Put the new password in set_variables.local.sh as ST_PASSWORD.\n"
