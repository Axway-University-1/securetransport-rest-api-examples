@echo off
REM ==============================================================================
REM Script Name: 02.sites_POST_pull.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Creates the six pull sites these examples use, using the `/sites` endpoint.
REM Each is an SSH site of the test account, logging in to this server's own SSH
REM listener as partner_to_pull_from and reading from the test account's drop
REM folder there (<account>/outbound-drop), each with a download pattern matching only
REM the file (or files) for its own scenario. A file is copied, not moved, by a
REM pull (storeAndForwardMode PRESERVE is not set here, which is the server's
REM default), so the six sites can share one drop folder without one site's pull
REM taking a file another site also needs.
REM
REM Usage:
REM 02.sites_POST_pull.bat
REM
REM Notes:
REM - Run 01.accounts_POST.bat first.
REM - Needs settings.local.bat with BT_ACCOUNT_PASSWORD. See settings.bat.
REM - Uses PowerShell to build the JSON body.
REM - The SSH port is BT_SSH_PORT, 8022 by default. It is not the REST API port.
REM - Site N is named <account>PullSite<N> and its pattern matches the file(s) for
REM   scenario <N> only: see settings.bat for the mapping from scenario to file.
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

REM Scenarios 2.1 and 2.2 can run several files (BT_INBOUND_ONLY_COUNT,
REM BT_IN_AND_OUT_COUNT): the pattern matches the plain name and the numbered ones
CALL :create_pull_site 1 "%BT_FILE_ONLY_INBOUND:.txt=%*.txt"
CALL :create_pull_site 2 "%BT_FILE_ONE_OUTBOUND:.txt=%*.txt"
CALL :create_pull_site 3 "%BT_FILE_TWO_OUTBOUNDS%"
CALL :create_pull_site 4 "file_*_for_compress.txt"
CALL :create_pull_site 5 "%BT_FILE_ARCHIVE_NAME%"
CALL :create_pull_site 6 "%BT_FILE_ARCHIVE2P_NAME%"
EXIT /B 0

:create_pull_site
SET SITE_N=%1
SET SITE_PATTERN=%~2
SET SITE_NAME=%BT_PULL_SITE_PREFIX%%SITE_N%
SET BODY_FILE=%TEMP%\bt_body_%RANDOM%.json
powershell -NoProfile -Command "@{ type='ssh'; protocol='ssh'; name=$env:SITE_NAME; host=$env:BT_SSH_HOST; port=$env:BT_SSH_PORT; userName=$env:BT_PULL_PARTNER; usePassword=$true; password=$env:BT_ACCOUNT_PASSWORD; account=$env:BT_TEST_ACCOUNT; transferType='partner'; downloadFolder=$env:BT_DROP_FOLDER; downloadPatternType='glob'; downloadPattern=$env:SITE_PATTERN } | ConvertTo-Json -Compress" > "%BODY_FILE%"

echo Creating the pull site %SITE_NAME%, matching %SITE_PATTERN%...
CALL "%~dp0..\lib\post_admin.bat" sites "%BODY_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B 0
