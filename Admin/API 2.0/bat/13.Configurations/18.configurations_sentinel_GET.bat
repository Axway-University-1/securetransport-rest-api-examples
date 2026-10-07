@echo off
REM ==============================================================================
REM Script Name: 18.configurations_sentinel_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads the Axway Sentinel settings, using the
REM `/configurations/sentinel` endpoint: whether events are reported, where to,
REM and which states.
REM
REM Usage:
REM 18.configurations_sentinel_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - eventStates lists each transfer state: true reports it, false does not,
REM   required always does.
REM - PowerShell is used to print the summary, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/sentinel" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo HTTP %HTTP_CODE%:
    TYPE "%RESPONSE_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"
echo.
echo.
echo In short:
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $h = if ($r.host) { $r.host } else { '-' }; '  enabled: {0}, to {1}:{2}, heartbeat: {3} every {4} {5}' -f ([string]$r.enabled).ToLower(), $h, $r.port, ([string]$r.heartbeatEnabled).ToLower(), $r.heartbeatDelay, $r.heartbeatTimeUnit; $s = @($r.eventStates.PSObject.Properties); '  states reported: {0} of {1}' -f @($s | Where-Object { $_.Value -ne 'false' }).Count, $s.Count"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
