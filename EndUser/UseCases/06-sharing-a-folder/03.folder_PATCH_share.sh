#!/bin/bash
# ==============================================================================
# Script Name: 03.folder_PATCH_share.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# Shares the folder with another user, who can then work in it as far as the rights say. PATCH /files/<folder> with a JSON patch that adds /sharedDirectoryProperties: the collaborators (e-mail addresses), the rights, and whether anyone is notified. 204 means done.
#
# Usage:
# ./03.folder_PATCH_share.sh EMAIL [RIGHTS]
#
# Risk: write
#
# Notes:
# - Copied from EndUser/API 2.0/bash/02.Files/14.files_filepath_PATCH_share.sh.
# - EMAIL is the e-mail address of a user the server knows: an address it does not know is refused with 400 "Unable to share folder ... with user ...". 02-knowing-yourself/05.myself_addressBook_GET.sh lists the users and their addresses.
# - RIGHTS is the type of share: read or 1 (the default: the other user can only read), write or 3 (read and upload), full or 7 (read, upload and delete, your files too). 05 changes it afterwards.
# - Notifications are off (enableNotifications and enableOwnerNotifications false), so nobody is sent an e-mail by this example.
# - The folder must be one of your own: sharing someone else's is refused.
# - A 400 "Shared folders functionality is disabled" is an account with no e-mail address (see 01), and the session does not notice a new address until it is ended and begun again.
# - Exit 2 without EMAIL, or with RIGHTS that is not one of the above (nothing is sent).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"

EMAIL="$1"
RIGHTS=$(st_rights "${2:-read}")
if [ -z "${EMAIL}" ] || [ -z "${RIGHTS}" ]; then
    printf "Usage: ./03.folder_PATCH_share.sh EMAIL [RIGHTS]\n"
    printf "  EMAIL   the e-mail address of a user the server knows: the folder is shared with them\n"
    st_rights_usage
    printf "          (default read)\n"
    exit 2
fi
st_session

BODY=$(jq -n --arg who "${EMAIL}" --argjson rights "${RIGHTS}" \
  '[{op: "add", path: "/sharedDirectoryProperties",
     value: {isOwner: true, collaborators: [$who], shareRights: $rights, enableNotifications: false,
             enableOwnerNotifications: false, showCollaboratorsToAll: false}}]')
result=$(curl -k -s -w "\n%{http_code}" -b "${JAR}" -X PATCH "${ST_URL}/files/$(st_enc "${FOLDER}")" -H "accept: application/json" -H "Referer: ${REFERER}" -H "Content-Type: application/json" -d "${BODY}")
code="${result##*$'\n'}"
echo "Share ${FOLDER} with ${EMAIL}, rights ${RIGHTS}: HTTP ${code}"
if [[ "${code}" != 204 ]]; then
    echo "${result%$'\n'*}"
    if [[ "${code}" == 400 ]]; then
        echo "A 400 here is an account with no e-mail address (see 01), or an address the server does not know."
        st_session_note
    fi
    exit 1
fi
