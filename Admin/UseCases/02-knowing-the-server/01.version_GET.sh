#!/bin/bash
# ==============================================================================
# Script Name: 01.version_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# What is this server? GET /version says which product and release, the build, the operating system, the update level and the plugins installed. This prints the few facts a script wants, and the plugins by type.
#
# Usage:
# ./01.version_GET.sh
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/02.Introduction/01.version_GET.sh.
# - The answer is long, and most of it is plugins and SPI versions: narrow it with jq.
# - A script that depends on a feature of a release reads the version first (see Features/lib/st_feature_check.sh).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
st_session

result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/version" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "HTTP ${code}"
[[ "${code}" == 200 ]] || { echo "${result%???}"; exit 1; }
BODY="${result%???}"
echo "${BODY}" | jq -r '"Server:  \(.serverType)", "Release: \(.version) (build \(.build))", "Update:  \(.updateLevel)", "System:  \(.os), \(.osDistribution)", "Runs as: \(.user)", "Docker:  \(.dockerMode)"'
echo "Plugins: $(echo "${BODY}" | jq '.plugins | length')"
echo "${BODY}" | jq -r '.plugins | group_by(.type)[] | "  \(.[0].type): \(map(.name) | join(", "))"' 
