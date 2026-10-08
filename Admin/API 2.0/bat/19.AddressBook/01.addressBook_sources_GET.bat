@echo off
REM ==============================================================================
REM Script Name: 01.addressBook_sources_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the address book sources using the `/addressBook/sources`
REM endpoint: where the end users' address book finds the people they share
REM with - the local accounts, an LDAP directory, or a custom source. It
REM demonstrates:
REM - Listing every source
REM - Filtering by type and by whether a source is enabled
REM - Asking for some fields only, with fields=
REM
REM Usage:
REM 01.addressBook_sources_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - type is LOCAL, LDAP or CUSTOM. name and parentGroup filter too.
REM - A server comes with its sources; the API has no POST or DELETE for them,
REM   only reading and changing (see 04 and 05 in this folder).
REM - PowerShell is used to print one source per line, in place of jq.
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Exit codes: 0 when every answer is 200, 1 otherwise.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\sources_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/addressBook/sources

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
echo Every address book source:
SET "URL=%MAIN_URL%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
TYPE "%RESPONSE_FILE%"

echo.
echo.
echo The LDAP sources only:
SET "URL=%MAIN_URL%?type=LDAP"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
TYPE "%RESPONSE_FILE%"

echo.
echo.
echo The enabled ones, one line each: id, type, name, group:
SET "URL=%MAIN_URL%?enabled=true&fields=id,type,name,parentGroup"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($s in $r.result) { '  {0}  {1}  {2}  {3}' -f $s.id, $s.type, $s.name, $s.parentGroup }"
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
