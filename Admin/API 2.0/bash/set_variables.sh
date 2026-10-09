#!/bin/bash
# ==============================================================================
# Script Name: set_variables.sh
# Author: Plamen Milenkov
# Created: 2025-08-05
# Location: Sofia
# ==============================================================================
# Description:
# This script sets environment variables required for API authentication and
# connectivity. It is intended to be sourced by other scripts that rely on
# ST_SERVER, ST_PORT, ST_USER, and ST_PASSWORD values.
#
# Usage:
# source ./set_variables.sh
#
# Notes:
# - Ensure this script is sourced, not executed, to preserve environment variables.
# - Values should be securely managed and updated as needed.
# - Rather than editing this file, put your own values in set_variables.local.sh
#   next to it. That file is excluded from git, so your credentials are never
#   committed. Anything it sets overrides the placeholders below.
# ==============================================================================

export ST_SERVER=""
export ST_PORT=""
export ST_USER=""
export ST_PASSWORD=""

#
# Two optional settings, not needed to run anything. A few examples need an
# account that already exists and, for the SSH sites, the partner's SSH port.
# They use john and 8022 unless you say otherwise. To change either, set it in
# set_variables.local.sh (or in the environment); an argument given to an
# example still wins over it. Leave them commented out to keep the defaults.
#
#   ST_EXAMPLE_ACCOUNT  the account those examples use (default john)
#   ST_SSH_PORT         the partner's SSH port, where an example names one (default 8022)
#
# export ST_EXAMPLE_ACCOUNT="john"
# export ST_SSH_PORT="8022"

#
# Load the local overrides, if present. Keep your real server and credentials
# here so that they stay out of the repository.
#
# ST_ADMIN_LOCAL_VARIABLES names another file to read instead; the test harness
# uses it so that it never has to write over your own set_variables.local.sh.
LOCAL_VARIABLES="${ST_ADMIN_LOCAL_VARIABLES:-$(dirname "${BASH_SOURCE[0]}")/set_variables.local.sh}"
if [ -f "${LOCAL_VARIABLES}" ]; then
    # shellcheck source=/dev/null
    source "${LOCAL_VARIABLES}"
fi
