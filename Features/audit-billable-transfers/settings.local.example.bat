@echo off
REM Copy to settings.local.bat and edit. git ignores settings.local.bat.
REM
REM Required: the password the test account will be created with.
SET BT_ACCOUNT_PASSWORD=<choose-a-password>

REM Optional. The defaults are in settings.bat.
REM SET BT_SSH_HOST=<host of this server's SSH listener>
REM SET BT_SSH_PORT=8022
REM SET BT_ENDUSER_PORT=8443
