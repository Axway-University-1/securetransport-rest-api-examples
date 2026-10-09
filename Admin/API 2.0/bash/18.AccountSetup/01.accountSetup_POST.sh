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
# [export ACCOUNT_PASSWORD='the password of example_setup']
# ./01.accountSetup_POST.sh
#
#   ACCOUNT_PASSWORD  the password of example_setup and of its site's login (optional): when it is not set, one is generated
#                     (12 random letters and digits after a fixed beginning) and printed once
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The account is example_setup, with an SSH site named example_setup_site.
#   ACCOUNT_PASSWORD is read from the environment (export ACCOUNT_PASSWORD='the password' first); when it is not set, a
#   password is generated and printed, so the account is never created with a password anyone could guess.
# - Every site, transfer profile and subscription in the body names its
#   account too, even here: without it the call answers 400 "...account must
#   not be null" (confirmed directly).
# - Confirmed directly: the call is NOT all or nothing. A body that fails part
#   of the way - for example a transfer profile on an account with no PeSIT
#   site, "Account does not contain any PeSIT transfer sites." - answers 400,
#   yet what came before it in the body has been created.
# - The answer lists one message per object, with its URL.
# - The site logs in over SSH on port 8022, or on ST_SSH_PORT when that is set (see set_variables.local.example.sh).
# - Certificates are imported with a multipart/mixed body instead; see the API
#   reference.
# - 04.accounts_name_DELETE.sh removes the account, its sites and its profiles.
# - Requires `jq`, which builds the body.
# - The password is never in the file. A generated one is printed once, after the call, also when the call fails (part of the body
#   may have been created: see above).
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

# The account and its site, with the password
BODY=$(jq -n --arg name "${ACCOUNT}" --arg password "${PASSWORD}" --arg host "${ST_SERVER}" --arg sshport "${ST_SSH_PORT:-8022}" \
  '{accountSetup: {
      account: {name: $name, type: "user", uid: "41733", gid: "41733", homeFolder: ("/home/" + $name),
                user: {name: $name, passwordCredentials: {password: $password}}},
      sites: [{type: "ssh", protocol: "ssh", name: ($name + "_site"), account: $name,
               host: $host, port: $sshport, userName: $name, usePassword: true, password: $password,
               transferType: "partner", uploadFolder: "/out"}]}}')

printf "Setting up the account %s and its site, in one call...\n" "${ACCOUNT}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accountSetup" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"

if [ -n "${GENERATED}" ]; then
    printf "The password of %s is %s (generated: it is not shown again).\n" "${ACCOUNT}" "${PASSWORD}"
fi
if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s. Part of it may have been created all the same:\n%s\n" "${HTTP_CODE}" "${RESPONSE}"
    exit 1
fi
printf '%s' "${RESPONSE}" | jq -r '.messages[] | "  " + .message'
