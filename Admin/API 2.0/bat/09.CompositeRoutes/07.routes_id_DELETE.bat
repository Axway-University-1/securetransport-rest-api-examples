@echo off
REM ==============================================================================
REM Script Name: 07.routes_id_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes routes using the `/routes/{id}` endpoint.
REM A route is deleted by its id, not its name, so it demonstrates:
REM - Looking up the id of a route by name
REM - Deleting the composite routes first, and only then the simple routes they
REM   run, since a simple route in use cannot be deleted
REM
REM Usage:
REM 07.routes_id_DELETE.bat
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - This cleans up the routes 02 to 05 in this folder create for the account
REM   "john". Only ever point it at routes you created.
REM - Composite route names are only unique within an account, so a composite
REM   route is matched by its account as well as its name.
REM - The route templates are left in place. 08.RouteTemplates created them.
REM - PowerShell is used to read the ids out of the responses, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0

SET ACCOUNT=john
SET RESPONSE_FILE=%TEMP%\routes_%RANDOM%.json

CALL :delete_route COMPOSITE CompositeRoute_Subscription
CALL :delete_route COMPOSITE CompositeRoute_WithExtension
CALL :delete_route COMPOSITE CompositeRoute_WithoutExtension

CALL :delete_route SIMPLE SimpleRoute_Compress
CALL :delete_route SIMPLE SimpleRoute_Decompress
CALL :delete_route SIMPLE SimpleRouteName

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0

REM delete_route TYPE NAME
:delete_route
SET ROUTE_TYPE=%1
SET ROUTE_NAME=%2
SET ROUTE_ID=
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/routes?type=%ROUTE_TYPE%&name=%ROUTE_NAME%" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { ((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result | Where-Object { $env:ROUTE_TYPE -eq 'SIMPLE' -or $_.account -eq $env:ACCOUNT } | Select-Object -First 1).id } catch { }"') DO SET ROUTE_ID=%%I

IF "%ROUTE_ID%"=="" (
    echo There is no %ROUTE_TYPE% route '%ROUTE_NAME%'.
    EXIT /B 0
)

echo Deleting the %ROUTE_TYPE% route '%ROUTE_NAME%' (%ROUTE_ID%)...
curl -s -o nul -w "HTTP %%{http_code}\n" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/routes/%ROUTE_ID%" ^
  -H "accept: */*" -H "%REFERER_HEADER%"
EXIT /B 0
