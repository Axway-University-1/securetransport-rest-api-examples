#!/bin/bash
# ==============================================================================
# Script Name: 04.sites_id_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-05
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes transfer sites using the `/sites/{id}` endpoint.
# A site is deleted by its id, not its name, so it demonstrates:
# - Looking up the id of a site by account and name
# - Deleting the site by that id, printing the HTTP code and what was deleted
#
# Usage:
# ./04.sites_id_DELETE.sh
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This cleans up the three sites that 01.sites_POST.sh and 02.sites_POST_ssh.sh create for the account
#   "john": SSH_PULL and SSH_PUSH (02), and HTTP (01, which was left out of the cleanup before). Only ever point it at sites
#   you created: an account that has a site of its own called HTTP loses it.
# - A site that a subscription or a route still uses cannot be deleted. Delete
#   those first (07.Subscriptions, 09.CompositeRoutes).
# - The name filter ignores case and takes a * wildcard, so the exact name is picked out of what comes back, and a name that two sites
#   match is not deleted (exit 1).
# - Requires `jq`, which reads the id out of the response.
# - Confirmed directly: a delete is 204 with no body; an id that is not there is a JSON 404, "Site with id X not found or not accessible.".
# - Exit codes: 0 when every site was deleted or was not there, 1 when the server refuses a lookup or a delete, or a name is ambiguous.
#   It takes no argument.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/sites"

if [ "$#" -ne 0 ]; then
    printf "Usage: ./04.sites_id_DELETE.sh\n"
    exit 2
fi

ACCOUNT="john"
FAILED=0

# The answer to a refused call: the server's own messages, or the text as it is
show_error() { printf '%s' "$1" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "$1"; }

for NAME in "SSH_PULL" "SSH_PUSH" "HTTP"; do
    # The sites of that account whose name matches (the filter is not exact): the ids of those with exactly this name
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" \
      --data-urlencode "account=${ACCOUNT}" --data-urlencode "name=${NAME}" --data-urlencode "fields=id,name" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "Could not look up the site '%s' of '%s': HTTP %s\n" "${NAME}" "${ACCOUNT}" "${HTTP_CODE}"
        show_error "${RESPONSE}"
        FAILED=1
        continue
    fi
    IDS=$(printf '%s' "${RESPONSE}" | jq -r --arg name "${NAME}" '[(.result // [])[] | select(.name == $name) | .id][]')
    COUNT=$(printf '%s' "${IDS}" | grep -c .)

    if [ "${COUNT}" -eq 0 ]; then
        printf "The account '%s' has no site '%s'.\n" "${ACCOUNT}" "${NAME}"
        continue
    fi
    if [ "${COUNT}" -gt 1 ]; then
        printf "The account '%s' has %s sites named '%s'; none deleted.\n" "${ACCOUNT}" "${COUNT}" "${NAME}"
        FAILED=1
        continue
    fi

    SITE_ID="${IDS}"
    printf "Deleting the site '%s' (%s)...\n" "${NAME}" "${SITE_ID}"
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/$(jq -rn --arg n "${SITE_ID}" '$n|@uri')" \
      -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    printf "HTTP %s\n" "${HTTP_CODE}"
    if [ "${HTTP_CODE}" != "204" ]; then
        show_error "${RESPONSE}"
        FAILED=1
        continue
    fi
    printf "Deleted the site '%s'.\n" "${NAME}"
done
exit "${FAILED}"
