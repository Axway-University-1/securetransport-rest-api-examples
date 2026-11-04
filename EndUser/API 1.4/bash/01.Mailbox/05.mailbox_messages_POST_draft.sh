#!/bin/bash
# ==============================================================================
# Script Name: 05.mailbox_messages_POST_draft.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# This script makes a message draft with `POST /api/v1.4/mailbox/messages`, and prints the id of the draft. A draft is kept in the Drafts folder until 07 sends it. The call takes form data.
#
# Usage:
# ./05.mailbox_messages_POST_draft.sh TO SUBJECT [MESSAGE] [SECURITY]
#
#   TO        the email address of the recipient (the `email` of his mailbox user, see 01); several are comma separated
#   SUBJECT   the subject
#   MESSAGE   the text (default: empty)
#   SECURITY  EXISTING_ACCOUNT, ENROLL_LICENSED, ENROLL_UNLICENSED, CHALLENGED_LINK or ANONYMOUS_LINK (default: EXISTING_ACCOUNT)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh). It holds the END USER of the mailbox: ST_USER and ST_PASSWORD are his, and ST_PORT is the End User port (8443, or 443 on a root install).
# - The API 1.4 mailbox is not in the API 2.0. Every call here uses Basic authentication and a Referer header. To act as another user (the recipient of a message), point ST_ENDUSER_LOCAL_VARIABLES at his settings file.
# - The mailbox answers its errors as {"error": ..., "errorDescription": ...}. The script prints both.
# - Confirmed directly on 5.5-20260924: the call SAVES the draft and still answers 500 "Draft was not saved" (errorDescription "Internal error"), with no id. The server log says "Draft created successfully" and also "Can not get package item input stream": the text of the message is not stored. The script reads the Drafts folder before and after, and takes the draft that is new. It tells you when it did.
# - Confirmed directly: a draft with no `security` is saved with the level null, and 07 then refuses it: "Message security level may not be empty." So the script always sends one.
# - Confirmed directly: a message to yourself is sent (200) and stays in your Sent folder; it does not arrive in your own Inbox. Use another user to see a message arrive.
# - Seen once: a draft that had been changed with `PUT /mailbox/messages/{messageId}` (which answers 500 "Draft was not saved") and given an attachment was refused at the send, 400 "Message recipient may not be empty." Changing a draft is not reliable on the lab: make a new one.
# - Not confirmed: the text of the message (MESSAGE). On the lab it is saved as an empty text (size 0).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${ST_ENDUSER_LOCAL_VARIABLES:-${SCRIPT_DIR}/../set_variables.local.sh}" ||
    { echo "Copy set_variables.local.example.sh to set_variables.local.sh and fill it in."; exit 1; }

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v1.4/mailbox"

# The reason of a refusal: the mailbox answers {"error", "errorDescription"}, other answers {"message"}
reason() { printf '%s' "$1" | jq -r '[.error, .errorDescription, .message] | map(select(. != null and . != "")) | join(" - ")' 2>/dev/null; }

USAGE="Usage: ./05.mailbox_messages_POST_draft.sh TO SUBJECT [MESSAGE] [SECURITY]"
if [ "$#" -lt 2 ] || [ "$#" -gt 4 ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
RECIPIENT="$1"
SUBJECT="$2"
TEXT="${3:-}"
SECURITY="${4:-EXISTING_ACCOUNT}"
if [ -z "${RECIPIENT}" ] || [ -z "${SUBJECT}" ] || [[ ! "${SECURITY}" =~ ^(EXISTING_ACCOUNT|ENROLL_LICENSED|ENROLL_UNLICENSED|CHALLENGED_LINK|ANONYMOUS_LINK)$ ]]; then
    printf "TO and SUBJECT are needed, and SECURITY is one of EXISTING_ACCOUNT, ENROLL_LICENSED, ENROLL_UNLICENSED, CHALLENGED_LINK, ANONYMOUS_LINK (it is '%s').\n%s\n" "${SECURITY}" "${USAGE}"
    exit 2
fi

# The ids in the Drafts folder, one on a line
draft_ids() {
    curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G "${MAIN_URL}/folders/Drafts" --data-urlencode "limit=100" --data-urlencode "offset=0" \
      -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '(.data // [])[].id' 2>/dev/null | sort
}

BEFORE=$(draft_ids)
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}/messages" --data-urlencode "to=${RECIPIENT}" --data-urlencode "subject=${SUBJECT}" --data-urlencode "message=${TEXT}" --data-urlencode "security=${SECURITY}" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" = "200" ] || [ "${HTTP_CODE}" = "201" ]; then
    printf "The draft was made (HTTP %s). Its id: %s\n" "${HTTP_CODE}" "$(printf '%s' "${BODY}" | jq -r '.messageId // .id // empty' 2>/dev/null)"
    exit 0
fi
if [ "${HTTP_CODE}" != "500" ]; then
    printf "Could not make the draft (HTTP %s): %s\n" "${HTTP_CODE}" "$(reason "${BODY}")"
    exit 1
fi
# 500 "Draft was not saved": the draft is saved all the same. Find it in the Drafts folder: the one that was not there before.
NEW=$(comm -13 <(printf '%s\n' "${BEFORE}") <(draft_ids))
if [ -z "${NEW}" ] || [ "$(printf '%s\n' "${NEW}" | wc -l | tr -d ' ')" != "1" ]; then
    printf "Could not make the draft (HTTP 500): %s\nThe Drafts folder holds no single new draft, so nothing can be said about its id.\n" "$(reason "${BODY}")"
    exit 1
fi
printf "The server answered 500 (%s), but the draft is in the Drafts folder.\nIts id: %s\n" "$(reason "${BODY}")" "${NEW}"
