#!/bin/bash
# ==============================================================================
# Script Name: 32.configurations_clusterManagement_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads whether the server is part of a cluster, using the
# `/configurations/clusterManagement` endpoint, and lists the cluster's nodes.
#
# Usage:
# ./32.configurations_clusterManagement_GET.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A standalone server answers isCluster false and no nodes.
# - Adding and removing nodes, bouncing a node, and the cluster operations
#   (bounce, synchronize) apply to a cluster only; they have no example here.
# - Requires `jq`, which prints the summary.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/clusterManagement" -H "accept: application/json" \
  -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "HTTP %s:\n%s\n" "${HTTP_CODE}" "${RESPONSE}"
    exit 1
fi
printf '%s\n' "${RESPONSE}"
printf "\nIn short:\n"
printf '%s' "${RESPONSE}" | jq -r 'if .isCluster then "  a \(.clusterMode) cluster of \(.clusterNodes | length) nodes", (.clusterNodes[] | "  \(.serverAddress // .)") else "  standalone, not a cluster" end'
