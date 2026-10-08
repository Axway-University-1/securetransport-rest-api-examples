@echo off
REM ==============================================================================
REM Script Name: 01.accounts_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Creates the three accounts these examples use, using the `/accounts` endpoint:
REM   - the test account, which owns every site, subscription and route
REM   - partner_to_pull_from, which holds the sample files the test account pulls
REM   - partner_to_push_to, which receives what the test account pushes
REM Each is a user account with its own password, so the test account's sites can
REM log in to this server's SSH listener as a partner, and each account can log in
REM to the End User API.
REM
REM Usage:
REM 01.accounts_POST.bat
REM
REM Risk: write
REM
REM Notes:
REM - Needs settings.local.bat with BT_ACCOUNT_PASSWORD. See settings.bat.
REM - Uses PowerShell to build the JSON body.
REM - transfersWebServiceAllowed is on. Without it the account cannot log in to the
REM   End User API, and that login fails with a 401.
REM - Exits 1 as soon as the server refuses an account.
REM - The partners are shared by every test account. One that already exists, from
REM   another test account's run, is reused and not created again.
REM   99.cleanup_DELETE removes a partner only when no other test account's site
REM   still logs in as it.
REM ==============================================================================

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0
CALL "%~dp0settings.bat"

IF "%BT_ACCOUNT_PASSWORD%"=="" (
    echo BT_ACCOUNT_PASSWORD is not set. Copy settings.local.example.bat to settings.local.bat and choose one.
    EXIT /B 1
)

CALL :create_account "%BT_TEST_ACCOUNT%" "%BT_HOME_FOLDER%"
IF ERRORLEVEL 1 EXIT /B 1
CALL :create_partner "%BT_PULL_PARTNER%" "%BT_PULL_PARTNER_HOME%"
IF ERRORLEVEL 1 EXIT /B 1
CALL :create_partner "%BT_PUSH_PARTNER%" "%BT_PUSH_PARTNER_HOME%"
IF ERRORLEVEL 1 EXIT /B 1
EXIT /B 0

:create_account
SET ACCOUNT_NAME=%~1
SET ACCOUNT_HOME=%~2
SET BODY_FILE=%TEMP%\bt_body_%RANDOM%.json
powershell -NoProfile -Command "@{ name=$env:ACCOUNT_NAME; type='user'; homeFolder=$env:ACCOUNT_HOME; uid='41733'; gid='41733'; transfersWebServiceAllowed=$true; user=@{ name=$env:ACCOUNT_NAME; passwordCredentials=@{ password=$env:BT_ACCOUNT_PASSWORD } } } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"

echo Creating the account %ACCOUNT_NAME%...
CALL "%~dp0..\lib\post_admin.bat" accounts "%BODY_FILE%"
SET POST_RESULT=%ERRORLEVEL%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B %POST_RESULT%

REM create_partner NAME HOME: creates a partner, or reuses it when it is there
:create_partner
CALL "%~dp0..\lib\admin_calls.bat" exists "accounts/%~1"
IF NOT ERRORLEVEL 1 (
    echo The account %~1 is already there, from another test account's run. Reused.
    EXIT /B 0
)
CALL :create_account "%~1" "%~2"
EXIT /B %ERRORLEVEL%
