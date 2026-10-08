#!/bin/bash
# ==============================================================================
# Script Name: 01.transferProfiles_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script retrieves transfer profiles using the `/transferProfiles` endpoint.
# It demonstrates:
# - The number of profiles on the server
# - The profiles of one account (or of every account), one line each
# - Only the default ones: an account has at most one default profile
#
# Usage:
# ./01.transferProfiles_GET.sh [ACCOUNT [NAME]]
#
#   ACCOUNT  list only the profiles of this account (default: every account)
#   NAME     only the profiles with this name; takes a * wildcard (default *)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Transfer profiles are a PeSIT thing. Confirmed directly: a profile for an account that has no PeSIT transfer site
#   is refused, 400 "Account does not contain any PeSIT transfer sites."; an account that does not exist is 404.
# - Confirmed directly: the answer is `{resultSet, result}`; `limit=0` lists all, a negative `limit` is 400. `account=` is
#   exact (case sensitive, no wildcard, an account that does not exist just finds nothing). `name=` ignores case and takes a
#   `*`, so `P*` finds `p1` and `P1`. A name is unique per account but case sensitive: `p1` and `P1` can both exist.
#   `default=` takes true or false, and any other text means false (`default=abc` lists the profiles that are not the default).
#   `transferMode`, `recordFormat`, `recordLength`, `multiSelect`, `fileLabelOption`, `sendMapping` and `additionalAttributes.key`
#   (or `.value`) filter too; a value that is no transfer mode finds nothing, not a 400. `fields=` keeps the keys named,
#   an unknown one is 400 "Field nope does not exist.".
# - A profile has an `id`, and the other examples in this folder look it up by account and name.
# - Requires `jq`, which prints one line per profile.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/transferProfiles"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/transferProfiles"
ACCOUNT="$1"
PATTERN="${2:-*}"

FILTER=()
[ -n "${ACCOUNT}" ] && FILTER=(--data-urlencode "account=${ACCOUNT}")

LINE='"  \(.id)  \(.account)/\(.name)  \(if .default then "default" else "-" end)  send \(.sendMapping)  receive \(.receiveMapping)  \(.fileLabelOption)  \(.transferMode)"'

printf "Transfer profiles on the server: "
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?limit=1&fields=id" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '.resultSet.totalCount'

printf "\nThe profiles matching %s: id, account/name, default, mappings, file label, mode:\n" "${PATTERN}"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" "${FILTER[@]}" --data-urlencode "name=${PATTERN}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r "(.result // [])[] | ${LINE}"

printf "\nOnly the default ones:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" "${FILTER[@]}" --data-urlencode "name=${PATTERN}" \
  --data-urlencode "default=true" -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r "(.result // [])[] | ${LINE}"
