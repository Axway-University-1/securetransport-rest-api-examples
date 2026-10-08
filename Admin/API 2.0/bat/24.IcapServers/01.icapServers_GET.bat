@echo off
REM ==============================================================================
REM Script Name: 01.icapServers_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the ICAP servers using the `/icapServers` endpoint: the antivirus
REM or data loss prevention servers SecureTransport sends transfers to, to be scanned.
REM It demonstrates:
REM - Counting them, and listing them with their type, address and whether enabled
REM - Only the enabled ones, with serverEnabled=
REM - One server by its name, with basicSettings.name=
REM - Only the ones of one type, with basicSettings.type=
REM
REM Usage:
REM 01.icapServers_GET.bat [NAME [TYPE]]
REM
REM   NAME  list the server with exactly this name (optional)
REM   TYPE  only the servers of this type: INCOMING, OUTGOING or BOTH (optional)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - An ICAP server scans transfers only for the business units that list it in
REM   enabledIcapServers (see 12.BusinessUnits), and only while it is enabled.
REM - Confirmed directly: the answer is {resultSet, result}. basicSettings.name= and
REM   basicSettings.url= are matched exactly: no * wildcard, and not without regard to
REM   case. A type that does not exist answers 400 "Unknown name value ... for enum
REM   class".
REM - PowerShell is used to print one server per line, in place of jq.
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Exit codes: 0 when every answer is 200, 1 otherwise, 2 when TYPE is not INCOMING, OUTGOING or BOTH, or there are more than two arguments (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\icap_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/icapServers
SET NAME=%~1
SET TYPE=%~2
IF NOT "%~3"=="" GOTO usage
IF "%TYPE%"=="" GOTO type_ok
IF "%TYPE%"=="INCOMING" GOTO type_ok
IF "%TYPE%"=="OUTGOING" GOTO type_ok
IF "%TYPE%"=="BOTH" GOTO type_ok
echo TYPE is INCOMING, OUTGOING or BOTH, not %TYPE%.
EXIT /B 2
:type_ok

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
SET "URL=%MAIN_URL%?limit=1&fields=serverEnabled"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
FOR /F %%N IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount"') DO echo ICAP servers: %%N

echo.
echo All of them: name, type, address, enabled:
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "fields=serverEnabled,basicSettings.name,basicSettings.type,basicSettings.url"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($s in $r.result) { $e = if ($s.serverEnabled) { 'enabled' } else { 'disabled' }; '  {0}  {1}  {2}  {3}' -f $s.basicSettings.name, $s.basicSettings.type, $s.basicSettings.url, $e }"

echo.
echo Only the enabled ones:
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "serverEnabled=true" --data-urlencode "fields=serverEnabled,basicSettings.name,basicSettings.type,basicSettings.url"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($s in $r.result) { $e = if ($s.serverEnabled) { 'enabled' } else { 'disabled' }; '  {0}  {1}  {2}  {3}' -f $s.basicSettings.name, $s.basicSettings.type, $s.basicSettings.url, $e }"

IF NOT "%NAME%"=="" CALL :by_name
IF ERRORLEVEL 1 EXIT /B 1
IF NOT "%TYPE%"=="" CALL :by_type
IF ERRORLEVEL 1 EXIT /B 1
EXIT /B 0

REM ------------------------------------------------------------------------------
REM The one named NAME
REM ------------------------------------------------------------------------------
:by_name
echo.
echo The one named %NAME%:
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "basicSettings.name=%NAME%" --data-urlencode "fields=serverEnabled,basicSettings.name,basicSettings.type,basicSettings.url"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($s in $r.result) { $e = if ($s.serverEnabled) { 'enabled' } else { 'disabled' }; '  {0}  {1}  {2}  {3}' -f $s.basicSettings.name, $s.basicSettings.type, $s.basicSettings.url, $e }"
EXIT /B 0

REM ------------------------------------------------------------------------------
REM The ones of type TYPE
REM ------------------------------------------------------------------------------
:by_type
echo.
echo Only the ones of type %TYPE%:
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "basicSettings.type=%TYPE%" --data-urlencode "fields=serverEnabled,basicSettings.name,basicSettings.type,basicSettings.url"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($s in $r.result) { $e = if ($s.serverEnabled) { 'enabled' } else { 'disabled' }; '  {0}  {1}  {2}  {3}' -f $s.basicSettings.name, $s.basicSettings.type, $s.basicSettings.url, $e }"
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
echo Usage: 01.icapServers_GET.bat [NAME [TYPE]]
EXIT /B 2
