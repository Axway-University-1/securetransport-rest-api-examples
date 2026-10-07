#!/bin/bash
# ==============================================================================
# Script Name: 17.configurations_database_operations_POST_test.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script tests a database connection, using the
# `/configurations/database/operations` endpoint with operation=test: the
# server connects with the settings given and reports whether it could. The
# settings in use do not change.
#
# Usage:
# ./17.configurations_database_operations_POST_test.sh
#
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It tests the database the server uses now: the host, port and name come
#   from 16.configurations_database_GET.sh's call; the user too, unless DB_USER
#   is set. DB_PASSWORD is read from the environment, so export it first:
#     export DB_PASSWORD='the database password'
# - The body is a multipart form. host, port, databaseName, username and
#   password are required.
# - Confirmed directly: a wrong password answers 400 "Database Configuration
#   test failed: FATAL: password authentication failed for user ...".
# - The other operations - restart, createPartitions, changePassword,
#   changePort, and the database certificates - change the server and have no
#   example here.
# - Requires `jq`, which reads the settings.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
if [ -z "${DB_PASSWORD}" ]; then
    printf "Set DB_PASSWORD to the database password first.\n"
    exit 2
fi
SETTINGS=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/database" -H "accept: application/json" -H "${REFERER_HEADER}")
DB_HOST=$(printf '%s' "${SETTINGS}" | jq -r '.host // empty')
DB_PORT=$(printf '%s' "${SETTINGS}" | jq -r '.port // empty')
DB_NAME=$(printf '%s' "${SETTINGS}" | jq -r '.databaseName // empty')
DB_TYPE=$(printf '%s' "${SETTINGS}" | jq -r '.databaseType // empty')
DB_USER="${DB_USER:-$(printf '%s' "${SETTINGS}" | jq -r '.username // empty')}"
[ -n "${DB_HOST}" ] || { printf "Could not read the database settings.\n"; exit 1; }

printf "Testing %s at %s:%s, database %s, user %s...\n" "${DB_TYPE}" "${DB_HOST}" "${DB_PORT}" "${DB_NAME}" "${DB_USER}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}/database/operations?operation=test" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  -F "databaseType=${DB_TYPE}" -F "host=${DB_HOST}" -F "port=${DB_PORT}" -F "databaseName=${DB_NAME}" \
  -F "username=${DB_USER}" -F "password=${DB_PASSWORD}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
[ -n "${RESPONSE}" ] && printf '%s' "${RESPONSE}" | jq -r '.message // .' 2>/dev/null
case "${HTTP_CODE}" in
    200|204) printf "The connection works.\n" ;;
    *) exit 1 ;;
esac
