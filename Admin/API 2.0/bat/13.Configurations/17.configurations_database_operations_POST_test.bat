@echo off
REM ==============================================================================
REM Script Name: 17.configurations_database_operations_POST_test.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script tests a database connection, using the
REM `/configurations/database/operations` endpoint with operation=test: the
REM server connects with the settings given and reports whether it could. The
REM settings in use do not change.
REM
REM Usage:
REM 17.configurations_database_operations_POST_test.bat
REM
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It tests the database the server uses now: the host, port and name come
REM   from 16.configurations_database_GET.bat's call; the user too, unless DB_USER
REM   is set. DB_PASSWORD is read from the environment, so set it first:
REM     SET DB_PASSWORD=the database password
REM - The body is a multipart form. host, port, databaseName, username and
REM   password are required.
REM - Confirmed directly: a wrong password answers 400 "Database Configuration
REM   test failed: FATAL: password authentication failed for user ...".
REM - The other operations - restart, createPartitions, changePassword,
REM   changePort, and the database certificates - change the server and have no
REM   example here.
REM - PowerShell is used to read the settings, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
IF "%DB_PASSWORD%"=="" (
    echo Set DB_PASSWORD to the database password first.
    EXIT /B 2
)
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json
SET BODY_FILE=

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/database" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F "tokens=1-5" %%A IN ('powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; '{0} {1} {2} {3} {4}' -f $r.host, $r.port, $r.databaseName, $r.databaseType, $r.username"') DO (
    SET DB_HOST=%%A
    SET DB_PORT=%%B
    SET DB_NAME=%%C
    SET DB_TYPE=%%D
    IF "%DB_USER%"=="" SET DB_USER=%%E
)
IF "%DB_HOST%"=="" (
    echo Could not read the database settings.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)

echo Testing %DB_TYPE% at %DB_HOST%:%DB_PORT%, database %DB_NAME%, user %DB_USER%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%/database/operations?operation=test" -H "accept: application/json" -H "%REFERER_HEADER%" -F "databaseType=%DB_TYPE%" -F "host=%DB_HOST%" -F "port=%DB_PORT%" -F "databaseName=%DB_NAME%" -F "username=%DB_USER%" -F "password=%DB_PASSWORD%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.message) { $r.message } } catch { }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF "%HTTP_CODE%"=="200" GOTO works
IF "%HTTP_CODE%"=="204" GOTO works
EXIT /B 1
:works
echo The connection works.
