#!/bin/bash
# ==============================================================================
# Script Name: 01.accounts_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-28
# Location: Sofia
# ==============================================================================
# Description:
# Onboarding, step 1: make the account. POST /accounts creates a user account with a home folder, a password and an email address (the address is what lets the user share folders). The
# password is generated here and kept in state.local.password: the server never shows it again.
#
# Usage:
# ./01.accounts_POST.sh [NAME] [EMAIL]
#
#   NAME   the account to create; it must start with example_ (default example_onboard)
#   EMAIL  its email address (default NAME@example.com)
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/05.Accounts/02.accounts_POST.sh, for one user account.
# - The account is read first (HEAD): one that exists is not made again, and the script says so.
# - The user id is the same for the same name every time (50000 to 59999). A home folder keeps the uid of its first owner, and an account made later under the same name with another uid cannot create a
#   folder in it (see 06 and the README).
# - The password is in state.local.password, which git ignores. It is written once, with a mode that only you can read.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./01.accounts_POST.sh [NAME] [EMAIL]"
if [ "$#" -gt 2 ]; then printf "%s parameters were given, and at most 2 are taken: NAME and EMAIL.\n%s\n" "$#" "${USAGE}"; exit 2; fi
NAME="${1:-${DEFAULT_NAME}}"
EMAIL="${2:-${NAME}@example.com}"
uc_check_name "${NAME}" "${USAGE}"
st_session

NAME_URI=$(printf '%s' "${NAME}" | jq -Rr @uri)
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" --head "${ST_URL}/accounts/${NAME_URI}" -H "accept: */*" -H "Referer: ${REFERER}")
if [ "${code}" = "200" ]; then
    echo "The account ${NAME} already exists. Nothing was created. Remove it with 99.cleanup_DELETE.sh ${NAME}, or give another name."
    exit 1
elif [ "${code}" != "404" ]; then
    echo "Could not tell whether the account ${NAME} exists (HTTP ${code}). Nothing was created."
    exit 1
fi

PASSWORD="Ex1!$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12)"
UID_NUMBER=$(uc_uid "${NAME}")
BODY=$(jq -cn --arg name "${NAME}" --arg email "${EMAIL}" --arg password "${PASSWORD}" --arg uid "${UID_NUMBER}" \
  '{name: $name, type: "user", homeFolder: ("/home/" + $name), uid: $uid, gid: $uid, contact: {email: $email}, user: {name: $name, passwordCredentials: {password: $password}}}')
headers=$(mktemp)
echo "Creating the account ${NAME} (home /home/${NAME}, user id ${UID_NUMBER}, email ${EMAIL})..."
result=$(curl -k -s -w "\n%{http_code}" -D "${headers}" -b "${JAR}" -X POST "${ST_URL}/accounts" -H "accept: */*" -H "Referer: ${REFERER}" \
         -H "Content-Type: application/json" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)" -d "${BODY}")
code="${result##*$'\n'}"
echo "HTTP ${code}"
if [ "${code}" != "201" ]; then
    echo "${result%$'\n'*}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || echo "${result%$'\n'*}"
    rm -f "${headers}"
    exit 1
fi
echo "It is at $(tr -d '\r' < "${headers}" | sed -n 's/^[Ll]ocation: *//p')"
rm -f "${headers}"
umask 077
printf '%s' "${PASSWORD}" > "${PASSWORD_FILE}"
echo "The password is in $(basename "${PASSWORD_FILE}"): the server never shows it again."
