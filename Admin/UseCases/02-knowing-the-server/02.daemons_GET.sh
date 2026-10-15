#!/bin/bash
# ==============================================================================
# Script Name: 02.daemons_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Which listeners are running? GET /daemons gives the state of each protocol daemon: ftp, http, pesit, ssh and as2.
#
# Usage:
# ./02.daemons_GET.sh
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/03.Connect/01.daemons_GET.sh.
# - A daemon that is Running does not mean a server is listening: a server is a separate object (03). The scripts that start and stop them are not part of this use case on purpose.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/daemons" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "HTTP ${code}"
[[ "${code}" == 200 ]] || { echo "${result%???}"; exit 1; }
BODY="${result%???}"
echo "${BODY}" | jq -r 'to_entries[] | "  \(.key | sub("Status$"; ""))\t\(.value)"' 
