#!/bin/bash
# ==============================================================================
# Script Name: 03.folder_PATCH_share.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# Shares the folder with another user, who can then read it. PATCH /files/<folder> with a JSON patch that adds /sharedDirectoryProperties: the collaborators (e-mail addresses), the rights, and whether anyone is notified. 204 means done.
#
# Usage:
# ./03.folder_PATCH_share.sh
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/02.Files/14.files_filepath_PATCH_share.sh.
# - ST_SHARE_WITH names the user: the e-mail address of one the server knows. An address it does not know is refused with 400 "Unable to share folder ... with user ...".
# - shareRights 1 is read only. 05 changes it to 3 and 7 (see its notes).
# - Notifications are off (enableNotifications and enableOwnerNotifications false), so nobody is sent an e-mail by this example.
# - The folder must be one of your own: sharing someone else's is refused.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_need_collaborator
st_session

BODY=$(jq -n --arg who "${SHARE_WITH}" \
  '[{op: "add", path: "/sharedDirectoryProperties",
     value: {isOwner: true, collaborators: [$who], shareRights: 1, enableNotifications: false,
             enableOwnerNotifications: false, showCollaboratorsToAll: false}}]')
result=$(curl -k -s -w "\n%{http_code}" -b "${JAR}" -X PATCH "${ST_URL}/files/$(st_enc "${FOLDER}")" -H "accept: application/json" -H "Referer: ${REFERER}" -H "Content-Type: application/json" -d "${BODY}")
code="${result##*$'\n'}"
echo "Share ${FOLDER} with ${SHARE_WITH}, read only: HTTP ${code}"
if [[ "${code}" != 204 ]]; then
    echo "${result%$'\n'*}"
    [[ "${code}" == 400 ]] && echo "A 400 here is an account with no e-mail address (see 01), or an address the server does not know."
    exit 1
fi
