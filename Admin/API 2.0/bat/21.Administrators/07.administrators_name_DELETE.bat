@echo off
REM ==============================================================================
REM Script Name: 07.administrators_name_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes an administrator, using the `/administrators/{name}`
REM endpoint.
REM
REM Usage:
REM 07.administrators_name_DELETE.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It deletes example_admin, which 02.administrators_POST.bat creates. Only ever
REM   point it at an administrator you created.
REM - Its API keys go with it.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrators
SET ADMIN=example_admin

echo Deleting the administrator %ADMIN%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/%ADMIN%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" EXIT /B 1
