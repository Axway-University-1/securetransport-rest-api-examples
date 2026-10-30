#!/bin/bash
# ==============================================================================
# Script Name: 01.object_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Changing an object, step 1: make the two throwaway objects the other steps change. A user account called NAME (text, numbers, true/false values and nested objects) and a simple route called NAME_route with two steps
# (a list). Nothing else on the server is touched by this use case, except the one option of step 11, which it puts back.
#
# Usage:
# ./01.object_POST.sh [NAME]
#
#   NAME  the account to make; the route is NAME_route. It must start with example_ (default example_chg)
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/05.Accounts/02.accounts_POST.sh (the account) and 09.CompositeRoutes/03.routes_POST_simple_compress.sh (a simple route with steps; these two steps are EncodingConversion, which needs
#   no site and no other object).
# - Both are looked for first (HEAD): when one exists nothing is made, and the script says so. The id of the route comes from the Location header and is kept in state.local.route_id (git ignores it).
# - The account is never logged in to, so its password is generated here and thrown away.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./01.object_POST.sh [NAME]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: NAME.\n%s\n" "$#" "${USAGE}"; exit 2; fi
NAME="${1:-${DEFAULT_NAME}}"
uc_check_name "${NAME}" "${USAGE}"
st_session
uc_init "${NAME}"

code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" --head "${ACCOUNT_URL}" -H "accept: */*" -H "Referer: ${REFERER}")
if [ "${code}" = "200" ]; then
    echo "The account ${NAME} already exists. Nothing was created. Remove it with 99.cleanup_DELETE.sh ${NAME}, or give another name."
    exit 1
elif [ "${code}" != "404" ]; then
    echo "Could not tell whether the account ${NAME} exists (HTTP ${code}). Nothing was created."
    exit 1
fi
if [ -n "$(uc_route_id)" ]; then
    echo "The route ${ROUTE_NAME} already exists. Nothing was created. Remove it with 99.cleanup_DELETE.sh ${NAME}, or give another name."
    exit 1
fi

PASSWORD="Ex1!$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12)"
UID_NUMBER=$(uc_uid "${NAME}")
BODY=$(jq -cn --arg name "${NAME}" --arg email "${NAME}@example.com" --arg password "${PASSWORD}" --arg uid "${UID_NUMBER}" \
  '{name: $name, type: "user", homeFolder: ("/home/" + $name), uid: $uid, gid: $uid, contact: {email: $email}, user: {name: $name, passwordCredentials: {password: $password}}}')
echo "Creating the account ${NAME}..."
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X POST "${ST_URL}/accounts" -H "accept: */*" -H "Referer: ${REFERER}" \
       -H "Content-Type: application/json" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)" -d "${BODY}")
echo "HTTP ${code}"
[ "${code}" = "201" ] || { echo "The account was not made."; exit 1; }

BODY=$(jq -cn --arg name "${ROUTE_NAME}" --argjson one "$(uc_step '*.one')" --argjson two "$(uc_step '*.two')" \
  '{name: $name, type: "SIMPLE", conditionType: "ALWAYS", description: "made by the use case 05-changing-an-object", steps: [$one, $two]}')
echo "Creating the route ${ROUTE_NAME} with two steps (file filters *.one and *.two)..."
headers=$(mktemp)
code=$(curl -k -s -o /dev/null -w "%{http_code}" -D "${headers}" -b "${JAR}" -X POST "${ST_URL}/routes" -H "accept: */*" -H "Referer: ${REFERER}" \
       -H "Content-Type: application/json" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)" -d "${BODY}")
echo "HTTP ${code}"
location=$(tr -d '\r' < "${headers}" | sed -n 's/^[Ll]ocation: *//p' | tail -n 1)
rm -f "${headers}"
[ "${code}" = "201" ] || { echo "The route was not made. The account ${NAME} was: remove it with 99.cleanup_DELETE.sh ${NAME}."; exit 1; }
if [ -z "${location}" ]; then
    echo "The server gave no Location header, so the id of the route is not known. Remove the objects with 99.cleanup_DELETE.sh ${NAME}."
    exit 1
fi
printf '%s' "${location##*/}" > "${ROUTE_ID_FILE}"
echo "The route is ${location##*/} (kept in $(basename "${ROUTE_ID_FILE}"))."
