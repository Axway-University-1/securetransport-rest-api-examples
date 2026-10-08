@echo off
REM ==============================================================================
REM Script Name: 35.configurations_clusterManagement_nodeThreshold_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script turns the node threshold email on or off, using the
REM `/configurations/clusterManagement/nodeThreshold` endpoint with PATCH.
REM
REM Usage:
REM 35.configurations_clusterManagement_nodeThreshold_PATCH.bat [true|false]
REM
REM   whether to send the email (default false)
REM
REM Risk: config
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: a success answers 204, with no body.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET SEND=%~1
IF "%SEND%"=="" SET SEND=false
IF NOT "%SEND%"=="true" IF NOT "%SEND%"=="false" (
    echo The value is true or false, not %SEND%.
    EXIT /B 2
)
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json
SET BODY_FILE=%TEMP%\conf_body_%RANDOM%.json

powershell -NoProfile -Command "ConvertTo-Json -Compress -Depth 5 -InputObject @(@{op='replace'; path='/sendNotification'; value=($env:SEND -eq 'true')}) | Set-Content -Encoding ASCII $env:BODY_FILE"
echo sendNotification: %SEND%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/clusterManagement/nodeThreshold" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    TYPE "%RESPONSE_FILE%"
    echo.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
