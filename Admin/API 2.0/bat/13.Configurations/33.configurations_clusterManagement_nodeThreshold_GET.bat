@echo off
REM ==============================================================================
REM Script Name: 33.configurations_clusterManagement_nodeThreshold_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads the node threshold, using the
REM `/configurations/clusterManagement/nodeThreshold` endpoint: how many nodes
REM the server expects, and whether to send an email when fewer are running.
REM
REM Usage:
REM 33.configurations_clusterManagement_nodeThreshold_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - PowerShell is used to print the summary, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/clusterManagement/nodeThreshold" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
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
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $t = '  expects {0} node(s); notification: {1}' -f $r.numberOfNodes, ([string]$r.sendNotification).ToLower(); if ($r.sendNotification) { $t += ', subject ' + $r.subject }; $t"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
