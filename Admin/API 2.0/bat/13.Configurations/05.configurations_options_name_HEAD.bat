@echo off
REM ==============================================================================
REM Script Name: 05.configurations_options_name_HEAD.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script checks whether a Server Configuration Option exists, using the
REM `/configurations/options/{name}` endpoint with HEAD: 200 when it does, 404
REM when it does not.
REM
REM Usage:
REM 05.configurations_options_name_HEAD.bat [NAME]
REM
REM   NAME  the option (default AddressBook.Enabled)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET NAME=%~1
IF "%NAME%"=="" SET NAME=AddressBook.Enabled

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "%MAIN_URL%/options/%NAME%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" (
    echo The option %NAME% exists.
) ELSE (
    echo The option %NAME% does not exist ^(HTTP %HTTP_CODE%^).
    EXIT /B 1
)
