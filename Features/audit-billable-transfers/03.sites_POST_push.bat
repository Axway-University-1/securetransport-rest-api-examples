@echo off
REM ==============================================================================
REM Script Name: 03.sites_POST_push.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Creates the two push sites these examples use as "the remote partners", using
REM the `/sites` endpoint. Both are SSH sites of the test account, logging in to
REM this server's own SSH listener as partner_to_push_to, each uploading into its
REM own delivered folder there (<account>/delivered-1 and <account>/delivered-2).
REM
REM Usage:
REM 03.sites_POST_push.bat
REM
REM Risk: write
REM
REM Notes:
REM - Run 01.accounts_POST.bat first.
REM - Needs settings.local.bat with BT_ACCOUNT_PASSWORD. See settings.bat.
REM - Uses PowerShell to build the JSON body.
REM - Stops at the first site the server refuses, and exits 1.
REM - Only scenario 2.6 (archive pushed to two partners) uses the second site.
REM   Every other scenario that pushes uses the first one.
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

CALL :create_push_site "%BT_PUSH_SITE_1%" "%BT_DELIVERED_1_FOLDER%"
IF ERRORLEVEL 1 EXIT /B 1
CALL :create_push_site "%BT_PUSH_SITE_2%" "%BT_DELIVERED_2_FOLDER%"
IF ERRORLEVEL 1 EXIT /B 1
EXIT /B 0

:create_push_site
SET SITE_NAME=%~1
SET SITE_FOLDER=%~2
SET BODY_FILE=%TEMP%\bt_body_%RANDOM%.json
powershell -NoProfile -Command "@{ type='ssh'; protocol='ssh'; name=$env:SITE_NAME; host=$env:BT_SSH_HOST; port=$env:BT_SSH_PORT; userName=$env:BT_PUSH_PARTNER; usePassword=$true; password=$env:BT_ACCOUNT_PASSWORD; account=$env:BT_TEST_ACCOUNT; transferType='partner'; uploadFolder=$env:SITE_FOLDER } | ConvertTo-Json -Compress" > "%BODY_FILE%"

echo Creating the push site %SITE_NAME%, delivering to %SITE_FOLDER%...
CALL "%~dp0..\lib\post_admin.bat" sites "%BODY_FILE%"
SET POST_RESULT=%ERRORLEVEL%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B %POST_RESULT%
