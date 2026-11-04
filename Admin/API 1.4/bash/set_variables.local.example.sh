#!/bin/bash
# ==============================================================================
# Copy this file to set_variables.local.sh and fill in your own values.
#
#   cp set_variables.local.example.sh set_variables.local.sh
#
# This is the one settings file of the API 1.4 examples in this folder.
# Every script reads set_variables.local.sh, and stops
# with a message when it is not there. It is excluded from git, so your
# credentials are never committed.
# ==============================================================================

# The SecureTransport host, without the protocol or port
export ST_SERVER="st.example.com"

# The admin port. 8444 for a non root install, 444 for a root install.
export ST_PORT="8444"

# An administrator account and its password, in plain text
export ST_USER="apiadmin"
export ST_PASSWORD="change_me"

