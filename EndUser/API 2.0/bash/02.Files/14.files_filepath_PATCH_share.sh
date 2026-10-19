#!/bin/bash
# ==============================================================================
# Script Name: 14.files_filepath_PATCH_share.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script shares a folder with other users, using the `/files/{filePath}`
# endpoint with PATCH: a JSON Patch document that adds
# sharedDirectoryProperties. 15.files_filepath_PATCH_unshare.sh stops sharing it.
#
# Usage:
# ./14.files_filepath_PATCH_share.sh FOLDER EMAIL [RIGHTS]
#
#   FOLDER  the folder to share, relative to the home folder
#   EMAIL   the email of the user to share it with. Several, comma separated.
#   RIGHTS  1 download (default), 3 download and upload, 7 download, upload and
#           overwrite
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
# - It checks for an active session first and, if there is none, logs in with
#   01.Authenticate/01.myself_POST.sh and then carries on.
# - The account must be allowed to share (sharingAllowed, see
#   01.myself_GET.sh), and the email must be one the server knows: confirmed
#   directly, an unknown one answers 400 "Unable to share folder ... with
#   user ...". 08.myself_addressBook_GET.sh lists the users to share with.
# - Notifications are off here; enableNotifications and
#   enableOwnerNotifications turn them on.
# - Requires `jq`, which builds the body and URL-encodes the path.
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

FOLDER="${1#/}"
FOLDER="${FOLDER%/}"
EMAILS="$2"
RIGHTS="${3:-1}"
if [ -z "${FOLDER}" ] || [ -z "${EMAILS}" ]; then
    printf "Usage: ./14.files_filepath_PATCH_share.sh FOLDER EMAIL [RIGHTS]\n"
    exit 2
fi
case "${RIGHTS}" in
    1|3|7) ;;
    *) printf "RIGHTS is 1, 3 or 7: %s\n" "${RIGHTS}"; exit 2 ;;
esac
st_ensure_session

ENCODED=$(printf '%s' "${FOLDER}" | jq -Rr 'split("/") | map(@uri) | join("/")')
BODY=$(jq -n --arg emails "${EMAILS}" --argjson rights "${RIGHTS}" \
  '[{op: "add", path: "/sharedDirectoryProperties",
     value: {isOwner: true, collaborators: ($emails | split(",") | map(gsub("^ +| +$"; ""))),
             shareRights: $rights, enableNotifications: false,
             enableOwnerNotifications: false, showCollaboratorsToAll: false}}]')

printf "Sharing %s with %s, rights %s...\n" "${FOLDER}" "${EMAILS}" "${RIGHTS}"
RESPONSE=$(curl -s -k -b "${COOKIE}" -X PATCH "${ST_URL}/files/${ENCODED}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf "The share failed (HTTP %s):\n%s\n" "${HTTP_CODE}" "${RESPONSE%$'\n'*}"
    exit 1
fi
printf "Shared.\n"
