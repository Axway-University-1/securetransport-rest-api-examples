#!/bin/bash
# ==============================================================================
# Script Name: 38.configurations_externalStores_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script adds a HashiCorp Vault as an external store, using the
# `/configurations/externalStores` endpoint. The server logs in to Vault with
# an AppRole, then reads KV version 2 secrets with the token it gets back.
#
# Usage:
# ./38.configurations_externalStores_POST.sh VAULT_URL [MOUNT]
#
#   VAULT_URL  the Vault, for example https://vault.example.com:8200
#   MOUNT      the KV secrets engine's path (default secret)
#
# Risk: config
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The store is example_vault.
# - VAULT_ROLE_ID and VAULT_SECRET_ID, the AppRole's credentials, are read from
#   the environment, so export them first:
#     export VAULT_ROLE_ID='the role id'
#     export VAULT_SECRET_ID='the secret id'
# - ${vault.api.auth.token} in the headers is replaced by the token the login
#   answered, which the server finds at auth.token ($.auth.client_token).
#   pathPrefix ($.data.data) is where a KV version 2 answer holds the secret.
# - Over https the Vault's certificate must be trusted: import its CA as a
#   trusted certificate and name it in tls.caAliases. Confirmed directly: an
#   untrusted one fails the test with "TLS Error code 46: Certificate is
#   unknown or untrusted!"
# - 42.configurations_externalStores_name_operations_POST_test.sh tries it.
# - tests/integration/lib/dummy_servers.py has a FakeVault that can stand in for
#   a HashiCorp Vault to try these examples against.
# - Requires `jq`, which builds the body.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
VAULT_URL="$1"
MOUNT="${2:-secret}"
if [ -z "${VAULT_URL}" ]; then
    printf "Usage: ./38.configurations_externalStores_POST.sh VAULT_URL [MOUNT]\n"
    exit 2
fi
if [ -z "${VAULT_ROLE_ID}" ] || [ -z "${VAULT_SECRET_ID}" ]; then
    printf "Set VAULT_ROLE_ID and VAULT_SECRET_ID first.\n"
    exit 2
fi

BODY=$(jq -n --arg url "${VAULT_URL}" --arg mount "${MOUNT}" --arg role "${VAULT_ROLE_ID}" --arg secret "${VAULT_SECRET_ID}" '{
  name: "example_vault", version: "2",
  baseUrl: $url, uri: "/v1/\($mount)/data", method: "GET",
  pathPrefix: "$.data.data", cacheTimeout: 600,
  authHeader: "X-Vault-Token",
  headers: {"X-Vault-Token": "${vault.api.auth.token}", "Content-Type": "application/json"},
  openTimeout: 5, readTimeout: 30, maxRetries: 3, retryIntervalMs: 100,
  tls: {protocols: ["TLSv1.3", "TLSv1.2"], skipHostNameVerification: false},
  auth: {
    baseUrl: $url, uri: "/v1/auth/approle/login",
    body: {role_id: $role, secret_id: $secret},
    token: "$.auth.client_token",
    openTimeout: 5, readTimeout: 30, maxRetries: 3, retryIntervalMs: 100,
    headers: {"Content-Type": "application/json", "Accept": "application/json"},
    tls: {protocols: ["TLSv1.3", "TLSv1.2"], skipHostNameVerification: false}}}')

printf "Adding the external store example_vault, %s...\n" "${VAULT_URL}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}/externalStores" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "201" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
