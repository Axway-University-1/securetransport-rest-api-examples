@echo off
REM ==============================================================================
REM Script Name: 06.routes_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script retrieves routes using the `/routes` endpoint.
REM It demonstrates:
REM - A GET request for the composite routes, kept to one account and printed as
REM   one line per route, with the template and subscriptions it is linked to
REM - A GET request for one route by its id, printing the type of each step
REM
REM Usage:
REM 06.routes_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - This example uses the account "john" and the simple route
REM   SimpleRoute_Compress, which 03.routes_POST_simple_compress.bat creates.
REM - PowerShell is used to print the short listings, in place of jq.
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Exit codes: 0 when every answer is 200 (also when there is no such simple route: that is said and is not an error), 1 otherwise.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\routes_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0

SET "ACCOUNT=%ST_EXAMPLE_ACCOUNT%"
IF "%ACCOUNT%"=="" SET "ACCOUNT=john"
SET SIMPLE_ROUTE_NAME=SimpleRoute_Compress

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
echo The composite routes of '%ACCOUNT%': id, name, template, subscriptions...
SET "URL=%MAIN_URL%/routes?type=COMPOSITE"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "$j = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($r in @($j.result | Where-Object { $_.account -eq $env:ACCOUNT })) { if ($r) { '{0}  {1}  template={2}  subscriptions={3}' -f $r.id, $r.name, $r.routeTemplate, ($r.subscriptions -join ',') } }"

echo.
echo The steps of the simple route '%SIMPLE_ROUTE_NAME%'...
SET SIMPLE_ROUTE_ID=
SET "URL=%MAIN_URL%/routes?fields=id&name=%SIMPLE_ROUTE_NAME%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result[0].id } catch { }"') DO SET SIMPLE_ROUTE_ID=%%I

IF "%SIMPLE_ROUTE_ID%"=="" (
    echo There is no route '%SIMPLE_ROUTE_NAME%'.
    EXIT /B 0
)

SET "URL=%MAIN_URL%/routes/%SIMPLE_ROUTE_ID%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($s in @($r.steps)) { if ($s) { '  {0}  {1}' -f $s.type, $s.status } }"
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
