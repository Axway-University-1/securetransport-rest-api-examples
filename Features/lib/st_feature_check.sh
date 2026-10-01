#!/bin/bash
# ==============================================================================
# Script Name: st_feature_check.sh
# Author: Plamen Milenkov
# Created: 2026-09-30
# Location: Sofia
# ==============================================================================
# Description:
# Shared by every feature example. Loads the connection settings, asks the
# server for its version with GET /version, and compares it with the version in
# which the feature was introduced.
#
# - server is at or after that version: returns, and the example carries on
# - server is before that version:      prints SKIPPED and ends the example (exit 0)
# - version cannot be determined:       prints why and ends the example (exit 1)
#
# Usage:
# Source it near the top of an example, passing the version that introduced
# the feature:
#
#   SCRIPT_DIR=$(dirname "$(realpath "$0")")
#   source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
#
# Version format:
# <major>.<minor>[-<YYYYMMDD>], for example 5.5 or 5.5-20260924. A date with
# only the month (5.5-202609) is also accepted and counts as the start of that
# month. A server that reports no date part is treated as the base release, so
# it is older than any dated update of the same release.
#
# Notes:
# - Uses the same set_variables.sh as the Admin examples, so there is nothing
#   extra to configure.
# - Because it is sourced, the exit ends the calling example, which is the point.
# ==============================================================================

ST_REQUIRED_VERSION="$1"
ST_FEATURE_LIB_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

source "${ST_FEATURE_LIB_DIR}/../../Admin/API 2.0/bash/set_variables.sh"

# Turn 5.5-20260924 into 00500520260924, which compares correctly as a string.
# Prints nothing if the text is not a version.
st_version_key() {
    local text="$1" major minor update
    if [[ "${text}" =~ ^([0-9]+)\.([0-9]+)(\.[0-9]+)?(-([0-9]{6}([0-9]{2})?))?([^0-9].*)?$ ]]; then
        major="${BASH_REMATCH[1]}"
        minor="${BASH_REMATCH[2]}"
        update="${BASH_REMATCH[5]:-0}"
        [ "${#update}" -eq 6 ] && update="${update}00"
        printf '%03d%03d%08d' "$((10#${major}))" "$((10#${minor}))" "$((10#${update}))"
    fi
}

REQUIRED_KEY=$(st_version_key "${ST_REQUIRED_VERSION}")
if [ -z "${REQUIRED_KEY}" ]; then
    printf "ERROR: '%s' is not a version this check understands. Use e.g. 5.5-20260924.\n" "${ST_REQUIRED_VERSION}"
    exit 1
fi

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

VERSION_RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" \
  "https://${ST_SERVER}:${ST_PORT}/api/v2.0/version" \
  -H "accept: application/json" -H "${REFERER_HEADER}")

ST_SERVER_VERSION=$(printf '%s' "${VERSION_RESPONSE}" \
  | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)

SERVER_KEY=$(st_version_key "${ST_SERVER_VERSION}")
if [ -z "${SERVER_KEY}" ]; then
    printf "ERROR: could not read a version from GET /version on %s:%s.\n" "${ST_SERVER}" "${ST_PORT}"
    printf "       Check the server, port and credentials in set_variables.local.sh.\n"
    exit 1
fi

if [[ "${SERVER_KEY}" < "${REQUIRED_KEY}" ]]; then
    printf "SKIPPED: this feature needs SecureTransport %s or later. This server is %s.\n" \
      "${ST_REQUIRED_VERSION}" "${ST_SERVER_VERSION}"
    exit 0
fi

printf "Version check passed: server %s, feature needs %s.\n" "${ST_SERVER_VERSION}" "${ST_REQUIRED_VERSION}"
