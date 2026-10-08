#!/bin/bash
# ==============================================================================
# Script Name: 10.files_upload_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Creates and uploads every sample file these scenarios pull, using the End User
# API `/fileOperations` endpoint, logged in as partner_to_pull_from, into the
# test account's drop folder there (BT_DROP_FOLDER, <account>/outbound-drop).
# The two archives (for scenarios 2.5 and 2.6) are built locally with `zip`
# first, then uploaded as ordinary binary content.
#
# Usage:
# ./10.files_upload_POST.sh
#
# Risk: write
#
# Notes:
# - Run 01.accounts_POST.sh and 04.files_POST_folders.sh first.
# - Scenarios 2.1 and 2.2 upload BT_INBOUND_ONLY_COUNT and BT_IN_AND_OUT_COUNT
#   files, numbered when there is more than one. See settings.sh.
# - Needs settings.local.sh with BT_ACCOUNT_PASSWORD. See settings.sh.
# - Requires `jq`, `zip`, which builds the archives, and `mktemp`.
# - Stops at the first call the server refuses (no operation id, or a refused
#   content), logs out, and exits 1.
# - The content call uses PUT, not POST: POST is refused with a 415 (confirmed
#   on Features/trigger-route-after-completed-pull).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
source "${SCRIPT_DIR}/settings.sh"

if [ -z "${BT_ACCOUNT_PASSWORD}" ]; then
    printf "BT_ACCOUNT_PASSWORD is not set. Copy settings.local.example.sh to settings.local.sh and choose one.\n"
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

upload_bytes() {
    local file_path="$1" local_file="$2"
    local body operation_id

    body=$(jq -n --arg path "${file_path}" \
      '{operation: "Upload", filePath: $path, customAttributes: {transferMode: "BINARY"}}')

    printf "Declaring the upload of %s...\n" "${file_path}"
    ar_enduser_call POST fileOperations "application/json" "${body}"
    operation_id=$(printf '%s' "${AR_EU_BODY}" | jq -r '.id // empty' 2>/dev/null)

    if [ -z "${operation_id}" ]; then
        printf "No operation id came back (HTTP %s), so nothing was uploaded. The response was:\n%s\n" "${AR_EU_CODE}" "${AR_EU_BODY}"
        return 1
    fi

    printf "Sending the content to operation %s...\n" "${operation_id}"
    ar_enduser_call PUT "fileOperations/${operation_id}" "application/octet-stream" "@${local_file}"
    local put_rc=$?
    printf "%s\nHTTP %s\n" "${AR_EU_BODY}" "${AR_EU_CODE}"
    return "${put_rc}"
}

# An upload the server refuses stops the run: log out, and exit 1 (the trap removes
# the work folder)
stop_if_refused() {
    ar_enduser_logout
    exit 1
}

upload_text_file() {
    local name="$1" text="$2"
    local local_file="${WORK}/${name}"
    printf '%s\n' "${text}" > "${local_file}"
    upload_bytes "${BT_DROP_FOLDER}/${name}" "${local_file}"
}

# upload_scenario_files NAME COUNT TEXT
#   One file under NAME when COUNT is 1, otherwise COUNT numbered copies:
#   only_inbound.txt, or only_inbound_1.txt to only_inbound_<COUNT>.txt
upload_scenario_files() {
    local name="$1" count="$2" text="$3" i
    if [ "${count}" -eq 1 ]; then
        upload_text_file "${name}" "${text}" || stop_if_refused
        return
    fi
    for i in $(seq 1 "${count}"); do
        upload_text_file "${name%.txt}_${i}.txt" "${text} File ${i} of ${count}." || stop_if_refused
    done
}

bt_login_as "${BT_PULL_PARTNER}" || exit 1

upload_scenario_files "${BT_FILE_ONLY_INBOUND}" "${BT_INBOUND_ONLY_COUNT}" "Scenario 2.1: only inbound, no outbound at all."
upload_scenario_files "${BT_FILE_ONE_OUTBOUND}" "${BT_IN_AND_OUT_COUNT}" "Scenario 2.2: inbound, then pushed out once."
upload_text_file "${BT_FILE_TWO_OUTBOUNDS}" "Scenario 2.3: inbound, then pushed out twice." || stop_if_refused
upload_text_file "${BT_FILE_COMPRESS_1}" "Scenario 2.4, file 1 of 2, to be compressed together." || stop_if_refused
upload_text_file "${BT_FILE_COMPRESS_2}" "Scenario 2.4, file 2 of 2, to be compressed together." || stop_if_refused

# The two archives are built locally, then uploaded as ordinary binary content
build_archive() {
    local archive_name="$1" file_a_name="$2" file_a_text="$3" file_b_name="$4" file_b_text="$5"
    local archive_dir="${WORK}/${archive_name%.zip}"
    mkdir -p "${archive_dir}"
    printf '%s\n' "${file_a_text}" > "${archive_dir}/${file_a_name}"
    printf '%s\n' "${file_b_text}" > "${archive_dir}/${file_b_name}"
    ( cd "${archive_dir}" && zip -q "../${archive_name}" "${file_a_name}" "${file_b_name}" )
    upload_bytes "${BT_DROP_FOLDER}/${archive_name}" "${WORK}/${archive_name}" || stop_if_refused
}

build_archive "${BT_FILE_ARCHIVE_NAME}" \
  "${BT_FILE_DECOMPRESS_1}" "Scenario 2.5, file 1 of 2, inside the archive." \
  "${BT_FILE_DECOMPRESS_2}" "Scenario 2.5, file 2 of 2, inside the archive."

build_archive "${BT_FILE_ARCHIVE2P_NAME}" \
  "${BT_FILE_DECOMPRESS2P_1}" "Scenario 2.6, file 1 of 2, pushed on to two partners." \
  "${BT_FILE_DECOMPRESS2P_2}" "Scenario 2.6, file 2 of 2, pushed on to two partners."

ar_enduser_logout
