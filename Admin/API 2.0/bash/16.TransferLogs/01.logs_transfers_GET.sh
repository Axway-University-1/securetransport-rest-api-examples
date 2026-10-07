#!/bin/bash
# ==============================================================================
# Script Name: 01.logs_transfers_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-05
# Location: Sofia
# ==============================================================================
# Description:
# This script reads the transfer log, what File Tracking shows, using the
# `/logs/transfers` endpoint. It demonstrates:
# - Filtering the log by account
# - Counting the matches with resultSet.totalCount, while limit keeps the
#   response itself small
# - Filtering by status as well
#
# Usage:
# ./01.logs_transfers_GET.sh [ACCOUNT]
#
#   ACCOUNT  the account whose transfers to read (default john)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The account is filtered with account=. The endpoint ignores accountName=
#   without a word and answers for every account (confirmed directly).
# - resultSet.returnCount is the number of entries in this response, so it is
#   never more than limit. resultSet.totalCount is the number of entries that
#   match, however many were returned.
# - curl -G sends the --data-urlencode values in the query string, encoded.
# - Requires `jq`, which reads the count.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

ACCOUNT="${1:-john}"

printf "The 10 latest transfers of '%s'...\n" "${ACCOUNT}"
RESPONSE=$(curl -s -k -G -u "${ST_USER}:${ST_PASSWORD}" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/logs/transfers" \
  --data-urlencode "account=${ACCOUNT}" --data-urlencode "sortByStartTime=descending" --data-urlencode "limit=10" \
  -H "accept: application/json" -H "${REFERER_HEADER}")
printf '%s\n' "${RESPONSE}" | jq '.result'
printf "%s transfer(s) of '%s' in the log, in all.\n" \
  "$(printf '%s' "${RESPONSE}" | jq -r '.resultSet.totalCount // "an unknown number of"')" "${ACCOUNT}"

printf "\nHow many of them failed...\n"
FAILED_COUNT=$(curl -s -k -G -u "${ST_USER}:${ST_PASSWORD}" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/logs/transfers" \
  --data-urlencode "account=${ACCOUNT}" --data-urlencode "status=Failed" \
  --data-urlencode "limit=1" --data-urlencode "fields=id" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.resultSet.totalCount // empty')
printf "%s failed transfer(s).\n" "${FAILED_COUNT:-An unknown number of}"
