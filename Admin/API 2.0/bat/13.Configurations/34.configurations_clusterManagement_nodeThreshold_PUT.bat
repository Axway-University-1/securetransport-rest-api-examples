@echo off
REM ==============================================================================
REM Script Name: 34.configurations_clusterManagement_nodeThreshold_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script replaces the node threshold, using the
REM `/configurations/clusterManagement/nodeThreshold` endpoint with PUT: the
REM number of nodes expected, and an email when fewer are running.
REM
REM Usage:
REM 34.configurations_clusterManagement_nodeThreshold_PUT.bat [NODES]
REM
REM   NODES  the number of nodes expected (default 1)
REM
REM Risk: config
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The email goes through the server's SMTP settings (the SMTP.Group options).
REM - 35.configurations_clusterManagement_nodeThreshold_PATCH.bat turns the email
REM   off again.
REM - Confirmed directly: a success answers 204, with no body.
REM - PowerShell is used to build the body, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET NODES=%~1
IF "%NODES%"=="" SET NODES=1
ECHO %NODES%| FINDSTR /R /X "[1-9][0-9]*" >NUL || (
    echo NODES must be a whole number: %NODES%
    EXIT /B 2
)
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json
SET BODY_FILE=%TEMP%\conf_body_%RANDOM%.json

powershell -NoProfile -Command "[ordered]@{ numberOfNodes=[int]$env:NODES; sendNotification=$true; subject='SecureTransport: fewer nodes than expected'; notification=('Fewer than ' + $env:NODES + ' SecureTransport node(s) are running.') } | ConvertTo-Json -Compress | Set-Content -Encoding ASCII $env:BODY_FILE"
echo Expecting %NODES% node(s), with an email when fewer run...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/clusterManagement/nodeThreshold" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
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
