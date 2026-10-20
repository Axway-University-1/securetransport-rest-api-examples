#!/bin/bash
# ==============================================================================
# Script Name: 05.folder_PATCH_rights.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# Changes what the other user may do, without sharing again: a JSON patch that replaces /sharedDirectoryProperties/shareRights. 1 is read only, 3 adds upload, 7 adds delete. This sets 3, then 7, and reads back each one.
#
# Usage:
# ./05.folder_PATCH_rights.sh
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/02.Files/14.files_filepath_PATCH_share.sh, with replace instead of add.
# - Confirmed on the lab with a second user: with 1 an upload and a delete are 403; with 3 an upload is 201 and a delete of their file is 403; with 7 both work, and they can delete your files too.
# - Run 03 first: only a folder that is shared has rights to change.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

for rights in 3 7; do
    BODY=$(jq -n --argjson r "${rights}" '[{op: "replace", path: "/sharedDirectoryProperties/shareRights", value: $r}]')
    code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X PATCH "${ST_URL}/files/$(st_enc "${FOLDER}")" -H "accept: application/json" -H "Referer: ${REFERER}" -H "Content-Type: application/json" -d "${BODY}")
    echo "Set the rights to ${rights}: HTTP ${code}"
    [[ "${code}" == 204 ]] || exit 1
    now=$(curl -k -s -G -b "${JAR}" "${ST_URL}/files/$(st_enc "${FOLDER}")" --data-urlencode "metadata=true" -H "accept: application/json" -H "Referer: ${REFERER}" | jq -r '.self.sharedDirectoryProperties.shareRights')
    echo "  read back: ${now}"
    [ "${now}" = "${rights}" ] || { echo "The rights are not what was set."; exit 1; }
done
