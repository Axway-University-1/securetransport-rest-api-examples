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
REM - PowerShell is used to URL-encode the name and print the summary, in place of jq.
REM - The name is URL-encoded into the path (a name with a space works); one with a / is refused with exit 2 (nothing is sent),
REM   as the web server answers 400 to an encoded slash.
REM - Confirmed directly: an unknown store is 404 "Cannot find external store with name 'X' or external store configuration is not accessible".
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET "NAME=%~1"
IF "%NAME%"=="" SET NAME=example_vault
IF NOT "%NAME:/=%"=="%NAME%" (
    echo NAME must not hold a /: such a name cannot be addressed in a path.
    EXIT /B 2
)
SET ENCODED=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET "ENCODED=%%E"
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/externalStores/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
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
EXIT /B 0
