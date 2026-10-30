#!/bin/bash
# ==============================================================================
# Script Name: 06.business_units_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Part 2, usage per business unit, step 1: make something to measure. Three business units, example_use_bu1 to example_use_bu3, and two user accounts in each: example_use_a1 and b1, c1 and d1, e1 and f1. An account belongs to a business unit through the field businessUnit that it is created with, and its home folder is under the base folder of the unit.
#
# Usage:
# ./06.business_units_POST.sh
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/12.BusinessUnits/01.businessUnits_POST.sh and from Admin/API 2.0/bash/05.Accounts/02.accounts_POST.sh (the account carries businessUnit).
# - The six accounts have one generated password, kept in state.local.password (git ignores it): 07 logs in with it on the End User API.
# - Each object is read first (HEAD): one that exists is not made again, and the script stops with exit 1 and says which. Remove them with 99.cleanup_DELETE.sh.
# - The user ids are fixed (see lib.sh): a home folder keeps the uid of its first owner, and an account made again with another uid cannot write into it (403). The home folders stay on the server after the
#   cleanup, so the same ids are used every time.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./06.business_units_POST.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
st_session

exists() {      # RESOURCE/NAME: HEAD, 200 is there, 404 is not
    local code
    code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" --head "${ST_URL}/$1" -H "accept: */*" -H "Referer: ${REFERER}")
    case "${code}" in
        200) return 0 ;;
        404) return 1 ;;
        *) echo "Could not tell whether $1 exists (HTTP ${code}). Nothing more was created."; exit 1 ;;
    esac
}

post() {        # RESOURCE JSON: POST, prints the Location header; any other answer than 201 is exit 1
    local headers result code
    headers=$(mktemp)
    result=$(curl -k -s -w "\n%{http_code}" -D "${headers}" -b "${JAR}" -X POST "${ST_URL}/$1" -H "accept: */*" -H "Referer: ${REFERER}" \
             -H "Content-Type: application/json" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)" -d "$2")
    code="${result##*$'\n'}"
    if [ "${code}" != "201" ]; then
        printf "POST /%s: HTTP %s\n" "$1" "${code}"
        echo "${result%$'\n'*}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || echo "${result%$'\n'*}"
        rm -f "${headers}"
        exit 1
    fi
    printf "  HTTP 201, it is at %s\n" "$(tr -d '\r' < "${headers}" | sed -n 's/^[Ll]ocation: *//p')"
    rm -f "${headers}"
}

for LINE in "${UC_BUS[@]}" "${UC_ACCOUNTS[@]}"; do
    NAME="${LINE%% *}"
    case "${NAME}" in example_use_bu*) RESOURCE="businessUnits/${NAME}" ;; *) RESOURCE="accounts/${NAME}" ;; esac
    if exists "${RESOURCE}"; then
        echo "${NAME} exists already. Nothing more was created. Remove it with 99.cleanup_DELETE.sh."
        exit 1
    fi
done

for NAME in "${UC_BUS[@]}"; do
    echo "Creating the business unit ${NAME} (base folder /home/${NAME})..."
    post businessUnits "$(jq -cn --arg name "${NAME}" '{name: $name, baseFolder: ("/home/" + $name)}')"
done

PASSWORD="Ex1!$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12)"
for LINE in "${UC_ACCOUNTS[@]}"; do
    read -r NAME BU UID_NUMBER GID_NUMBER _ <<< "${LINE}"
    echo "Creating the account ${NAME} in ${BU} (home /home/${BU}/${NAME}, user id ${UID_NUMBER}, group ${GID_NUMBER})..."
    post accounts "$(jq -cn --arg name "${NAME}" --arg bu "${BU}" --arg password "${PASSWORD}" --arg uid "${UID_NUMBER}" --arg gid "${GID_NUMBER}" \
      '{name: $name, type: "user", businessUnit: $bu, homeFolder: ("/home/" + $bu + "/" + $name), uid: $uid, gid: $gid, user: {name: $name, passwordCredentials: {password: $password}}}')"
done
umask 077
printf '%s' "${PASSWORD}" > "${PASSWORD_FILE}"
echo "The password of the six accounts is in $(basename "${PASSWORD_FILE}"): the server never shows it again."
