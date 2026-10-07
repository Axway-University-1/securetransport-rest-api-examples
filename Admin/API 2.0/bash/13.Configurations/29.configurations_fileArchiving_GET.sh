#!/bin/bash
# ==============================================================================
# Script Name: 29.configurations_fileArchiving_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads the file archiving settings, using the
# `/configurations/fileArchiving` endpoint: whether the files transferred are
# kept in an archive, where, encrypted with which certificate, and for how long.
#
# Usage:
# ./29.configurations_fileArchiving_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The archive can be a folder or an S3 bucket (isS3Storage and the s3*
#   settings).
# - Requires `jq`, which prints the summary.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/fileArchiving" -H "accept: application/json" \
  -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s:\n%s\n" "${HTTP_CODE}" "${RESPONSE}"
    exit 1
fi
printf '%s\n' "${RESPONSE}"
printf "\nIn short:\n"
printf '%s' "${RESPONSE}" | jq -r '"  archiving: \(.globalArchivingPolicy), to \(if .isS3Storage then "S3 bucket \(.s3BucketName)" else .archiveFolder end)", "  files deleted after \(.deleteFilesOlderThan) \(.deleteFilesOlderThanUnit), files up to \(.maximumFileSizeAllowedToArchive) MB archived"'
