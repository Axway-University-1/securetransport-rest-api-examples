#!/bin/bash
# ==============================================================================
# Script Name: 10.certificates_requests_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the certificate signing requests waiting on the server,
# using the `/certificates/requests` endpoint.
#
# Usage:
# ./10.certificates_requests_GET.sh [USAGE]
#
#   USAGE  local or private (default: both)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: with a filter, resultSet.totalCount still counts every
#   request; returnCount, and the result, are the filtered ones.
# - Confirmed directly: keySize reads 0 and signAlgorithm null, whatever the
#   request was made with.
# - Requires `jq`, which prints one request per line.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/certificates/requests"
USAGE="$1"
QUERY="fields=id,subject,usage,account"
[ -n "${USAGE}" ] && QUERY="${QUERY}&usage=${USAGE}"

printf "The requests: id, subject, usage, account:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?${QUERY}" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '(.result // [])[] | "  \(.id)  \(.subject)  \(.usage)  \(.account // "-")"'
