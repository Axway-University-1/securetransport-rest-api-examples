@echo off
REM ==============================================================================
REM Script Name: 03.events_operations_POST_delete.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes events using the `/events/operations` endpoint with
REM operation=delete, and prints what became of each id.
REM
REM Usage:
REM 03.events_operations_POST_delete.bat EVENT_ID [EVENT_ID...]
REM
REM   EVENT_ID  the events to delete: required, as 01.events_GET.bat shows them
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Delete only events you know are stuck: it ends the server's tracking of the
REM   event. The id is required, so that running the script bare deletes nothing.
REM - Confirmed directly: the answer is 200 with a status for each id: "deleted", or
REM   "not found". A "not found" does not make this script fail; read the lines.
REM - Confirmed directly: no ids, or an empty list, answers 400 "Id is not specified."
REM - Confirmed directly: any other operation (operation=purge) answers 200 with {} and
REM   does nothing, so a misspelled operation looks like a success. This script only
REM   sends operation=delete.
REM - PowerShell is used to build the body and print the answer, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/events
IF "%~1"=="" (
    echo Usage: 03.events_operations_POST_delete.bat EVENT_ID [EVENT_ID...]
    EXIT /B 2
)
SET IDS=%*
SET BODY_FILE=%TEMP%\events_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\events_%RANDOM%.json

SET COUNT=0
FOR %%A IN (%*) DO SET /A COUNT+=1
powershell -NoProfile -Command "$ids = @($env:IDS -split '\s+' | Where-Object { $_ }); [IO.File]::WriteAllText($env:BODY_FILE, (ConvertTo-Json -Compress -InputObject ([ordered]@{ ids = $ids })))"

echo Deleting %COUNT% event^(s^)...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%/operations?operation=delete" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="200" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($x in $r.events) { '  {0}: {1}' -f $x.id, $x.status }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
