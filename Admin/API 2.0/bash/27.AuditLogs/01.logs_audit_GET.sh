#!/bin/bash
# ==============================================================================
# Script Name: 01.logs_audit_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script reads the audit log using the `/logs/audit` endpoint: who created, changed or
# deleted what on the server, when, and from which address. It demonstrates:
# - Counting the entries, and the ones of the last hours (duration=)
# - The entries for one type of object, and one object by its exact name
# - Only the entries of one kind of operation
#
# Usage:
# ./01.logs_audit_GET.sh [HOURS [OBJECT_TYPE [OBJECT_NAME [OPERATION]]]]
#
#   HOURS        how far back to look, in whole hours (default 24)
#   OBJECT_TYPE  for example BusinessUnit or Account (optional)
#   OBJECT_NAME  one object's exact name (optional)
#   OPERATION    CREATE, UPDATE, DELETE or CREATE_OR_UPDATE (optional)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The audit log is the server's record of changes made through the Admin UI and this API.
#   Confirmed directly: it is newest first, the opposite of the server log.
# - Confirmed directly: objectType= and objectName= are matched exactly, with case: BusinessUnit
#   finds the units, businessunit and Business find none, and there is no * wildcard.
#   userName= is a case sensitive part of the name.
# - Confirmed directly: fromDate and endDate are RFC 2822 dates, for example Wed, 07 Oct 2026
#   00:00:00 +0300; 2026-10-07 answers 400. duration= takes hours and needs no date.
# - An operation that does not exist answers 400 "Unknown name value ... for enum class".
# - Requires `jq`, which prints one entry per line.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/logs/audit"
HOURS="${1:-24}"
OBJECT_TYPE="$2"
OBJECT_NAME="$3"
OPERATION="$4"
[[ "${HOURS}" =~ ^[1-9][0-9]*$ ]] || { printf "HOURS must be a whole number of 1 or more: %s\n" "${HOURS}"; exit 2; }
if [ -n "${OPERATION}" ] && ! [[ "${OPERATION}" =~ ^(CREATE|UPDATE|DELETE|CREATE_OR_UPDATE)$ ]]; then
    printf "OPERATION is CREATE, UPDATE, DELETE or CREATE_OR_UPDATE, not %s.\n" "${OPERATION}"
    exit 2
fi
LINE='"  \(.dateModified)  \(.operationType)  \(.objectType) \(.objectName // "-")  by \(.userName // "-") from \(.remoteAddress // "-")"'
FIELDS="id,dateModified,operationType,objectType,objectName,userName,remoteAddress"

printf "Audit log entries: "
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?limit=1&fields=id" -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.resultSet.totalCount'

printf "\nThe last %s hour(s): " "${HOURS}"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "duration=${HOURS}" --data-urlencode "limit=1" --data-urlencode "fields=id" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '"\(.resultSet.totalCount) entries"'
printf "The latest 5, newest first:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "duration=${HOURS}" --data-urlencode "limit=5" --data-urlencode "fields=${FIELDS}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r "(.result // [])[] | ${LINE}"

FILTER=()
[ -n "${OBJECT_TYPE}" ] && FILTER+=(--data-urlencode "objectType=${OBJECT_TYPE}")
[ -n "${OBJECT_NAME}" ] && FILTER+=(--data-urlencode "objectName=${OBJECT_NAME}")
[ -n "${OPERATION}" ] && FILTER+=(--data-urlencode "operationType=${OPERATION}")
if [ "${#FILTER[@]}" -gt 0 ]; then
    printf "\nThe latest 10 entries for those filters:\n"
    curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" "${FILTER[@]}" --data-urlencode "limit=10" --data-urlencode "fields=${FIELDS}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r "(.result // [])[] | ${LINE}"
fi
