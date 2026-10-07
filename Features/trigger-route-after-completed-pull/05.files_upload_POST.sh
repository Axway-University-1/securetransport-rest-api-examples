#!/bin/bash
# ==============================================================================
# Script Name: 05.files_upload_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Puts the sample files in the pull folder, using the End User API `/fileOperations`
# endpoint. It logs in to the End User API as the test account itself, on the End
# User port, and logs out again at the end.
#
# Each file is two calls: the first declares the upload and returns an operation
# id, the second sends the content to that id.
#
# Usage:
# ./05.files_upload_POST.sh
#
# Risk: write
#
# Notes:
# - Run 04.files_POST_folders first, so the folder exists.
# - Needs settings.local.sh with AR_ACCOUNT_PASSWORD. See settings.sh.
# - Requires `jq`, which builds the JSON body and reads the id.
# - The port is AR_ENDUSER_PORT, 8443 by default. It is not the Admin port.
# - The content is sent with PUT, not POST: POST is refused with a 415 for every
#   content type except multipart, and multipart names the file after the local
#   one instead of the path declared in the first call.
# - The operation is asynchronous: the status in the first response is the
#   operation's, not the upload's.
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

ar_enduser_login || exit 1

for i in $(seq 1 "${AR_SAMPLE_FILES}"); do
    FILE_PATH="${AR_UPLOAD_FOLDER}/${AR_SAMPLE_PREFIX}${i}.txt"

    # 1. Declare the upload, and read the operation id from the response
    BODY=$(jq -n --arg path "${FILE_PATH}" \
      '{operation: "Upload", filePath: $path, customAttributes: {transferMode: "ASCII"}}')

    printf "Declaring the upload of %s...\n" "${FILE_PATH}"
    ar_enduser_call POST fileOperations "application/json" "${BODY}"
    OPERATION_ID=$(printf '%s' "${AR_EU_BODY}" | jq -r '.id // empty' 2>/dev/null)

    if [ -z "${OPERATION_ID}" ]; then
        printf "No operation id came back (HTTP %s), so nothing was uploaded. The response was:\n%s\n" "${AR_EU_CODE}" "${AR_EU_BODY}"
        ar_enduser_logout
        exit 1
    fi

    # 2. Send the content to that operation
    printf "Sending the content to operation %s...\n" "${OPERATION_ID}"
    ar_enduser_call PUT "fileOperations/${OPERATION_ID}" "application/octet-stream" "Sample file ${i} for the pull test."
    printf "%s\nHTTP %s\n" "${AR_EU_BODY}" "${AR_EU_CODE}"
done

ar_enduser_logout
