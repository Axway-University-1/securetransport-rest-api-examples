#!/bin/bash
# ==============================================================================
# Script Name: 12.files_PUT_triggerfile.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Handles a current limitation: when the pull renames the files it receives (the
# _PULLED suffix), the trigger file written to the file system still lists their
# ORIGINAL names, so the route cannot find them. This finds the newest trigger
# file in the subscription folder and uploads it again with the current names,
# using the End User API `/fileOperations` endpoint:
#
#   pull_test_1.txt_PULLED
#   pull_test_2.txt_PULLED
#   pull_test_3.txt_PULLED
#
# The server refuses to write over the existing trigger file (HTTP 403), because
# the system created it, not the account. So the old file is deleted first and the
# new one is uploaded under the same name. Uploading into the subscription folder
# is a new arrival, so the subscription triggers again, this time on a correct
# list.
#
# Usage:
# ./12.files_PUT_triggerfile.sh
#
# Risk: write
#
# Notes:
# - Run it after 11.transfers_pull_POST.sh. It waits up to AR_WAIT_SECONDS for the
#   trigger file to appear, because the pull is asynchronous. The first route
#   execution, on the wrong names, is expected to fail. This step handles that
#   current limitation, and is no longer needed once the limitation is lifted.
# - The names come from the settings: AR_SAMPLE_PREFIX, AR_SAMPLE_FILES and
#   AR_PULLED_SUFFIX.
# - Needs settings.local.sh with AR_ACCOUNT_PASSWORD. See settings.sh.
# - Requires `jq`, which reads the listing and builds the JSON body.
# - If the old trigger file cannot be deleted either, the new one is uploaded as
#   <name>_fixed.trigger. It still ends in .trigger, so the trigger condition
#   matches it.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
source "${SCRIPT_DIR}/settings.sh"

if [ -z "${AR_ACCOUNT_PASSWORD}" ]; then
    printf "AR_ACCOUNT_PASSWORD is not set. Copy settings.local.example.sh to settings.local.sh and choose one.\n"
    exit 1
fi

# The names the files have now
CONTENT=""
for i in $(seq 1 "${AR_SAMPLE_FILES}"); do
    CONTENT="${CONTENT}${AR_SAMPLE_PREFIX}${i}.txt${AR_PULLED_SUFFIX}"$'\n'
done

ar_enduser_login || exit 1

# The newest trigger file in the subscription folder. The pull is asynchronous, so
# give the trigger file time to appear.
waited=0
while true; do
    ar_enduser_call GET "files${AR_SUBSCRIPTION_FOLDER}" ""
    TRIGGER=$(printf '%s' "${AR_EU_BODY}" | jq -r \
      '[(.files // [])[] | select(.isRegularFile and (.fileName | endswith(".trigger")))]
       | sort_by(.lastModifiedTime) | last | .fileName // empty' 2>/dev/null)
    [ -n "${TRIGGER}" ] && break
    [ "${waited}" -ge "${AR_WAIT_SECONDS}" ] && break
    printf "No trigger file in %s yet. Waiting...\n" "${AR_SUBSCRIPTION_FOLDER}"
    sleep 3
    waited=$((waited + 3))
done

if [ -z "${TRIGGER}" ]; then
    printf "No trigger file in %s. Has the pull in step 11 finished?\n" "${AR_SUBSCRIPTION_FOLDER}"
    ar_enduser_logout
    exit 1
fi

# The system owns the trigger file, so it cannot be written over. Delete it first.
printf "Deleting the old trigger file %s/%s...\n" "${AR_SUBSCRIPTION_FOLDER}" "${TRIGGER}"
TARGET="${TRIGGER}"
if ar_enduser_call DELETE "files${AR_SUBSCRIPTION_FOLDER}/${TRIGGER}" ""; then
    printf "HTTP %s\n" "${AR_EU_CODE}"
else
    TARGET="${TRIGGER%.trigger}_fixed.trigger"
    printf "It could not be deleted (HTTP %s), so the new one is uploaded as %s instead.\n" "${AR_EU_CODE}" "${TARGET}"
fi

printf "Uploading %s/%s with:\n%s" "${AR_SUBSCRIPTION_FOLDER}" "${TARGET}" "${CONTENT}"

# 1. Declare the upload, and read the operation id from the response
BODY=$(jq -n --arg path "${AR_SUBSCRIPTION_FOLDER}/${TARGET}" \
  '{operation: "Upload", filePath: $path, customAttributes: {transferMode: "ASCII"}}')
ar_enduser_call POST fileOperations "application/json" "${BODY}"
OPERATION_ID=$(printf '%s' "${AR_EU_BODY}" | jq -r '.id // empty' 2>/dev/null)

if [ -z "${OPERATION_ID}" ]; then
    printf "No operation id came back (HTTP %s), so nothing was changed. The response was:\n%s\n" "${AR_EU_CODE}" "${AR_EU_BODY}"
    ar_enduser_logout
    exit 1
fi

# 2. Send the new content to that operation
ar_enduser_call PUT "fileOperations/${OPERATION_ID}" "application/octet-stream" "${CONTENT}"
printf "%s\nHTTP %s\n" "${AR_EU_BODY}" "${AR_EU_CODE}"

ar_enduser_logout
