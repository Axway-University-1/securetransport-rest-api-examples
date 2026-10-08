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
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Exit codes: 0 when every answer is 200, 1 otherwise, 2 when there is more than one argument (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET PATTERN=%~1
IF "%PATTERN%"=="" SET PATTERN=AddressBook*
IF NOT "%~2"=="" GOTO usage

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
SET "URL=%MAIN_URL%/options?limit=1&fields=name"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
FOR /F %%N IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount"') DO echo Server Configuration Options: %%N

echo.
echo The options named %PATTERN%: name = values (default):
SET "URL=%MAIN_URL%/options"
SET CURL_OPTS=-G --data-urlencode "name=%PATTERN%" --data-urlencode "fields=name,values,defaultValues"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($o in $r.result) { '  {0} = {1} ({2})' -f $o.name, ($o.values -join ', '), ($o.defaultValues -join ', ') }"

echo.
echo The first 10 options changed from their default:
SET "URL=%MAIN_URL%/options?isModified=true&limit=10&fields=name,values"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($o in $r.result) { '  {0} = {1}' -f $o.name, ($o.values -join ', ') }"
EXIT /B 0

REM ------------------------------------------------------------------------------
REM A GET of the URL in URL, with the curl options in CURL_OPTS (for example -G --data-urlencode ...). The answer goes to
REM RESPONSE_FILE. A status other than 200 prints the status and the answer and returns 1.
REM ------------------------------------------------------------------------------
:st_get
SET HTTP_CODE=
SET OPTS=%CURL_OPTS%
SET CURL_OPTS=
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" %OPTS% -X GET "%URL%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" EXIT /B 0
echo HTTP %HTTP_CODE%
IF EXIST "%RESPONSE_FILE%" TYPE "%RESPONSE_FILE%"
EXIT /B 1

:usage
echo Usage: 03.configurations_options_GET.bat [PATTERN]
EXIT /B 2
