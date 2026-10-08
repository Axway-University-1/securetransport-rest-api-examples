#!/bin/bash
# Copy to settings.local.sh and edit. git ignores settings.local.sh.
#
# Required: the password the three accounts (the test account and the two
# partners) will be created with. Keep the single
# quotes: in double quotes the shell would expand characters such as $ and !.
export BT_ACCOUNT_PASSWORD='<choose-a-password>'

# Optional. The defaults are in settings.sh.
# export BT_SSH_HOST="<host of this server's SSH listener>"
# export BT_SSH_PORT="8022"
# export BT_ENDUSER_PORT="8443"
# export BT_PULL_PARTNER="partner_to_pull_from"
# export BT_PUSH_PARTNER="partner_to_push_to"
# export BT_HOME_ROOT="/home"
# A name chosen here is never changed by 00.run_all.sh (see "A stale home folder" there):
# export BT_TEST_ACCOUNT="<another account name>"
