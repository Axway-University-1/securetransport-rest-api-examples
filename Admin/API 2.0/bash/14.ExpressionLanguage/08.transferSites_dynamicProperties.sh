#!/bin/bash
# ==============================================================================
# Script Name: 08.transferSites_dynamicProperties.sh
# Author: Plamen Milenkov
# Created: 2025-09-29
# Location: Sofia
# ==============================================================================
# Description:
# This script demonstrates the DXAGENT_TRANSFERSAPI_* pattern: a transfer
# site's own field holds a template like ${DXAGENT_TRANSFERSAPI_SERVER}
# instead of a fixed value, so the same site can be reused for many partners
# or file patterns - the actual value is supplied later, per request, in
# customProperties on a transfer operation (POST /transfers/operations),
# which this script does not call - only the site side of the pattern is
# shown here.
#
# APIs used - /myself ( ST login and logout )
#             /sites ( POST, GET, DELETE )
#
# Usage:
# ./08.transferSites_dynamicProperties.sh
#
# Notes:
# - Confirmed directly against a real server: a site's host and
#   downloadPattern fields accept and store the literal template text
#   verbatim - "${DXAGENT_TRANSFERSAPI_SERVER}" is not evaluated or rejected
#   at creation time, it is just a string until a real transfer request
#   supplies the matching customProperties key.
# - "${DXAGENT_TRANSFERSAPI_FOO}" is a generic placeholder shape from the EL
#   documentation - FOO is any name of your choosing, matched against
#   whatever key you send as customProperties.FOO on the actual pull/push
#   request. This example uses SERVER and FILE to match the fields they fill.
# - This site's account "john" must already exist, the same assumption
#   06.TransferSites/01.sites_POST.sh makes.
# ==============================================================================

SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/sites"
NAME="ZZTEST_EL_dynamicSite"

printf "\nCreating %s with templated host and downloadPattern fields...\n" "${NAME}"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
-d "{
  \"name\": \"${NAME}\",
  \"type\": \"http\",
  \"protocol\": \"http\",
  \"account\": \"john\",
  \"host\": \"\${DXAGENT_TRANSFERSAPI_SERVER}\",
  \"port\": \"443\",
  \"downloadPattern\": \"\${DXAGENT_TRANSFERSAPI_FILE}\",
  \"uploadFolder\": \"/\",
  \"userName\": \"john\"
}"

printf "\n\nReading it back - both fields should still hold the literal template text:\n"
curl -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?name=${NAME}&fields=name,host,downloadPattern" -H "accept: application/json" -H "${REFERER_HEADER}"

printf "\n\nCleaning up the throwaway site...\n"
ID=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?name=${NAME}&fields=id" -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.result[0].id // empty')
if [ -n "${ID}" ]; then
    curl -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${ID}" -H "accept: application/json" -H "${REFERER_HEADER}"
    printf "\ndeleted %s (%s)\n" "${NAME}" "${ID}"
fi
