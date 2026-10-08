@echo off
REM ==============================================================================
REM Script Name: 03.sites_POST_push.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Creates the transfer site the pulled files are pushed to, using the `/sites`
REM endpoint. It points at this server's own SSH listener, and its upload folder
REM is outside the subscription folder.
REM
REM Usage:
REM 03.sites_POST_push.bat
REM
REM Risk: write
REM
REM Notes:
REM - Run 01.accounts_POST.bat first.
REM - Needs settings.local.bat with AR_ACCOUNT_PASSWORD. See settings.bat.
REM - Uses PowerShell to build the JSON body.
REM - doAsOut renames each file as it is sent, to ${stenv.target}_PUSHED, so the
REM   outbound rows in File Tracking can be told from the inbound ones.
REM - Exits 1 when the server refuses the site.
REM - The upload folder must not be the subscription folder, or the pushed files
REM   would trigger the route again.
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

powershell -NoProfile -Command "@{ type='ssh'; protocol='ssh'; name=$env:AR_PUSH_SITE; host=$env:AR_SSH_HOST; port=$env:AR_SSH_PORT; userName=$env:AR_TEST_ACCOUNT; usePassword=$true; password=$env:AR_ACCOUNT_PASSWORD; account=$env:AR_TEST_ACCOUNT; transferType='partner'; uploadFolder=$env:AR_DELIVERED_FOLDER; postTransmissionActions=@{ doAsOut=$env:AR_PUSH_RENAME } } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"

echo Creating the push site %AR_PUSH_SITE%...
CALL "%~dp0..\lib\post_admin.bat" sites "%BODY_FILE%"
SET POST_RESULT=%ERRORLEVEL%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B %POST_RESULT%
