@echo off
REM ==============================================================================
REM Script Name: 41.configurations_externalStores_name_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script changes how long the server caches the secrets it reads from an
REM external store (cacheTimeout), using the
REM `/configurations/externalStores/{externalStoreName}` endpoint with PATCH.
REM
REM Usage:
REM 41.configurations_externalStores_name_PATCH.bat SECONDS [NAME]
REM
REM   SECONDS  the new cacheTimeout; 0 does not cache
REM   NAME  the external store (default example_vault)
REM
REM Risk: config
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Changing a store clears the secrets the server cached from it.
REM - Confirmed directly: a success answers 204, with no body.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET SECONDS_CACHE=%~1
SET NAME=%~2
IF "%NAME%"=="" SET NAME=example_vault
ECHO %SECONDS_CACHE%| FINDSTR /R /X "[0-9][0-9]*" >NUL || (
    echo Usage: 41.configurations_externalStores_name_PATCH.bat SECONDS [NAME]
    EXIT /B 2
)
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json
SET BODY_FILE=%TEMP%\conf_body_%RANDOM%.json

powershell -NoProfile -Command "ConvertTo-Json -Compress -Depth 5 -InputObject @(@{op='replace'; path='/cacheTimeout'; value=[int]$env:SECONDS_CACHE}) | Set-Content -Encoding ASCII $env:BODY_FILE"
echo Caching the secrets of %NAME% for %SECONDS_CACHE% seconds...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/externalStores/%NAME%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"'') DO SET HTTP_CODE=%%C
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
