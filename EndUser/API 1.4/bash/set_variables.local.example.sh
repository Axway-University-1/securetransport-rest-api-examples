#!/bin/bash
# ==============================================================================
# Copy this file to set_variables.local.sh and fill in your own values.
#
#   cp set_variables.local.example.sh set_variables.local.sh
#
# This is the one settings file of the End User API 1.4 examples in this folder.
# Every script reads set_variables.local.sh, and stops with a message when it is
# not there. It is excluded from git, so your credentials are never committed.
#
# The settings are those of an END USER, not an administrator. The mailbox is the
# mailbox of this user. To act as another user (the recipient of a message), keep
# his settings in another file and point ST_ENDUSER_LOCAL_VARIABLES at it:
#
#   ST_ENDUSER_LOCAL_VARIABLES=/path/to/recipient.sh ./04.mailbox_folders_name_GET.sh
# ==============================================================================

# The SecureTransport host, without the protocol or port
export ST_SERVER="st.example.com"

# The user level port. 8443 for a non root install, 443 for a root install.
export ST_PORT="8443"

# An end user and his password, in plain text
export ST_USER="john"
export ST_PASSWORD="change_me"
