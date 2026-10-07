@echo off
REM ==============================================================================
REM Script Name: 44.configurations_externalStores_name_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes an external store, using the
REM `/configurations/externalStores/{externalStoreName}` endpoint.
REM
REM Usage:
REM 44.configurations_externalStores_name_DELETE.bat [NAME]
REM
REM   NAME  the external store (default example_vault)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Anything that fetches its secrets from the store stops working: only ever
REM   point it at a store you created.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_vault

echo Deleting the external store %NAME%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/externalStores/%NAME%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" EXIT /B 1
