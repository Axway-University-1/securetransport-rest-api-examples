#!/bin/bash
# ==============================================================================
# Script Name: 01.transfers_operations_POST_pull.sh
# Author: Plamen Milenkov
# Created: 2026-10-05
# Location: Sofia
# ==============================================================================
# Description:
# This script starts a pull from a partner, on demand, using the
# `/transfers/operations?operation=pull` endpoint. The files the site matches
# are downloaded into a folder of the account.
#
# Usage:
# ./01.transfers_operations_POST_pull.sh [ACCOUNT [SITE [DESTINATION_FOLDER]]]
#
#   ACCOUNT             the account that pulls (default john, or ST_EXAMPLE_ACCOUNT)
#   SITE                the transfer site of that account to pull with (default SSH_PULL)
#   DESTINATION_FOLDER  the folder of the account the files land in (default /inbox)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The account "john" and its site SSH_PULL must already exist. Run
#   06.TransferSites/02.sites_POST_ssh.sh first.
# - With awaitResult false, SecureTransport answers 202 as soon as the pull is
#   accepted, and the pull runs on in the background. Follow it in File
#   Tracking, or with 16.TransferLogs/01.logs_transfers_GET.sh.
# - When the destination folder is subscribed to an application, as
#   07.Subscriptions/02.subscriptions_POST.sh sets up for /inbox, what arrives
#   there is routed.
# - The HTTP code is printed. Anything but 202 is a refusal and the script exits 1 with the server's answer: the pull was not started.
# - Confirmed directly: an account that does not exist is 404 "Cannot find account with name X or it is not accessible", a site
#   the account does not have 400 "X site does not exist", a body with nothing in it 400 listing every field it lacks
#   (accountName, site, destinationDirectory).
# - Requires `jq`, which builds the request body.
# - Exit codes: 0 when the pull was accepted (202), 1 when the server refuses, 2 when an argument is empty or there are too many (nothing is sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
USAGE="Usage: ./01.transfers_operations_POST_pull.sh [ACCOUNT [SITE [DESTINATION_FOLDER]]]"

ACCOUNT="${1:-${ST_EXAMPLE_ACCOUNT:-john}}"
PULL_SITE="${2:-SSH_PULL}"
DESTINATION_FOLDER="${3:-/inbox}"
if [ "$#" -gt 3 ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi
for VALUE in "${ACCOUNT}" "${PULL_SITE}" "${DESTINATION_FOLDER}"; do
    if [ -z "${VALUE// /}" ]; then
        printf "ACCOUNT, SITE and DESTINATION_FOLDER must not be empty.\n%s\n" "${USAGE}"
        exit 2
    fi
done

BODY=$(jq -cn --arg account "${ACCOUNT}" --arg site "${PULL_SITE}" --arg folder "${DESTINATION_FOLDER}" \
  '{accountName: $account, site: $site, destinationDirectory: $folder, awaitResult: false}')

printf "Pulling with the site '%s' into '%s' of '%s'...\n" "${PULL_SITE}" "${DESTINATION_FOLDER}" "${ACCOUNT}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/transfers/operations?operation=pull" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "202" ]; then
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
printf '%s\n' "${RESPONSE}"
