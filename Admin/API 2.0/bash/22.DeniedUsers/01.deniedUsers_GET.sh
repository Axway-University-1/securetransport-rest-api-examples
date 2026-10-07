#!/bin/bash
# ==============================================================================
# Script Name: 01.deniedUsers_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the denied users using the `/deniedUsers` endpoint: the login
# names that may not log in to SecureTransport, permanently or for a time.
# It demonstrates:
# - Counting them
# - Searching by login name, with the * wildcard
# - Only the permanent ones, and only the temporary ones (isPermanent=)
# - Only the ones blocked since a date (blockedAt.from=)
#
# Usage:
# ./01.deniedUsers_GET.sh [PATTERN [SINCE]]
#
#   PATTERN  a login name, * matches anything (default *)
#   SINCE    only the ones blocked on or after this date, as yyyy-MM-dd (optional)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: the answer is {resultSet, result}; each entry has
#   loginName, blockedAt, blockedUntil, blockedBy and note.
# - Confirmed directly: blockedUntil null means blocked for good. A temporary
#   entry stays in the list after it expires, until the server's blocked users
#   cleaner removes it, so isPermanent=false can show entries that no longer
#   block anyone.
# - Confirmed directly: loginName= is matched without regard to case, but an
#   entry's name is case sensitive: example_denied and EXAMPLE_DENIED can both
#   be in the list.
# - Confirmed directly: blockedAt and blockedUntil take .from and .to, as
#   yyyy-MM-dd, an RFC 2822 date or a timestamp in milliseconds.
# - Requires `jq`, which prints one entry per line.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/deniedUsers"
PATTERN="${1:-*}"
SINCE="$2"
if [ -n "${SINCE}" ] && ! [[ "${SINCE}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    printf "SINCE is a date as yyyy-MM-dd: %s\n" "${SINCE}"
    exit 2
fi

LINE='"  \(.loginName)  \(if .blockedUntil == null then "permanent" else "until " + .blockedUntil end)  by \(.blockedBy // "-")  \(.note // "")"'

printf "Denied users: "
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?limit=1&fields=loginName" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '.resultSet.totalCount'

printf "\nThe login names matching %s: name, until, by, note:\n" "${PATTERN}"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "loginName=${PATTERN}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r "(.result // [])[] | ${LINE}"

printf "\nOnly the permanent ones:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "loginName=${PATTERN}" \
  --data-urlencode "isPermanent=true" -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r "(.result // [])[] | ${LINE}"

printf "\nOnly the temporary ones:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "loginName=${PATTERN}" \
  --data-urlencode "isPermanent=false" -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r "(.result // [])[] | ${LINE}"

if [ -n "${SINCE}" ]; then
    printf "\nBlocked on or after %s:\n" "${SINCE}"
    curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "loginName=${PATTERN}" \
      --data-urlencode "blockedAt.from=${SINCE}" -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r "(.result // [])[] | ${LINE}"
fi
