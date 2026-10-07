@echo off
REM ==============================================================================
REM Script Name: 02.events_id_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads one event using the `/events/{id}` endpoint: its status, the file
REM it is for, the subscription and account it belongs to, and its data.
REM
REM Usage:
REM 02.events_id_GET.bat [EVENT_ID]
REM
REM   EVENT_ID  the event (default: the first one 01.events_GET.bat lists)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - An event that is not there, or not visible to this administrator, answers 404
REM   "Cannot find event with id ... or it is not accessible".
REM - The id goes into the path URL-encoded once, with jq's @uri.
REM - data and sessionData hold "key": "value" pairs the processing keeps.
REM - PowerShell is used to look the id up, URL-encode it and print the summary, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/events
SET EVENT_ID=%~1
SET RESPONSE_FILE=%TEMP%\events_%RANDOM%.json
IF NOT "%EVENT_ID%"=="" GOTO have_id
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?limit=1&fields=id" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.result) { $r.result[0].id }"') DO SET EVENT_ID=%%I
IF "%EVENT_ID%"=="" (
    echo There are no events to read.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
:have_id
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:EVENT_ID)"') DO SET ENCODED=%%E

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the event ^(HTTP %HTTP_CODE%^):
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"
echo.
echo.
echo In short:
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $t = if ($r.fullTarget) { $r.fullTarget } else { '-' }; $a = if ($r.accountName) { $r.accountName } else { '-' }; $s = if ($r.subscriptionId) { $r.subscriptionId } else { '-' }; $n = if ($r.clusterNode) { $r.clusterNode } else { '-' }; '  {0} {1} event for {2}' -f $r.status, $r.agentType, $t; '  account {0}, subscription {1}' -f $a, $s; '  retries {0}, recovered {1}, node {2}' -f $r.retryCount, ([string]$r.recovered).ToLower(), $n"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
