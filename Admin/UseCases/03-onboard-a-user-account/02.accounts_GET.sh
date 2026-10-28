#!/bin/bash
# ==============================================================================
# Script Name: 02.accounts_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-28
# Location: Sofia
# ==============================================================================
# Description:
# Onboarding, step 2: read the account back. HEAD says whether it exists, GET reads it, and the fields an administrator cares about are shown with what each one means.
#
# Usage:
# ./02.accounts_GET.sh [NAME]
#
#   NAME  the account to read (default example_onboard)
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/05.Accounts/03.accounts_name_HEAD.sh and 04.accounts_name_GET.sh.
# - The password is never returned: the answer has "password": null. (It does hold a salted digest of it, which is not the password.)
# - accountCreationDate is a timestamp in milliseconds (see Features/Guidance/time-formats.md); lastModified is RFC 2822 text with an offset.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./02.accounts_GET.sh [NAME]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: NAME.\n%s\n" "$#" "${USAGE}"; exit 2; fi
NAME="${1:-${DEFAULT_NAME}}"
uc_check_name "${NAME}" "${USAGE}"
st_session

NAME_URI=$(printf '%s' "${NAME}" | jq -Rr @uri)
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" --head "${ST_URL}/accounts/${NAME_URI}" -H "accept: */*" -H "Referer: ${REFERER}")
echo "HEAD: HTTP ${code}"
if [ "${code}" = "404" ]; then
    echo "There is no account ${NAME}. Run 01.accounts_POST.sh first."
    exit 1
elif [ "${code}" != "200" ]; then
    echo "Could not tell whether the account ${NAME} exists."
    exit 1
fi
result=$(curl -k -s -w "\n%{http_code}" -b "${JAR}" -X GET "${ST_URL}/accounts/${NAME_URI}" -H "accept: application/json" -H "Referer: ${REFERER}")
code="${result##*$'\n'}"
echo "GET: HTTP ${code}"
[ "${code}" = "200" ] || { echo "${result%$'\n'*}"; exit 1; }
echo "${result%$'\n'*}" | jq -r '
  "  name                        \(.name)",
  "      the login name",
  "  type                        \(.type)",
  "      user: a person or a program that logs in (service and template accounts are other types)",
  "  homeFolder                  \(.homeFolder)",
  "      where its files are, on the server",
  "  email                       \(.contact.email // "none")",
  "      needed to share folders; shown to collaborators",
  "  disabled                    \(.disabled)",
  "      true: the account exists but cannot log in",
  "  locked                      \(.user.locked)",
  "      true after \(.user.failedAuthMaximum // "?") wrong passwords; only an administrator unlocks it",
  "  accountCreationDate         \((.accountCreationDate / 1000 | todate) // "?") (UTC)",
  "      when the account was made",
  "  secret question set         \(if .user.secretQuestion.secretQuestion == null then "no" else "yes" end)",
  "      a question the user answers to reset the password",
  "  transfersWebServiceAllowed  \(.transfersWebServiceAllowed)",
  "      whether the End User API /transfers may be used by this account",
  "  password                    \(.user.passwordCredentials.password // "null")",
  "      the password is never returned"'
