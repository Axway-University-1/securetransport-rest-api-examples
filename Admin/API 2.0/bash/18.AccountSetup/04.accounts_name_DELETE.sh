#!/bin/bash
# ==============================================================================
# Script Name: 04.accounts_name_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script removes the account 01.accountSetup_POST.sh sets up, using the
# `/accounts/{name}` endpoint. /accountSetup has no DELETE of its own:
# deleting the account removes what was set up with it.
#
# Usage:
# ./04.accounts_name_DELETE.sh
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: deleting the account also deletes its transfer sites
#   and transfer profiles.
# - The files in the account's home folder stay on disk. See
#   05.Accounts/07.accounts_name_DELETE.sh.
# - Only ever point it at an account you set up.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

ACCOUNT="example_setup"

printf "Deleting the account %s, with its sites and profiles...\n" "${ACCOUNT}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE \
  "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/${ACCOUNT}" -H "accept: */*" -H "${REFERER_HEADER}")
printf "HTTP %s\n" "${HTTP_CODE}"
[ "${HTTP_CODE}" = "204" ]
