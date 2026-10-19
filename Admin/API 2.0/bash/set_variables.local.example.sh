#!/bin/bash
# ==============================================================================
# Copy this file to set_variables.local.sh and fill in your own values.
#
#   cp set_variables.local.example.sh set_variables.local.sh
#
# This is the one settings file of the examples in this folder, and of the use
# cases that go with it: every script reads set_variables.local.sh, and stops
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

# Optional. Some examples need an account that already exists and, for the SSH
# sites, the partner's SSH port. They use john and 8022; remove the # to use
# your own. An argument given to an example still wins over these.
# export ST_EXAMPLE_ACCOUNT="john"
# export ST_SSH_PORT="8022"
