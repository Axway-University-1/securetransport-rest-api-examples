#!/bin/bash
# ==============================================================================
# Script Name: 06.configurations_settings_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# How is the server set up? Reads two settings objects, GET /configurations/loginSettings and GET /configurations/maintenance, and narrows each: how users and administrators are authenticated, and whether the server is in maintenance mode.
#
# Usage:
# ./06.configurations_settings_GET.sh
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/13.Configurations/21.configurations_loginSettings_GET.sh and 24.configurations_maintenance_GET.sh.
# - It only reads. Maintenance mode is changed by another call (25) that is not part of the use cases: it changes the whole server.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/configurations/loginSettings" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "HTTP ${code}"
[[ "${code}" == 200 ]] || { echo "${result%???}"; exit 1; }
BODY="${result%???}"
echo "Login settings:"
echo "${BODY}" | jq -r '"  user password:       \(.requirePassword)", "  user single sign-on: \(.userSSO)", "  administrators SSO:  \(.adminSSO)", "  LDAP:                \(.ldapOption)"'
result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/configurations/maintenance" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "HTTP ${code}"
[[ "${code}" == 200 ]] || { echo "${result%???}"; exit 1; }
BODY="${result%???}"
echo "Maintenance mode: $(echo "${BODY}" | jq -r '.zduMaintenanceMode')"
