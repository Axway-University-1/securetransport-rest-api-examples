#!/bin/bash
# ==============================================================================
# Script Name: 06.sites_id_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script reads one transfer site, using the `/sites/{id}` endpoint with GET. It
# demonstrates:
# - Looking up the id by account and name
# - Reading the whole site, and printing a short summary of it
# - Asking for only some of its fields, with `fields=`
#
# Usage:
# ./06.sites_id_GET.sh [ACCOUNT [NAME]]
#
#   ACCOUNT  the account the site belongs to (default john)
#   NAME     the site (default SSH_PULL, which 02.sites_POST_ssh.sh creates)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The site is looked up by account and name, and must be the only one with that name.
# - Confirmed directly: an unknown id is a JSON 404, "Site with id X not found or not
#   accessible.". `fields=` keeps the keys named (and always `type`); an unknown field is 400
#   "Field nosuch does not exist.". `type=`, which the reference says is needed to read a field
#   of one site type, is not: `type=http` or `type=bogus` on an SSH site answers the site.
# - The password reads back encrypted (`{AES128}...`), never in clear. Send that text back
#   and the password is kept (see 07.sites_id_PUT.sh).
# - The fields differ by type: an SSH, FTP or HTTP site has host, port and folders; a custom
#   site (S3, SMB...) has `customProperties` instead; run it on one of each to see.
# - Requires `jq`, which reads the id and prints the summary.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/sites"
ACCOUNT="${1:-john}"
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

SITE_JSON=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${SITE_ID}" -H "accept: application/json" -H "${REFERER_HEADER}")
if ! printf '%s' "${SITE_JSON}" | jq -e '.id' >/dev/null 2>&1; then
    printf "Could not read the site %s (id %s).\n" "${NAME}" "${SITE_ID}"
    exit 1
fi
printf "The site %s of %s, id %s:\n" "${NAME}" "${ACCOUNT}" "${SITE_ID}"
printf '%s' "${SITE_JSON}" | jq -r '"  type:             \(.type)",
  "  protocol:         \(.protocol)",
  "  partner:          \(.host // "-"):\(.port // "-")",
  "  user:             \(.userName // "-")",
  "  download folder:  \(.downloadFolder // "-")",
  "  upload folder:    \(.uploadFolder // "-")",
  "  max connections:  \(.maxConcurrentConnection)",
  "  access level:     \(.accessLevel)",
  "  password:         \(.password // "-")"'

printf "\nOnly some of its fields, with fields=name,host,port:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}/${SITE_ID}" --data-urlencode "fields=name,host,port" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -c .
