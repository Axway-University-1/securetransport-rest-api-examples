@echo off
REM ==============================================================================
REM Script Name: 32.configurations_clusterManagement_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads whether the server is part of a cluster, using the
REM `/configurations/clusterManagement` endpoint, and lists the cluster's nodes.
REM
REM Usage:
REM 32.configurations_clusterManagement_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - A standalone server answers isCluster false and no nodes.
REM - Adding and removing nodes, bouncing a node, and the cluster operations
REM   (bounce, synchronize) apply to a cluster only; they have no example here.
REM - PowerShell is used to print the summary, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/clusterManagement" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
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
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.isCluster) { '  a {0} cluster of {1} nodes' -f $r.clusterMode, @($r.clusterNodes).Count; foreach ($n in $r.clusterNodes) { '  ' + $(if ($n.serverAddress) { $n.serverAddress } else { $n }) } } else { '  standalone, not a cluster' }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
