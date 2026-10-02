@echo off
REM ==============================================================================
REM Script Name: 11.transfers_pull_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Runs all six pulls by hand, using the `/transfers/operations?operation=pull`
REM endpoint, instead of waiting for a schedule. Each pull uses its own site, so it
REM only ever fetches the file(s) for its own scenario, landing in that
REM scenario's own subscription folder.
REM
REM Usage:
REM 11.transfers_pull_POST.bat
REM
REM Notes:
REM - Run steps 01 to 10 first.
REM - Uses PowerShell to build the JSON bodies.
REM - Each call answers 202 on success: the pull is asynchronous. 00.run_all.bat
REM   pauses afterwards to give the pulls, and the routes they trigger, time to run.
REM ==============================================================================

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0
CALL "%~dp0settings.bat"

CALL :run_pull 1
CALL :run_pull 2
CALL :run_pull 3
CALL :run_pull 4
CALL :run_pull 5
CALL :run_pull 6
EXIT /B 0

:run_pull
SET SCENARIO_N=%1
SET SITE_NAME=%BT_PULL_SITE_PREFIX%%SCENARIO_N%
SET SUB_FOLDER=%BT_SUBSCRIPTION_FOLDER%/s%SCENARIO_N%
SET BODY_FILE=%TEMP%\bt_body_%RANDOM%.json
powershell -NoProfile -Command "@{ accountName=$env:BT_TEST_ACCOUNT; site=$env:SITE_NAME; destinationDirectory=$env:SUB_FOLDER; awaitResult=$false } | ConvertTo-Json -Compress" > "%BODY_FILE%"

echo Pulling from %SITE_NAME% into %SUB_FOLDER%...
CALL "%~dp0..\lib\post_admin.bat" "transfers/operations?operation=pull" "%BODY_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B 0
