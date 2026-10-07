#!/bin/bash
# ==============================================================================
# Script Name: 03.ldapDomains_name_HEAD.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script checks whether an LDAP domain exists using the `/ldapDomains/{name}`
# endpoint with HEAD: 200 when it does, 404 when it does not.
#
# Usage:
# ./03.ldapDomains_name_HEAD.sh [NAME]
#
#   NAME  the domain (default example_ldap)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The name goes into the path URL-encoded once, with jq's @uri.
# - Requires `jq`, which URL-encodes the name.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/ldapDomains"
NAME="${1:-example_ldap}"
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" --head "${MAIN_URL}/${ENCODED}" \
  -H "accept: */*" -H "${REFERER_HEADER}")
if [ "${HTTP_CODE}" = "200" ]; then
    printf "The LDAP domain %s exists.\n" "${NAME}"
else
    printf "The LDAP domain %s does not exist (HTTP %s).\n" "${NAME}" "${HTTP_CODE}"
    exit 1
fi
