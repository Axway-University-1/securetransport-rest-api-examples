#!/bin/bash
# ==============================================================================
# Script Name: 01.accountSetup_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script creates an account and its transfer site in one call, using the
# `/accountSetup` endpoint. One body can carry the account, its certificates,
# sites, transfer profiles, routes and subscriptions.
#
# Usage:
# ./01.accountSetup_POST.sh
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The account is example_setup, with an SSH site named example_setup_site.
#   ACCOUNT_PASSWORD is read from the environment, so export it first:
#     export ACCOUNT_PASSWORD='the password'
# - Every site, transfer profile and subscription in the body names its
#   account too, even here: without it the call answers 400 "...account must
#   not be null" (confirmed directly).
# - Confirmed directly: the call is NOT all or nothing. A body that fails part
#   of the way - for example a transfer profile on an account with no PeSIT
#   site, "Account does not contain any PeSIT transfer sites." - answers 400,
#   yet what came before it in the body has been created.
# - The answer lists one message per object, with its URL.
# - Certificates are imported with a multipart/mixed body instead; see the API
#   reference.
# - 04.accounts_name_DELETE.sh removes the account, its sites and its profiles.
# - Requires `jq`, which builds the body.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

ACCOUNT="example_setup"
ACCOUNT_PASSWORD="${ACCOUNT_PASSWORD:-change_me}"

BODY=$(jq -n --arg name "${ACCOUNT}" --arg password "${ACCOUNT_PASSWORD}" --arg host "${ST_SERVER}" \
  '{accountSetup: {
      account: {name: $name, type: "user", uid: "41733", gid: "41733", homeFolder: ("/home/" + $name),
                user: {name: $name, passwordCredentials: {password: $password}}},
      sites: [{type: "ssh", protocol: "ssh", name: ($name + "_site"), account: $name,
               host: $host, port: "8022", userName: $name, usePassword: true, password: $password,
               transferType: "partner", uploadFolder: "/out"}]}}')

printf "Setting up the account %s and its site, in one call...\n" "${ACCOUNT}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accountSetup" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"

if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s. Part of it may have been created all the same:\n%s\n" "${HTTP_CODE}" "${RESPONSE}"
    exit 1
fi
printf '%s' "${RESPONSE}" | jq -r '.messages[] | "  " + .message'
