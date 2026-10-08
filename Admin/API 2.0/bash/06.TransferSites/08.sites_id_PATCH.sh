#!/bin/bash
# ==============================================================================
# Script Name: 08.sites_id_PATCH.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script changes one property of a transfer site, using the `/sites/{id}`
# endpoint with PATCH: a JSON Patch document that replaces the download folder.
# Unlike PUT (07.sites_id_PUT.sh), it sends only what changes.
#
# Usage:
# ./08.sites_id_PATCH.sh ACCOUNT NAME [FOLDER]
#
#   ACCOUNT  the account the site belongs to
#   NAME     the site (it must be the only one with that name)
#   FOLDER   the new download folder (default /inbox)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It prints the folder before, to put it back with.
# - Only a site with a download folder (SSH, FTP, HTTP, folder monitor) can be patched this
#   way; the script says so for the others (a PeSIT or AS2 site has no such field).
# - Confirmed directly: a success answers 204, with no body. `replace` works on a field that
#   is null; `add` creates a nested one (`/postTransmissionActions/doAsOut`) and `remove`
#   sets it back to null, not absent. An empty patch is 204. `add` to `/additionalAttributes/
#   userVars.<name>` works. `type` is read only (400 "Patch operation on read only or
#   discriminator fields is not permitted."), a path that does not exist is 400 `Missing
#   field "nosuch"`, a wrong value type 400 "Something went wrong while patching the entity.",
#   and a failing `test` operation is 400. `replace` of `/id` and of `/account` answer 204 and
#   change nothing; of `/name` it renames the site.
# - Requires `jq`, which reads the id and builds the patch.
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
[ -n "${ACCOUNT}" ] && [ -n "${NAME}" ] || { printf "Usage: ./08.sites_id_PATCH.sh ACCOUNT NAME [FOLDER]\n"; exit 2; }
FOLDER="${3:-/inbox}"

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
if ! printf '%s' "${SITE_JSON}" | jq -e 'has("downloadFolder")' >/dev/null 2>&1; then
    printf "The site %s has no download folder to change.\n" "${NAME}"
    exit 1
fi
printf "The download folder of %s is now %s.\n" "${NAME}" "$(printf '%s' "${SITE_JSON}" | jq -r '.downloadFolder // "(none)"')"
BODY=$(jq -n --arg value "${FOLDER}" '[{op: "replace", path: "/downloadFolder", value: $value}]')

printf "Setting it to %s...\n" "${FOLDER}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/${SITE_ID}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "204" ]
