#!/bin/bash
# ==============================================================================
# Script Name: 07.sites_id_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script replaces a transfer site, using the `/sites/{id}` endpoint with PUT: it
# reads the site, changes how many connections it may open at once
# (maxConcurrentConnection, which every type of site has), and sends the whole site
# back.
#
# Usage:
# ./07.sites_id_PUT.sh ACCOUNT NAME [VALUE]
#
#   ACCOUNT  the account the site belongs to
#   NAME     the site (it must be the only one with that name)
#   VALUE    the new maxConcurrentConnection, 0 to 65535 (default 2; 0 means no limit)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It prints the value before, to put it back with.
# - PUT replaces the whole site. Confirmed directly: a hand-built fragment (the name, host,
#   port, user and password only) answers 204 and silently resets everything left out, the
#   folders, the pattern, the renaming and the connection limit. That is why the site is read
#   first and sent back with only one field changed. metadata, the read-only links, is left out.
# - Confirmed directly: a success answers 204, with no body. The site read back carries the
#   password encrypted, and sending that text back keeps the password; a body with no password
#   is 400 "Specify password", and plain text is encrypted anew. An unknown id is a JSON 404.
#   A body with another `name` renames the site; one with another `account` is accepted (204)
#   and ignored; a different `type` is refused, 400, and so is a body with no `type`.
# - Requires `jq`, which reads the id and edits the site.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/sites"
ACCOUNT="$1"
NAME="$2"
[ -n "${ACCOUNT}" ] && [ -n "${NAME}" ] || { printf "Usage: ./07.sites_id_PUT.sh ACCOUNT NAME [VALUE]\n"; exit 2; }
VALUE="${3:-2}"
[[ "${VALUE}" =~ ^[0-9]+$ ]] && [ "${VALUE}" -le 65535 ] || { printf "VALUE is a number from 0 to 65535, not %s.\n" "${VALUE}"; exit 2; }

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

SITE_JSON=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${SITE_ID}" -H "accept: application/json" -H "${REFERER_HEADER}")
if ! printf '%s' "${SITE_JSON}" | jq -e '.id' >/dev/null 2>&1; then
    printf "Could not read the site %s (id %s).\n" "${NAME}" "${SITE_ID}"
    exit 1
fi
printf "maxConcurrentConnection of %s is now %s.\n" "${NAME}" "$(printf '%s' "${SITE_JSON}" | jq -r '.maxConcurrentConnection')"
BODY=$(printf '%s' "${SITE_JSON}" | jq -c --argjson value "${VALUE}" '.maxConcurrentConnection = $value | del(.metadata)')

printf "Setting it to %s...\n" "${VALUE}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/${SITE_ID}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "204" ]
