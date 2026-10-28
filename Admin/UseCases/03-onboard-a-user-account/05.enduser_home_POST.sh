#!/bin/bash
# ==============================================================================
# Script Name: 05.enduser_home_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-28
# Location: Sofia
# ==============================================================================
# Description:
# Onboarding, step 5: use the home folder. As the new user, make a folder, upload a small file into it and list it, over the End User API. This is what the account is for, and it shows that the home folder
# the account was given works.
#
# Usage:
# ./05.enduser_home_POST.sh [NAME]
#
#   NAME  the account to work as (default example_onboard)
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/02.Files/02.files_name_POST_folder.sh and 04.files_filepath_POST.sh, with Basic authentication instead of a session.
# - A folder directly in the home is the check that matters: if the home folder is owned by another user id, this POST is 403 (see the README of this use case).
# - The folder and the file stay: step 06 empties the home before the account is deleted.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./05.enduser_home_POST.sh [NAME]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: NAME.\n%s\n" "$#" "${USAGE}"; exit 2; fi
NAME="${1:-${DEFAULT_NAME}}"
uc_check_name "${NAME}" "${USAGE}"
if [ ! -s "${PASSWORD_FILE}" ]; then
    echo "There is no $(basename "${PASSWORD_FILE}"): run 01.accounts_POST.sh first (it makes the password)."
    exit 2
fi
PASSWORD=$(cat "${PASSWORD_FILE}")
FOLDER="welcome"

echo "Making the folder ${FOLDER} in the home of ${NAME}..."
BODY=$(jq -n '{isDirectory: true, isRegularFile: false, isSymbolicLink: false, isOther: false, isShared: false}')
code=$(curl -k -s -o /dev/null -w "%{http_code}" -u "${NAME}:${PASSWORD}" -X POST "${EU_URL}/files/${FOLDER}" -H "accept: application/json" -H "Referer: ${REFERER}" \
       -H "Content-Type: application/json" -d "${BODY}")
echo "HTTP ${code}"
case "${code}" in
    20*) ;;
    409) echo "The folder ${FOLDER} is already there." ;;
    403) echo "The server refused (403). If this account's home folder was made by an earlier account of the same name with another user id, use another name."; exit 1 ;;
    *) echo "The folder was not made."; exit 1 ;;
esac

TMP=$(mktemp)
trap 'rm -f "${TMP}"' EXIT
printf 'Welcome, %s.\n' "${NAME}" > "${TMP}"
echo "Uploading hello.txt into ${FOLDER}..."
code=$(curl -k -s -o /dev/null -w "%{http_code}" -u "${NAME}:${PASSWORD}" -X POST "${EU_URL}/files/${FOLDER}" -H "accept: application/json" -H "Referer: ${REFERER}" \
       -F "file=@${TMP};filename=hello.txt")
echo "HTTP ${code}"
[[ "${code}" == 20* ]] || { echo "The file was not uploaded."; exit 1; }

echo "The folder now holds:"
curl -k -s -u "${NAME}:${PASSWORD}" -X GET "${EU_URL}/files/${FOLDER}" -H "accept: application/json" -H "Referer: ${REFERER}" | jq -r '(.files // [])[] | "  \(.fileName)\t\(.size) bytes"'
