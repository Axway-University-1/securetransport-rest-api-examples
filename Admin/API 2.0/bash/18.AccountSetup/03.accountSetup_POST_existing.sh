#!/bin/bash
# ==============================================================================
# Script Name: 03.accountSetup_POST_existing.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script adds a transfer site to an account that already exists, using
# the `/accountSetup` endpoint. The account in the body is skipped, not
# refused, so the same call works for a new account and an existing one.
#
# Usage:
# ./03.accountSetup_POST_existing.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Run 01.accountSetup_POST.sh first. This adds example_setup_site2 to
#   example_setup. ACCOUNT_PASSWORD is read from the environment, as there.
# - Confirmed directly: it answers 200, with "Account with name example_setup
#   skipped because it already exists." and "Site with name example_setup_site2
#   created.", each with its URL.
# - 04.accounts_name_DELETE.sh removes the account and both sites.
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

# The account as it is, and the one new site
BODY=$(jq -n --arg name "${ACCOUNT}" --arg password "${ACCOUNT_PASSWORD}" --arg host "${ST_SERVER}" \
  '{accountSetup: {
      account: {name: $name, type: "user", uid: "41733", gid: "41733", homeFolder: ("/home/" + $name),
                user: {name: $name, passwordCredentials: {password: $password}}},
      sites: [{type: "ssh", protocol: "ssh", name: ($name + "_site2"), account: $name,
               host: $host, port: "8022", userName: $name, usePassword: true, password: $password,
               transferType: "partner", downloadFolder: "/in", downloadPattern: "*"}]}}')

printf "Adding a site to the existing account %s...\n" "${ACCOUNT}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accountSetup" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"

if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s:\n%s\n" "${HTTP_CODE}" "${RESPONSE}"
    exit 1
fi
printf '%s' "${RESPONSE}" | jq -r '.messages[] | "  " + .message'
