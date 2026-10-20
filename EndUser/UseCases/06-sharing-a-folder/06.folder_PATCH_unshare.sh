#!/bin/bash
# ==============================================================================
# Script Name: 06.folder_PATCH_unshare.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# Stops sharing: a JSON patch that removes /sharedDirectoryProperties. The folder and its files stay, with you; the other user no longer sees them. Then it checks that the folder is no longer shared.
#
# Usage:
# ./06.folder_PATCH_unshare.sh
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/02.Files/15.files_filepath_PATCH_unshare.sh.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X PATCH "${ST_URL}/files/$(st_enc "${FOLDER}")" -H "accept: application/json" -H "Referer: ${REFERER}" -H "Content-Type: application/json" \
       -d '[{"op":"remove","path":"/sharedDirectoryProperties"}]')
echo "Stop sharing ${FOLDER}: HTTP ${code}"
[[ "${code}" == 204 ]] || exit 1
shared=$(curl -k -s -G -b "${JAR}" "${ST_URL}/files/$(st_enc "${FOLDER}")" --data-urlencode "metadata=true" -H "accept: application/json" -H "Referer: ${REFERER}" | jq -r '.self.isShared')
echo "Shared now: ${shared}"
[ "${shared}" = "false" ] || exit 1
