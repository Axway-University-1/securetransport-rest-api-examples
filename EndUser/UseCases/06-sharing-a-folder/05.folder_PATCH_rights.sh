#!/bin/bash
# ==============================================================================
# Script Name: 05.folder_PATCH_rights.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# Changes the type of share, what the other user may do, without sharing again: a JSON patch that replaces /sharedDirectoryProperties/shareRights. read (1) is read only, write (3) adds upload, full (7) adds delete. The new rights are read back.
#
# Usage:
# ./05.folder_PATCH_rights.sh RIGHTS
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/02.Files/14.files_filepath_PATCH_share.sh, with replace instead of add.
# - RIGHTS is read or 1, write or 3, full or 7. Run it again with another value to change the share again; it takes effect at once.
# - Confirmed on the lab with a second user: with read an upload and a delete are 403; with write an upload is 201 and deleting their own file is still 403; with full both work, and they can delete your files too.
# - Run 03 first: only a folder that is shared has rights to change.
# - Exit 2 without RIGHTS, or with one that is not in the list (nothing is sent).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"

RIGHTS=$(st_rights "$1")
if [ -z "${RIGHTS}" ]; then
    printf "Usage: ./05.folder_PATCH_rights.sh RIGHTS\n"
    st_rights_usage
    exit 2
fi
st_session

BODY=$(jq -n --argjson r "${RIGHTS}" '[{op: "replace", path: "/sharedDirectoryProperties/shareRights", value: $r}]')
code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X PATCH "${ST_URL}/files/$(st_enc "${FOLDER}")" -H "accept: application/json" -H "Referer: ${REFERER}" -H "Content-Type: application/json" -d "${BODY}")
echo "Set the rights of ${FOLDER} to ${RIGHTS}: HTTP ${code}"
[[ "${code}" == 204 ]] || { echo "Is the folder shared? Run 03.folder_PATCH_share.sh first."; exit 1; }
now=$(curl -k -s -G -b "${JAR}" "${ST_URL}/files/$(st_enc "${FOLDER}")" --data-urlencode "metadata=true" -H "accept: application/json" -H "Referer: ${REFERER}" | jq -r '.self.sharedDirectoryProperties.shareRights')
echo "Read back: ${now}"
[ "${now}" = "${RIGHTS}" ] || { echo "The rights are not what was set."; exit 1; }
