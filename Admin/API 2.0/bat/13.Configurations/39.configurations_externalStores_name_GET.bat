@echo off
REM ==============================================================================
REM Script Name: 39.configurations_externalStores_name_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads an external store, using the
REM `/configurations/externalStores/{externalStoreName}` endpoint.
REM
REM Usage:
REM 39.configurations_externalStores_name_GET.bat [NAME]
REM
REM   NAME  the external store (default example_vault)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The AppRole's secret_id comes back masked.
REM - PowerShell is used to print the summary, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_vault
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/externalStores/%NAME%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read %NAME% ^(HTTP %HTTP_CODE%^):
    TYPE "%RESPONSE_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"
echo.
echo.
echo In short:
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; '  {0}: {1} {2}{3}, secret at {4}, cached {5}s' -f $r.name, $r.method, $r.baseUrl, $r.uri, $r.pathPrefix, $r.cacheTimeout; $l = if ($r.auth.baseUrl) { $r.auth.baseUrl + $r.auth.uri } else { '-' }; '  login: ' + $l"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
