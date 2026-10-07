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
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0

SET ACCOUNT=john
SET SIMPLE_ROUTE_NAME=SimpleRoute_Compress
SET RESPONSE_FILE=%TEMP%\routes_%RANDOM%.json

echo The composite routes of '%ACCOUNT%': id, name, template, subscriptions...
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/routes?type=COMPOSITE" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$j = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($r in ($j.result | Where-Object { $_.account -eq $env:ACCOUNT })) { '{0}  {1}  template={2}  subscriptions={3}' -f $r.id, $r.name, $r.routeTemplate, ($r.subscriptions -join ',') }"

echo.
echo The steps of the simple route '%SIMPLE_ROUTE_NAME%'...
SET SIMPLE_ROUTE_ID=
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/routes?fields=id&name=%SIMPLE_ROUTE_NAME%" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result[0].id } catch { }"') DO SET SIMPLE_ROUTE_ID=%%I

IF "%SIMPLE_ROUTE_ID%"=="" (
    echo There is no route '%SIMPLE_ROUTE_NAME%'.
    GOTO :done
)

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/routes/%SIMPLE_ROUTE_ID%" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($s in $r.steps) { '  {0}  {1}' -f $s.type, $s.status }"

:done
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
