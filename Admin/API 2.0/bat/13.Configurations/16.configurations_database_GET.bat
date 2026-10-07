@echo off
REM ==============================================================================
REM Script Name: 16.configurations_database_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads the database configuration, using the
REM `/configurations/database` endpoint: the database type, host, port, name and
REM user the server connects with.
REM
REM Usage:
REM 16.configurations_database_GET.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The password never comes back.
REM - PUT /configurations/database repoints the server at another database; it
REM   has no example here, as a wrong value stops the server. Use the Admin UI's
REM   database settings for that, after a test with
REM   17.configurations_database_operations_POST_test.bat.
REM - GET and PUT /configurations/database/{componentType}, for the server log and
REM   the transfer log databases, apply to Oracle only.
REM - PowerShell is used to print the summary, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/database" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
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
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $k = if ($r.isInternalDB) { '(embedded)' } else { '(external)' }; '  {0} {1} at {2}:{3}, database {4}, user {5}' -f $r.databaseType, $k, $r.host, $r.port, $r.databaseName, $r.username; '  running: {0}, secure connection: {1}' -f ([string]$r.databaseRunning).ToLower(), ([string]$r.secureConnectionEnabled).ToLower()"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
