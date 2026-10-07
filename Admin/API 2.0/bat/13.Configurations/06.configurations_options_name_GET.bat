@echo off
REM ==============================================================================
REM Script Name: 06.configurations_options_name_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads one Server Configuration Option, using the
REM `/configurations/options/{name}` endpoint: its values, its default, its
REM description, and whether it can be changed.
REM
REM Usage:
REM 06.configurations_options_name_GET.bat [NAME]
REM
REM   NAME  the option (default AddressBook.Enabled)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - encrypted options, passwords for example, come back empty.
REM - PowerShell is used to print the summary, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET NAME=%~1
IF "%NAME%"=="" SET NAME=AddressBook.Enabled
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/options/%NAME%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
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
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; '  {0} = {1}, default {2}' -f $r.name, ($r.values -join ', '), ($r.defaultValues -join ', '); $t = if ($r.readOnly) { 'read only' } else { 'can be changed' }; if ($r.encrypted) { $t += ', encrypted' }; if ($r.isLocal) { $t += ', local to this server' }; '  ' + $t"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
