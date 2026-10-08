#!/bin/bash
# ==============================================================================
# Script Name: set_variables.sh
# ==============================================================================
# Description:
# This script sets the environment variables required by the EndUser API
# examples. It is intended to be sourced by the other scripts, which rely on
# ST_SERVER, ST_PORT, ST_USER, and ST_PASSWORD values.
#
# The same four variable names are used by the Admin examples, so there is one
# set of names to learn across the whole project.
#
# Two further values are derived from them for convenience:
#   ST_URL        - the full base URL of the EndUser API
#   ST_BASIC_AUTH - the base64 encoded 'user:password' pair, as required by the
#                   Authorization header. You do not need to encode it yourself.
#
# Usage:
# source ./set_variables.sh
#
# Notes:
# - Ensure this script is sourced, not executed, to preserve the variables.
# - Rather than editing this file, put your own values in set_variables.local.sh
#   next to it. That file is excluded from git, so your credentials are never
#   committed. Anything it sets overrides the placeholders below.
# ==============================================================================

#
# The user level port is 8443 for a non root install and 443 for a root install.
#
export ST_SERVER=""
export ST_PORT="8443"
export ST_USER=""
export ST_PASSWORD=""

#
# Load the local overrides, if present. Keep your real server and credentials
# here so that they stay out of the repository.
#
# ST_ENDUSER_LOCAL_VARIABLES names another file to read instead; the test harness
# uses it so that it never has to write over your own set_variables.local.sh.
LOCAL_VARIABLES="${ST_ENDUSER_LOCAL_VARIABLES:-$(dirname "${BASH_SOURCE[0]}")/set_variables.local.sh}"
if [ -f "${LOCAL_VARIABLES}" ]; then
    # shellcheck source=/dev/null
    source "${LOCAL_VARIABLES}"
fi

#
# Derived values. Anything below this point is built from the four variables
# above, so there is normally no reason to change it.
#
export ST_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0"
ST_BASIC_AUTH="$(printf '%s:%s' "${ST_USER}" "${ST_PASSWORD}" | base64 | tr -d '\n')"
export ST_BASIC_AUTH

#
# Fail early with a clear message rather than sending a request that cannot work.
#
if [ -z "${ST_SERVER}" ] || [ -z "${ST_USER}" ] || [ -z "${ST_PASSWORD}" ]; then
    echo "No configuration found."
    echo "Copy set_variables.local.example.sh to set_variables.local.sh and set"
    echo "ST_SERVER, ST_PORT, ST_USER and ST_PASSWORD for your environment."
    return 1 2>/dev/null || exit 1
fi
