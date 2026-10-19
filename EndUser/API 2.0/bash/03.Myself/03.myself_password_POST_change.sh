#!/bin/bash
# ==============================================================================
# Script Name: 03.myself_password_POST_change.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script changes the logged-in user's password, using the
# `/myself/password?operation=change` endpoint, proves the new one works, and
# by default puts the old one back, so it can be run again and again. It demonstrates:
# - Sending the operation twice, as the API requires: in the query string and
#   in the body
# - Logging in again after each change, since a change ends the session
#
# Usage:
# ./03.myself_password_POST_change.sh [NEW_PASSWORD] [--keep]
#
#   NEW_PASSWORD  the password to change to (default: a random one, made for this run).
#                 It must meet the account's password policy (see 01.myself_GET.sh).
#   --keep        leave the account on the new password. Without it the script changes back
#                 to ST_PASSWORD at the end, so nothing needs updating afterwards.
#
# Risk: write - changes the password of the end user it logs in as, and changes it back
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
# - It checks for an active session first and, if there is none, logs in with
#   01.Authenticate/01.myself_POST.sh and then carries on.
# - The old password is ST_PASSWORD. With --keep, put the new one in
#   set_variables.local.sh afterwards, or the next login (and the next run) fails: the
#   settings file holds the one password, and this script cannot know it changed.
# - Confirmed directly: the session ends with the change, and the next call
#   with the old cookie answers 401. This script logs in again, so the cookie
#   jar is ready for the other examples.
# - A wrong old password answers 400 "Old password is not correct." A server that
#   remembers recent passwords (recentPasswords in the password policy) or has a
#   minimum password age can refuse the change back: the script then says so and
#   prints the password the account is on, so it can be put in set_variables.local.sh.
# - The random password is not shown, unless the account is left on it.
# - Requires `jq`, which builds the body, and `openssl`, which makes the random password.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${ST_ENDUSER_LOCAL_VARIABLES:-${SCRIPT_DIR}/../set_variables.local.sh}" ||
    { echo "Copy set_variables.local.example.sh to set_variables.local.sh and fill it in."; exit 1; }
export ST_URL="${ST_URL:-https://${ST_SERVER}:${ST_PORT}/api/v2.0}"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
source "${SCRIPT_DIR}/../ensure_session.sh"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

NEW_PASSWORD=""
KEEP=0
for arg in "$@"; do
    case "${arg}" in
        --keep) KEEP=1 ;;
        -*) printf "Usage: ./03.myself_password_POST_change.sh [NEW_PASSWORD] [--keep]\n"; exit 2 ;;
        *) if [ -n "${NEW_PASSWORD}" ]; then
               printf "Usage: ./03.myself_password_POST_change.sh [NEW_PASSWORD] [--keep]\n"; exit 2
           fi
           NEW_PASSWORD="${arg}" ;;
    esac
done
if [ -z "${NEW_PASSWORD}" ]; then
    # Random, with a letter of each kind, a digit and a symbol, so that a password policy accepts it
    NEW_PASSWORD="$(openssl rand -base64 18 | tr -d '/+=')Aa1-"
    printf "No NEW_PASSWORD given: using a random one.\n"
fi
if [ "${NEW_PASSWORD}" = "${ST_PASSWORD}" ]; then
    printf "NEW_PASSWORD is the password the account has already.\n"
    exit 2
fi
st_ensure_session

# change_password OLD NEW: the change itself, answered 200 (it ends the session)
change_password() {
    local body response code
    body=$(jq -n --arg old "$1" --arg new "$2" '{operation: "change", oldPassword: $old, newPassword: $new}')
    response=$(curl -s -k -b "${COOKIE}" -X POST "${ST_URL}/myself/password?operation=change" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
      -d "${body}" -w "\n%{http_code}")
    code="${response##*$'\n'}"
    printf '%s\nHTTP %s\n' "${response%$'\n'*}" "${code}"
    [ "${code}" = "200" ]
}

# login PASSWORD: a new session, in the cookie jar
login() {
    local code
    code=$(curl -s -k -o /dev/null -w "%{http_code}" --cookie-jar "${COOKIE}" \
      -u "${ST_USER}:$1" -X POST "${ST_URL}/myself" \
      -H "accept: application/json" -H "${REFERER_HEADER}")
    if [ "${code}" != "200" ]; then
        printf "The login failed (HTTP %s).\n" "${code}"
        return 1
    fi
}

printf "Changing the password of %s...\n" "${ST_USER}"
change_password "${ST_PASSWORD}" "${NEW_PASSWORD}" || exit 1

#
# The change ended the session: log in again with the new password
#
printf "Logging in again with the new password...\n"
login "${NEW_PASSWORD}" || exit 1
printf "It works.\n"

if [ "${KEEP}" = "1" ]; then
    printf "Put the new password in set_variables.local.sh as ST_PASSWORD.\n"
    exit 0
fi

#
# Put the old password back, so that the next run (and set_variables.local.sh) still match
#
printf "Changing it back...\n"
if ! change_password "${NEW_PASSWORD}" "${ST_PASSWORD}"; then
    printf "The change back was refused. The password of %s is now: %s\n" "${ST_USER}" "${NEW_PASSWORD}"
    printf "Put it in set_variables.local.sh as ST_PASSWORD.\n"
    exit 1
fi
login "${ST_PASSWORD}" || exit 1
printf "Back on the original password, and logged in.\n"
