@echo off
REM ==============================================================================
REM Script Name: 25.configurations_maintenance_operations_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script turns maintenance mode for zero downtime updates on or off, using
REM the `/configurations/maintenance/operations` endpoint. Maintenance mode keeps
REM automated systems from changing the server while it is updated.
REM
REM Usage:
REM 25.configurations_maintenance_operations_POST.bat start|stop
REM
REM Risk: disruptive - puts the whole server in maintenance mode
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - NOT RUN on the shared lab these examples were checked against: it changes
REM   the whole server, and cannot simply be undone. Its request is checked
REM   offline, against a stub.
REM - Zero downtime updates are licensed only with an active SecureTransport
REM   Enterprise Pack subscription; starting maintenance mode accepts that.
REM - 24.configurations_maintenance_GET.bat reads the mode.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET OPERATION=%~1
IF NOT "%OPERATION%"=="start" IF NOT "%OPERATION%"=="stop" (
    echo Usage: 25.configurations_maintenance_operations_POST.bat start^|stop
    EXIT /B 2
)
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json
SET BODY_FILE=

echo Maintenance mode: %OPERATION%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%/maintenance/operations?operation=%OPERATION%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF "%HTTP_CODE%"=="200" GOTO done
IF "%HTTP_CODE%"=="204" GOTO done
TYPE "%RESPONSE_FILE%"
echo.
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 1
:done
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
