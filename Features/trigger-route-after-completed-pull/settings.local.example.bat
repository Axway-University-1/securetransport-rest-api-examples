@echo off
REM Copy to settings.local.bat and edit. git ignores settings.local.bat.
REM
REM Required: the password the test account will be created with.
SET AR_ACCOUNT_PASSWORD=<choose-a-password>

REM Optional. The defaults are in settings.bat.
REM SET AR_SSH_HOST=<host of this server's SSH listener>
REM SET AR_SSH_PORT=8022
REM SET AR_ENDUSER_PORT=8443
REM SET AR_HOME_ROOT=/home
REM A name chosen here is never changed by 00.run_all.bat (see "A stale home folder" there):
REM SET AR_TEST_ACCOUNT=<another account name>
