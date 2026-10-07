@echo off
REM ==============================================================================
REM Script Name: 11.transfers_pull_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Runs the pull by hand, using the `/transfers/operations?operation=pull` endpoint,
REM instead of waiting for a schedule. Files land in the subscription folder, and
REM when the pull completes the trigger file starts one route execution.
REM
REM Usage:
REM 11.transfers_pull_POST.bat
REM
REM Risk: write
REM
REM Notes:
REM - Uses PowerShell to build the JSON body.
REM - Run steps 1 to 10 first.
REM - A successful call answers 202: the pull is asynchronous. The response links
REM   to /logs/transfers?operationIndex=... to follow it.
REM - Afterwards look in the delivered folder, and in the transfer log: there should
REM   be one route execution for all the pulled files.
REM ==============================================================================

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0
CALL "%~dp0settings.bat"

SET BODY_FILE=%TEMP%\ar_body_%RANDOM%.json
powershell -NoProfile -Command "@{ accountName=$env:AR_TEST_ACCOUNT; site=$env:AR_PULL_SITE; destinationDirectory=$env:AR_SUBSCRIPTION_FOLDER; awaitResult=$false } | ConvertTo-Json -Compress" > "%BODY_FILE%"

echo Pulling from %AR_PULL_SITE% into %AR_SUBSCRIPTION_FOLDER%...
CALL "%~dp0..\lib\post_admin.bat" "transfers/operations?operation=pull" "%BODY_FILE%" 
SET POST_RESULT=%ERRORLEVEL%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B %POST_RESULT%
