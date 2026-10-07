@echo off
REM ==============================================================================
REM Script Name: 36.configurations_replication_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads the database replication status, using the
REM `/configurations/replication` endpoint: whether the database is replicated
REM between sites, and the state of each subscription.
REM
REM Usage:
REM 36.configurations_replication_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - A server without replication answers enabled false and no subscriptions.
REM - The replication operations (enable and disable replication or a
REM   subscription, a manual restore) and deleting a subscription need replicated
REM   servers; they have no example here.
REM - PowerShell is used to print the summary, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/replication" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
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
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; '  replication: ' + ([string]$r.enabled).ToLower(); foreach ($s in @($r.subscriptions)) { if ($s) { $n = if ($s.name) { $s.name } else { $s.subscriptionName }; $st = if ($s.status) { $s.status } elseif ($s.state) { $s.state } else { '-' }; '  {0}: {1}' -f $n, $st } }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
