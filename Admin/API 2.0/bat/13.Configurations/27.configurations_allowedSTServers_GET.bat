@echo off
REM ==============================================================================
REM Script Name: 27.configurations_allowedSTServers_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the SecureTransport servers allowed to connect, using the
REM `/configurations/allowedSTServers` endpoint.
REM
REM Usage:
REM 27.configurations_allowedSTServers_GET.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: a standalone server answers 404 here; the list belongs
REM   to a deployment where servers connect to each other. PUT and PATCH replace
REM   and change it there.
REM - PowerShell is used to print the servers, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/allowedSTServers" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo No list of allowed servers here ^(HTTP %HTTP_CODE%^).
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"
echo.
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
