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
#
# The base URL, https://ST_SERVER:ST_PORT/api/v2.0, is built from the host and the
# port by each script. To point at something else (a proxy, a different path),
# add:   export ST_URL="https://your-host:8443/api/v2.0"
# ==============================================================================

# The SecureTransport host, without the protocol or port
export ST_SERVER="st.example.com"

# The user level port. 8443 for a non root install, 443 for a root install.
export ST_PORT="8443"

# An end user account and its password, in plain text
export ST_USER="john"
export ST_PASSWORD="change_me"
