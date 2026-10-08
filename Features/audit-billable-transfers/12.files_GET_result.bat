@echo off
REM ==============================================================================
REM Script Name: 12.files_GET_result.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Shows what each scenario left behind, using the End User API
REM `GET /files/{folder}` endpoint: the test account's six subscription/sN folders
REM (what was pulled), then partner_to_push_to's two delivered folders (what was
REM pushed). The pushes are asynchronous, so it first waits for delivered-2 to hold
REM both files of scenario 2.6, the last pushes to arrive.
REM
REM Usage:
REM 12.files_GET_result.bat
REM
REM Risk: read
REM
REM Notes:
REM - Run it after 11.transfers_pull_POST.bat.
REM - Needs settings.local.bat with BT_ACCOUNT_PASSWORD. See settings.bat.
REM - Uses PowerShell to read the listing.
REM - Exits 1 when the server refuses a listing. While it waits for delivered-2 to
REM   fill, a refused listing is retried like an empty one, and then reported.
REM - This only shows files. 00.run_all.bat's own analysis step is about the
REM   billable counts, not this listing; this is a sanity check along the way.
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

REM partner_to_push_to: scenario 2.6 pushes its two files to delivered-2 last
SET EU_ACCOUNT=%BT_PUSH_PARTNER%
CALL "%~dp0..\lib\enduser.bat" login
IF ERRORLEVEL 1 EXIT /B 1

SET LISTINGS_REFUSED=
SET WAITED=0
:wait_loop
CALL :count_files "%BT_DELIVERED_2_FOLDER%"
IF %FILE_COUNT% GEQ 2 GOTO :show
IF %WAITED% GEQ %BT_WAIT_SECONDS% GOTO :show
echo %BT_DELIVERED_2_FOLDER% holds %FILE_COUNT% of 2 files yet. Waiting...
ping -n 4 127.0.0.1 >NUL
SET /A WAITED=%WAITED%+3
GOTO :wait_loop

:show
CALL :show_folder "%BT_DELIVERED_1_FOLDER%"
CALL :show_folder "%BT_DELIVERED_2_FOLDER%"
CALL "%~dp0..\lib\enduser.bat" logout

REM The test account: what each scenario pulled in
SET EU_ACCOUNT=%BT_TEST_ACCOUNT%
CALL "%~dp0..\lib\enduser.bat" login
IF ERRORLEVEL 1 EXIT /B 1
FOR %%N IN (1,2,3,4,5,6) DO CALL :show_folder "%BT_SUBSCRIPTION_FOLDER%/s%%N"
CALL "%~dp0..\lib\enduser.bat" logout
IF DEFINED LISTINGS_REFUSED EXIT /B 1
EXIT /B 0

:count_files
CALL "%~dp0..\lib\enduser.bat" call GET "files%~1" ""
SET LIST_RC=%ERRORLEVEL%
SET FILE_COUNT=0
FOR /F %%C IN ('powershell -NoProfile -Command "try { @((Get-Content -Raw $env:EU_BODY_FILE | ConvertFrom-Json).files | Where-Object { $_.isRegularFile }).Count } catch { 0 }"') DO SET FILE_COUNT=%%C
EXIT /B 0

:show_folder
CALL :count_files "%~1"
echo.
echo %EU_ACCOUNT% %~1: %FILE_COUNT% file^(s^)
IF NOT "%LIST_RC%"=="0" echo The listing was refused ^(HTTP %EU_CODE%^).
IF NOT "%LIST_RC%"=="0" SET LISTINGS_REFUSED=1
powershell -NoProfile -Command "try { (Get-Content -Raw $env:EU_BODY_FILE | ConvertFrom-Json).files | Where-Object { $_.isRegularFile } | ForEach-Object { '    ' + $_.fileName + '  (' + $_.size + ' bytes)' } } catch { }"
EXIT /B 0
