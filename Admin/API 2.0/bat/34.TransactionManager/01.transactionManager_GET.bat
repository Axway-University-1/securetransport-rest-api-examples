@echo off
REM ==============================================================================
REM Script Name: 01.transactionManager_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads the status of the Transaction Manager (TM), the component that runs the server's
REM file transfers and routing events, using the `/transactionManager` endpoint.
REM It demonstrates:
REM - Reading the status text the server gives
REM - Telling a running Transaction Manager from one that is stopped or stopping, by the exit code
REM
REM Usage:
REM 01.transactionManager_GET.bat
REM
REM   Exit code: 0 when the Transaction Manager is running, 1 when the server refuses or it is not running.
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - PowerShell is used to read the status from the answer, in place of jq.
REM - The answer is one object with one field, `status`, a free text: the reference says only "running, stopped or shutdown is in progress".
REM - Confirmed directly: a running Transaction Manager answers 200 `{"status": "Running."}` (with a full stop). The script
REM   decides on the word "Running", the way `python/python3/stGraceful.py` does, and not on the whole text. What the stopped or the
REM   stopping answers read was NOT SEEN: stopping the Transaction Manager cannot be undone through the API (see 02), so the lab
REM   was never stopped. The reference lists them without giving the words.
REM - Confirmed directly: `fields=` is ignored (even an unknown one); HEAD is 200; PUT, PATCH and DELETE are 405 "HTTP 405 Method Not
REM   Allowed"; `Accept: application/xml` and `text/csv` are 406; `/transactionManager/x` is 404.
REM - Used before the stop in 02, to see that there is something to stop.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/transactionManager
SET RESPONSE_FILE=%TEMP%\tm_%RANDOM%.json

echo Reading the status of the Transaction Manager...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" GOTO refused
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $s = if ($r.status) { $r.status } else { 'unknown' }; 'Transaction Manager status: ' + $s; if ($s -like '*Running*') { exit 0 } else { exit 1 }"
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%
:refused
echo HTTP %HTTP_CODE%
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 1
