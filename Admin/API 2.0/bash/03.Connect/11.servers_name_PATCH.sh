#!/bin/bash
# ==============================================================================
# Script Name: 11.servers_name_PATCH.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script demonstrates how to PATCH an SSH server configuration using curl.
# It performs:
# - A PATCH to update the port
# - A PATCH to remove RSA keys from the publicKeys field
#
# Usage:
# ./11.servers_name_PATCH.sh
#
# Risk: config - changes a protocol server
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The PATCH method allows partial updates to specific fields.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

NAME="SSH_TEST_SERVER_1"

printf "Patching the server port...\n"
curl -s -o /dev/null -w "%{http_code}\n" -k -u "${ST_USER}:${ST_PASSWORD}" -X "PATCH" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers/${NAME}" \
-H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
-d "[{ \"op\": \"replace\", \"path\": \"/port\", \"value\": 8026 }]"

printf "Patching the server publicKeys...\n"
OLD_PUBLIC_KEYS=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers/${NAME}" \
-H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" | \
grep "publicKeys" | awk -F ':' '{print $2}' | sed 's/",/"/g' | sed 's/"//g')
echo "Public keys before removing rsa: ${OLD_PUBLIC_KEYS}"

NEW_PUBLIC_KEYS=$(echo "${OLD_PUBLIC_KEYS}" | sed 's/[a-zA-Z0-9-]*rsa[a-zA-Z0-9-]*//g' | sed 's/,,//g')
echo "Public keys after removal: ${NEW_PUBLIC_KEYS}"

curl -k -u "${ST_USER}:${ST_PASSWORD}" -X "PATCH" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers/${NAME}" \
-H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
-d "[{ \"op\": \"replace\", \"path\": \"/publicKeys\", \"value\": \"${NEW_PUBLIC_KEYS}\" }]"

printf "\nDone\n"
printf "Retrieve the server information to check the changes...\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers/${NAME}" \
-H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json"
