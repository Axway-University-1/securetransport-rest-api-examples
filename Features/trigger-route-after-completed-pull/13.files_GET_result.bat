@echo off
REM ==============================================================================
REM Script Name: 13.files_GET_result.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Shows what the pull and the push left behind, using the End User API
REM `GET /files/{folder}` endpoint. It lists the files in each of the folders in
REM AR_CHECK_FOLDERS, as the test account sees them. The last folder, delivered, is
REM where the push puts the files, so it waits for that one to fill up.
REM
REM Usage:
REM 13.files_GET_result.bat
REM
REM Risk: read
REM
REM Notes:
REM - Run it after 12.files_PUT_triggerfile.bat. The pull and the route run
REM   asynchronously, so the push can take a few seconds to arrive. The script
REM   waits up to AR_WAIT_SECONDS for the files in the last folder.
REM - Needs settings.local.bat with AR_ACCOUNT_PASSWORD. See settings.bat.
REM - Uses PowerShell to read the listing.
REM - Exits 1 if nothing arrived in the last folder, or if the server refused a listing.
REM - This only shows files. The transfer log shows the route runs themselves.
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

CALL "%~dp0..\lib\enduser.bat" login
IF ERRORLEVEL 1 EXIT /B 1

FOR %%F IN (%AR_CHECK_FOLDERS%) DO SET LAST_FOLDER=%%F

REM The push is asynchronous: give the last folder time to fill up
SET WAITED=0
:wait_loop
CALL :count_files %LAST_FOLDER%
IF %FILE_COUNT% GTR 0 GOTO :show
IF %WAITED% GEQ %AR_WAIT_SECONDS% GOTO :show
echo Nothing in %LAST_FOLDER% yet. Waiting...
ping -n 4 127.0.0.1 >NUL
SET /A WAITED=%WAITED%+3
GOTO :wait_loop

:show
SET LAST_COUNT=0
SET LISTINGS_REFUSED=
FOR %%F IN (%AR_CHECK_FOLDERS%) DO CALL :show_folder %%F

CALL "%~dp0..\lib\enduser.bat" logout
IF DEFINED LISTINGS_REFUSED EXIT /B 1
IF %LAST_COUNT% GTR 0 EXIT /B 0
EXIT /B 1

:count_files
CALL "%~dp0..\lib\enduser.bat" call GET "files/%1" ""
SET LIST_RC=%ERRORLEVEL%
SET FILE_COUNT=0
FOR /F %%N IN ('powershell -NoProfile -Command "try { @((Get-Content -Raw $env:EU_BODY_FILE | ConvertFrom-Json).files | Where-Object { $_.isRegularFile }).Count } catch { 0 }"') DO SET FILE_COUNT=%%N
EXIT /B 0

:show_folder
CALL :count_files %1
echo.
echo %1: %FILE_COUNT% file^(s^)
IF NOT "%LIST_RC%"=="0" echo The listing of %1 was refused ^(HTTP %EU_CODE%^).
IF NOT "%LIST_RC%"=="0" SET LISTINGS_REFUSED=1
powershell -NoProfile -Command "try { (Get-Content -Raw $env:EU_BODY_FILE | ConvertFrom-Json).files | Where-Object { $_.isRegularFile } | ForEach-Object { '    ' + $_.fileName + '  (' + $_.size + ' bytes)' } } catch { }"
IF "%1"=="%LAST_FOLDER%" SET LAST_COUNT=%FILE_COUNT%
EXIT /B 0
