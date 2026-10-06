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
# - Deleting the site by that id
#
# Usage:
# ./04.sites_id_DELETE.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This cleans up the two sites 02.sites_POST_ssh.sh creates for the account
#   "john": SSH_PULL and SSH_PUSH. Only ever point it at sites you created.
# - A site that a subscription or a route still uses cannot be deleted. Delete
#   those first (07.Subscriptions, 09.CompositeRoutes).
# - Requires `jq`, which reads the id out of the response.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

ACCOUNT="john"

for NAME in "SSH_PULL" "SSH_PUSH"; do
    SITE_ID=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET \
      "https://${ST_SERVER}:${ST_PORT}/api/v2.0/sites?account=${ACCOUNT}&name=${NAME}&fields=id" \
      -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.result[0].id // empty')

    if [ -z "${SITE_ID}" ]; then
        printf "The account '%s' has no site '%s'.\n" "${ACCOUNT}" "${NAME}"
        continue
    fi

    printf "Deleting the site '%s' (%s)...\n" "${NAME}" "${SITE_ID}"
    curl -s -o /dev/null -w "HTTP %{http_code}\n" -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE \
      "https://${ST_SERVER}:${ST_PORT}/api/v2.0/sites/${SITE_ID}" \
      -H "accept: */*" -H "${REFERER_HEADER}"
done
