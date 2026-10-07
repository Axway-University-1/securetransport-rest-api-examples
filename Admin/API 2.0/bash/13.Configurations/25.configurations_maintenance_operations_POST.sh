#!/bin/bash
# ==============================================================================
# Script Name: 25.configurations_maintenance_operations_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script turns maintenance mode for zero downtime updates on or off, using
# the `/configurations/maintenance/operations` endpoint. Maintenance mode keeps
# automated systems from changing the server while it is updated.
#
# Usage:
# ./25.configurations_maintenance_operations_POST.sh start|stop
#
# Risk: disruptive - puts the whole server in maintenance mode
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - NOT RUN on the shared lab these examples were checked against: it changes
#   the whole server, and cannot simply be undone. Its request is checked
#   offline, against a stub.
# - Zero downtime updates are licensed only with an active SecureTransport
#   Enterprise Pack subscription; starting maintenance mode accepts that.
# - 24.configurations_maintenance_GET.sh reads the mode.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
OPERATION="$1"
[[ "${OPERATION}" =~ ^(start|stop)$ ]] || { printf "Usage: ./25.configurations_maintenance_operations_POST.sh start|stop\n"; exit 2; }

printf "Maintenance mode: %s...\n" "${OPERATION}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}/maintenance/operations?operation=${OPERATION}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
case "${HTTP_CODE}" in
    200|204) ;;
    *) printf '%s\n' "${RESPONSE%$'\n'*}"; exit 1 ;;
esac
