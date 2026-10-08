#!/bin/bash
# ==============================================================================
# Script Name: 07.transferProfiles_id_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes a transfer profile, using the `/transferProfiles/{id}` endpoint.
# A profile is deleted by its id, not its name, so it looks the id up by account and name first.
#
# Usage:
# ./07.transferProfiles_id_DELETE.sh ACCOUNT NAME
#
#   ACCOUNT  the account the profile belongs to
#   NAME     the profile (it must be the only one with that name)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This deletes data. Check the names before running it; 02.transferProfiles_POST.sh creates `example_profile`.
# - Confirmed directly: a success is 204; a second delete, or an unknown id, is a JSON 404 "Transfer profile with id X
#   not found or not accessible.". Deleting an account deletes its
#   profiles.
# - Requires `jq`, which reads the id.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/transferProfiles"
ACCOUNT="$1"
NAME="$2"
[ -n "${ACCOUNT}" ] && [ -n "${NAME}" ] || { printf "Usage: ./07.transferProfiles_id_DELETE.sh ACCOUNT NAME\n"; exit 2; }

# The one profile of that account with that name: "1 <id>", or how many there are.
# The name filter ignores case and takes a * wildcard, so the exact name is
# picked out of what comes back.
read -r FOUND PROFILE_ID < <(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" \
  --data-urlencode "account=${ACCOUNT}" --data-urlencode "name=${NAME}" --data-urlencode "fields=id,name" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r --arg name "${NAME}" '[(.result // [])[] | select(.name == $name)] | if length == 1 then "1 \(.[0].id)" else "\(length)" end')
if [ "${FOUND}" != "1" ]; then
    printf "Found %s transfer profiles named %s on the account %s; this script acts on exactly one.\n" "${FOUND:-0}" "${NAME}" "${ACCOUNT}"
    exit 1
fi

printf "Deleting the transfer profile %s of %s (%s)...\n" "${NAME}" "${ACCOUNT}" "${PROFILE_ID}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${PROFILE_ID}" -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
