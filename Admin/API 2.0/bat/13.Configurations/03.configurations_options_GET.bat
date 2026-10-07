@echo off
REM ==============================================================================
REM Script Name: 03.configurations_options_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the Server Configuration Options using the
REM `/configurations/options` endpoint. It demonstrates:
REM - Counting them
REM - Searching by name, with the * wildcard
REM - The ones changed from their default (isModified=true)
REM - Asking for some fields only, with fields=
REM
REM Usage:
REM 03.configurations_options_GET.bat [PATTERN]
REM
REM   PATTERN  an option name, * matches anything (default AddressBook*)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - values is always a list, even for an option with one value; defaultValues
REM   is the value it has when nothing is set.
REM - values= searches by value, also with *.
REM - PowerShell is used to print one option per line, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET PATTERN=%~1
IF "%PATTERN%"=="" SET PATTERN=AddressBook*
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/options?limit=1&fields=name" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F %%N IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount"') DO echo Server Configuration Options: %%N

echo.
echo The options named %PATTERN%: name = values (default):
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%/options" --data-urlencode "name=%PATTERN%" ^
  --data-urlencode "fields=name,values,defaultValues" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($o in $r.result) { '  {0} = {1} ({2})' -f $o.name, ($o.values -join ', '), ($o.defaultValues -join ', ') }"

echo.
echo The first 10 options changed from their default:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/options?isModified=true&limit=10&fields=name,values" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($o in $r.result) { '  {0} = {1}' -f $o.name, ($o.values -join ', ') }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
