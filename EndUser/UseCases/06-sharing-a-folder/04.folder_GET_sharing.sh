#!/bin/bash
# ==============================================================================
# Script Name: 04.folder_GET_sharing.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# Looks at how the folder is shared: GET /files/<folder>?metadata=true says whether it is shared, who owns it, with whom, and with which rights.
#
# Usage:
# ./04.folder_GET_sharing.sh
#
# Risk: read
#
# Notes:
# - Copied from EndUser/API 2.0/bash/02.Files/10.files_filepath_GET_metadata.sh.
# - The rights: 1 is read, 3 is read and upload, 7 is read, upload and delete (confirmed on the lab).
# - What the other user sees: the folder in the root of their own home folder, named <folder> (<your e-mail address>), for example example_uc_shared (you@example.com). It is in their file list like any folder.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

result=$(curl -k -s -G -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/files/$(st_enc "${FOLDER}")" --data-urlencode "metadata=true" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "HTTP ${code}"
[[ "${code}" == 200 ]] || { echo "${result%???}"; exit 1; }
echo "${result%???}" | jq -r '.self | "  shared:        \(.isShared)",
  (if .isShared then "  owner:         \(.sharedDirectoryProperties.ownerName) <\(.sharedDirectoryProperties.ownerEmail)>",
   "  shared with:   \(.sharedDirectoryProperties.collaborators | join(", "))",
   "  rights:        \(.sharedDirectoryProperties.shareRights) (\({"1":"read","3":"read and upload","7":"read, upload and delete"}[(.sharedDirectoryProperties.shareRights | tostring)] // "other"))" else empty end)' 
