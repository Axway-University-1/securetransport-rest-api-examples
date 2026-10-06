#!/bin/bash
# ==============================================================================
# Script Name: files_GET_download.sh
# Author: Plamen Milenkov
# Created: 2026-10-02
# Location: Sofia
# ==============================================================================
# Description:
# Downloads one file from the test account's home folder, as a client would,
# COUNT times in a row, using the End User API `GET /files/{path}` endpoint. It
# logs in once as the account, downloads, and logs out.
#
# Each download is a transfer of its own. Run billable_GET_report.sh before and
# after to see how much repeated client downloads add to the usage reporting.
#
# Not numbered, so 00.run_all.sh does not run it: it is a separate experiment,
# run by hand against a file that is already in the account's home folder.
#
# Usage:
# ./files_GET_download.sh FILE [COUNT [ACCOUNT]]
#
#   FILE     the file to download, relative to the account's home folder, for
#            example subscription/s1/only_inbound.txt, where scenario 2.1 lands in
#            the test account, or btTestAccount/delivered-1/inbound_and_one_outbound.txt
#            as partner_to_push_to
#   COUNT    how many times to download it (default 1)
#   ACCOUNT  the account to log in as: the test account (default btTestAccount)
#            or a partner. Its password is BT_ACCOUNT_PASSWORD, the one
#            00.run_all.sh creates all three accounts with.
#
# For example:
# ./files_GET_download.sh subscription/s1/only_inbound.txt 50
# ./files_GET_download.sh btTestAccount/delivered-1/inbound_and_one_outbound.txt 50 partner_to_push_to
#
# Notes:
# - Needs settings.local.sh with BT_ACCOUNT_PASSWORD. See settings.sh.
# - Requires `jq`, which URL-encodes the path.
# - The downloaded content is discarded; only the HTTP code of each download is
#   kept. Exits 1 if any download did not answer 200.
# - The port is BT_ENDUSER_PORT, 8443 by default. It is not the Admin port.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

usage() {
    printf "Usage: ./files_GET_download.sh FILE [COUNT [ACCOUNT]]\n"
    exit 2
}

FILE_ARG="$1"
COUNT="${2:-1}"
[ -z "${FILE_ARG}" ] && usage
[ "$#" -gt 3 ] && usage
[[ "${COUNT}" =~ ^[1-9][0-9]*$ ]] \
    || { printf "COUNT must be a whole number, 1 or more: %s\n" "${COUNT}"; exit 2; }
if [ -n "$3" ]; then
    [[ "$3" =~ ^[A-Za-z0-9._-]+$ ]] \
        || { printf "ACCOUNT may use only letters, digits, '.', '_' and '-': %s\n" "$3"; exit 2; }
    export BT_RUN_ACCOUNT="$3"
fi

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
source "${SCRIPT_DIR}/settings.sh"

if [ -z "${BT_ACCOUNT_PASSWORD}" ]; then
    printf "BT_ACCOUNT_PASSWORD is not set. Copy settings.local.example.sh to settings.local.sh and choose one.\n"
    exit 1
fi

# Relative to the home folder, so a leading / is dropped. Each segment of the
# path is URL-encoded on its own, so a space or a # in a name survives, and the
# / between the segments stays a /
FILE_PATH="${FILE_ARG#/}"
ENCODED_PATH=$(printf '%s' "${FILE_PATH}" | jq -Rr 'split("/") | map(@uri) | join("/")')

ar_enduser_login || exit 1

printf "Downloading %s from %s's home folder, %s time(s)...\n" "${FILE_PATH}" "${BT_TEST_ACCOUNT}" "${COUNT}"
OK=0
FAILED_CODES=()
for i in $(seq 1 "${COUNT}"); do
    code=$(curl -L -s -k -b "${AR_EU_JAR}" -X GET "https://${ST_SERVER}:${EU_ENDUSER_PORT}/api/v2.0/files/${ENCODED_PATH}" \
      -H "accept: */*" -H "Referer: THIS_IS_A_RANDOM_TEXT" -H "csrfToken: ${AR_EU_CSRF}" \
      -o /dev/null -w "%{http_code}")
    if [ "${code}" = "200" ]; then
        OK=$((OK + 1))
    else
        FAILED_CODES+=("${i}:${code}")
    fi
    printf "  %s of %s: HTTP %s\n" "${i}" "${COUNT}" "${code}"
done

ar_enduser_logout

printf "%s of %s download(s) succeeded.\n" "${OK}" "${COUNT}"
if [ "${OK}" -ne "${COUNT}" ]; then
    printf "Failed (download:HTTP code): %s\n" "${FAILED_CODES[*]}"
    exit 1
fi
