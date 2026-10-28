#!/bin/bash
# ==============================================================================
# Script Name: 06.accounts_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-28
# Location: Sofia
# ==============================================================================
# Description:
# Onboarding, step 6: take the account away again. The home folder is emptied first, as the user, over the End User API (the Admin API cannot browse files). Then DELETE /accounts/{name}, and a read that
# says it is gone.
#
# Usage:
# ./06.accounts_DELETE.sh [NAME]
#
#   NAME  the account to delete (default example_onboard)
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/05.Accounts/07.accounts_name_DELETE.sh.
# - Deleting an account does not delete its home folder: /home/NAME stays on the server, owned by the user id the account had (50000 to 59999 here, the same for the same name). An account made later under the same name
#   with ANOTHER user id cannot create a folder in it (403). That is why 01 gives the same name the same id, and why this step empties the home first. See the README.
# - Without state.local.password (the password of the account) the home cannot be emptied: the script says so and deletes the account anyway.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./06.accounts_DELETE.sh [NAME]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: NAME.\n%s\n" "$#" "${USAGE}"; exit 2; fi
NAME="${1:-${DEFAULT_NAME}}"
uc_check_name "${NAME}" "${USAGE}"
st_session

NAME_URI=$(printf '%s' "${NAME}" | jq -Rr @uri)
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" --head "${ST_URL}/accounts/${NAME_URI}" -H "accept: */*" -H "Referer: ${REFERER}")
if [ "${code}" = "404" ]; then
    echo "There is no account ${NAME}: nothing to delete."
    exit 0
elif [ "${code}" != "200" ]; then
    echo "Could not tell whether the account ${NAME} exists (HTTP ${code}). Nothing was deleted."
    exit 1
fi

if [ -s "${PASSWORD_FILE}" ]; then
    uc_empty_home "${NAME}" "$(cat "${PASSWORD_FILE}")"
else
    echo "There is no $(basename "${PASSWORD_FILE}"): the home folder cannot be emptied as the user, so its files stay."
fi

code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X DELETE "${ST_URL}/accounts/${NAME_URI}" -H "accept: application/json" -H "Referer: ${REFERER}" \
       -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)")
echo "DELETE: HTTP ${code}"
[ "${code}" = "204" ] || { echo "The account was not deleted."; exit 1; }
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/accounts/${NAME_URI}" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "GET: HTTP ${code}"
[ "${code}" = "404" ] || { echo "The account is still there."; exit 1; }
echo "The account ${NAME} is gone. Its home folder /home/${NAME} is not: it stays on the server with user id $(uc_uid "${NAME}"). Give a new account of the same name the same user id (01 does), or another name."
rm -f "${PASSWORD_FILE}"
