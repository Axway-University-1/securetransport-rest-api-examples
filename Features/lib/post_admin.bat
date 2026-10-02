@echo off
REM ==============================================================================
REM Script Name: post_admin.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Shared across Features/. POSTs a JSON file to the Admin API and
REM prints the response and the HTTP code. On success, the id of the new object
REM is read from the Location header and saved under STATE_KEY.
REM
REM Usage:
REM CALL post_admin.bat PATH BODY_FILE [STATE_KEY]
REM
REM Notes:
REM - Ids are kept in state.local.bat, next to this file, which git ignores. A
REM   later example reads the ids an earlier one saved, and 99.cleanup_DELETE.bat
REM   uses them to delete what was created.
REM - Sets ERRORLEVEL to 1 when the server did not answer with a 2xx code.
REM ==============================================================================

SET PA_HEADERS=%TEMP%\ar_headers_%RANDOM%.txt
SET PA_CODE=
SET PA_LOCATION=
SET PA_ID=

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/%~1" ^
  -H "accept: */*" -H "Referer: THIS_IS_A_RANDOM_TEXT" -H "Content-Type: application/json" ^
  -D "%PA_HEADERS%" -d "@%~2"

FOR /F "tokens=2" %%C IN ('findstr /B /I "HTTP/" "%PA_HEADERS%"') DO SET PA_CODE=%%C
FOR /F "tokens=2" %%L IN ('findstr /B /I "location:" "%PA_HEADERS%"') DO SET PA_LOCATION=%%L
IF EXIST "%PA_HEADERS%" DEL "%PA_HEADERS%"

echo.
echo HTTP %PA_CODE%

IF NOT "%PA_CODE:~0,1%"=="2" EXIT /B 1

IF DEFINED PA_LOCATION FOR %%P IN ("%PA_LOCATION%") DO SET PA_ID=%%~nxP
IF NOT "%~3"=="" IF DEFINED PA_ID (
    >> "%FEATURE_DIR%state.local.bat" echo SET %~3=%PA_ID%
    echo Saved %~3 = %PA_ID%
)
EXIT /B 0
