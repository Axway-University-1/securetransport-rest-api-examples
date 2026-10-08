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
# [export ACCOUNT_PASSWORD='the password of example_setup']
# ./03.accountSetup_POST_existing.sh
#
#   ACCOUNT_PASSWORD  the password of example_setup and of its site's login (optional): when it is not set, one is generated
#                     (12 random letters and digits after a fixed beginning) and printed once
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Run 01.accountSetup_POST.sh first. This adds example_setup_site2 to
#   example_setup. ACCOUNT_PASSWORD is read from the environment, as there, and generated and printed when it is not set (the
#   account exists, so its own password is not touched; the site gets this one).
# - Confirmed directly: it answers 200, with "Account with name example_setup
#   skipped because it already exists." and "Site with name example_setup_site2
#   created.", each with its URL.
# - 04.accounts_name_DELETE.sh removes the account and both sites.
# - Requires `jq`, which builds the body.
# - The password is never in the file: no placeholder is used, so the site is never created with a password anyone could guess.
# - Exit codes: 0 when the call answers 200, 1 otherwise.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

ACCOUNT="example_setup"
PASSWORD="${ACCOUNT_PASSWORD}"
GENERATED=""
if [ -z "${PASSWORD}" ]; then
    PASSWORD="Ex1!$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12)"
    GENERATED="yes"
fi

# The account as it is, and the one new site
BODY=$(jq -n --arg name "${ACCOUNT}" --arg password "${PASSWORD}" --arg host "${ST_SERVER}" \
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

if [ -n "${GENERATED}" ]; then
    printf "The password of the site's login is %s (generated: it is not shown again).\n" "${PASSWORD}"
fi
if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s:\n%s\n" "${HTTP_CODE}" "${RESPONSE}"
    exit 1
fi
printf '%s' "${RESPONSE}" | jq -r '.messages[] | "  " + .message'
