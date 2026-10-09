#!/bin/bash
# ==============================================================================
# Script Name: 05.sites_id_HEAD.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script checks whether a transfer site exists, using the `/sites/{id}`
# endpoint with HEAD: 200 when it does, 404 when it does not. The path takes the
# site's id, so the script looks the id up by account and name first.
#
# Usage:
# ./05.sites_id_HEAD.sh [ACCOUNT [NAME]]
#
#   ACCOUNT  the account the site belongs to (default john, or ST_EXAMPLE_ACCOUNT)
#   NAME     the site (default SSH_PULL, which 02.sites_POST_ssh.sh creates)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The site is looked up by account and name, and must be the only one with that name.
# - Confirmed directly: HEAD answers 200 for a site of any type and 404, with no body, for an
#   id that does not exist. Two accounts may each have a site of the same name (201), but a
#   second one in the same account is 409 "Entry already exist.". The `name=` filter
#   ignores case and takes a * wildcard, so `example_x` and `EXAMPLE_X` (two different sites)
#   both come back for either, and `example_x*` also finds `example_x2`: the script keeps only
#   the exact name. The `account=` filter is exact, case sensitive, with no wildcard.
# - Requires `jq`, which reads the id.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/sites"
ACCOUNT="${1:-${ST_EXAMPLE_ACCOUNT:-john}}"
NAME="${2:-SSH_PULL}"

# The one site of that account with that name: "1 <id>", or how many there are.
# The name filter ignores case and takes a * wildcard, so the exact name is
# picked out of what comes back.
read -r FOUND SITE_ID < <(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" \
  --data-urlencode "account=${ACCOUNT}" --data-urlencode "name=${NAME}" --data-urlencode "fields=id,name" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r --arg name "${NAME}" '[(.result // [])[] | select(.name == $name)] | if length == 1 then "1 \(.[0].id)" else "\(length)" end')
if [ "${FOUND}" != "1" ]; then
    printf "Found %s sites named %s on the account %s; this script acts on exactly one.\n" "${FOUND:-0}" "${NAME}" "${ACCOUNT}"
    exit 1
fi

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" --head "${MAIN_URL}/${SITE_ID}" \
  -H "accept: */*" -H "${REFERER_HEADER}")
if [ "${HTTP_CODE}" = "200" ]; then
    printf "The site %s of %s exists, id %s.\n" "${NAME}" "${ACCOUNT}" "${SITE_ID}"
else
    printf "The site %s of %s, id %s, does not exist (HTTP %s).\n" "${NAME}" "${ACCOUNT}" "${SITE_ID}" "${HTTP_CODE}"
    exit 1
fi
