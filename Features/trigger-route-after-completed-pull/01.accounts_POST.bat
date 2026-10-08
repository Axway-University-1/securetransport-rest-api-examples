@echo off
REM ==============================================================================
REM Script Name: 01.accounts_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Creates the test account that owns the pull site, the subscription and the push
REM site, using the `/accounts` endpoint. It is a user account with its own
REM password, so the two sites can log in to this server's SSH listener as it.
REM
REM Usage:
REM 01.accounts_POST.bat
REM
REM Risk: write
REM
REM Notes:
REM - Needs settings.local.bat with AR_ACCOUNT_PASSWORD. See settings.bat.
REM - Uses PowerShell to build the JSON body.
REM - A password containing % or ! may not survive a batch file. Avoid them.
REM - Exits 1 when the server refuses the account (a 409 when it is already there).
REM - The account is AR_TEST_ACCOUNT. 00.run_all.bat and 99.cleanup_DELETE.bat take
REM   another name on their command line (AR_RUN_ACCOUNT, see settings.bat).
REM - transfersWebServiceAllowed is on. Without it the account cannot log in to the
REM   End User API, which steps 4 and 5 use, and the login fails with a 401.
REM - The account is created with a home folder of AR_HOME_FOLDER. Create the
REM   subfolders outbound-drop and delivered in it, and put some files in
REM   outbound-drop, before running the pull.
REM - 99.cleanup_DELETE.bat removes the account again.
REM ==============================================================================

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0
CALL "%~dp0settings.bat"

IF "%AR_ACCOUNT_PASSWORD%"=="" (
    echo AR_ACCOUNT_PASSWORD is not set. Copy settings.local.example.bat to settings.local.bat and choose one.
    EXIT /B 1
)

SET BODY_FILE=%TEMP%\ar_body_%RANDOM%.json

powershell -NoProfile -Command "@{ name=$env:AR_TEST_ACCOUNT; type='user'; homeFolder=$env:AR_HOME_FOLDER; uid='41733'; gid='41733'; transfersWebServiceAllowed=$true; user=@{ name=$env:AR_TEST_ACCOUNT; passwordCredentials=@{ password=$env:AR_ACCOUNT_PASSWORD } } } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"

echo Creating the account %AR_TEST_ACCOUNT%...
CALL "%~dp0..\lib\post_admin.bat" accounts "%BODY_FILE%"
SET POST_RESULT=%ERRORLEVEL%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B %POST_RESULT%
