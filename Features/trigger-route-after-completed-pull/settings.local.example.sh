#!/bin/bash
# Copy to settings.local.sh and edit. git ignores settings.local.sh.
#
# Required: the password the test account will be created with. Keep the single
# quotes: in double quotes the shell would expand characters such as $ and !.
export AR_ACCOUNT_PASSWORD='<choose-a-password>'

# Optional. The defaults are in settings.sh.
# export AR_SSH_HOST="<host of this server's SSH listener>"
# export AR_SSH_PORT="8022"
# export AR_ENDUSER_PORT="8443"
# export AR_HOME_ROOT="/home"
# A name chosen here is never changed by 00.run_all.sh (see "A stale home folder" there):
# export AR_TEST_ACCOUNT="<another account name>"
