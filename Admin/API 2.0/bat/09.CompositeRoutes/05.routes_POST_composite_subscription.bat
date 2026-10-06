@echo off
REM ==============================================================================
REM Script Name: 05.routes_POST_composite_subscription.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script creates a composite route that is linked to a subscription, using
REM the `/routes` endpoint. Linked this way, the route runs on every file that
REM arrives in the subscription's folder. It demonstrates:
REM - Looking up three ids by name: the route template, the subscription and the
REM   simple route to run
REM - Creating a composite route that inherits the template, lists the
REM   subscription, and runs the simple route through an ExecuteRoute step
REM
REM Usage:
REM 05.routes_POST_composite_subscription.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Run these first:
REM     08.RouteTemplates\02.routes_POST.bat               the template RouteFromPartner
REM     07.Subscriptions\02.subscriptions_POST.bat         john's subscription on /inbox
REM     09.CompositeRoutes\03.routes_POST_simple_compress.bat   SimpleRoute_Compress
REM - It uses a different template than 02.routes_POST.bat, so the two do not
REM   touch each other's routes.
REM - PowerShell is used to read the ids out of the responses, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0

SET ACCOUNT=john
SET ROUTE_NAME=CompositeRoute_Subscription
SET ROUTE_TEMPLATE_NAME=RouteFromPartner
SET SUBSCRIPTION_FOLDER=/inbox
SET SIMPLE_ROUTE_NAME=SimpleRoute_Compress
SET RESPONSE_FILE=%TEMP%\composite_%RANDOM%.json

SET ROUTE_TEMPLATE_ID=
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/routes?fields=id&name=%ROUTE_TEMPLATE_NAME%" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result[0].id } catch { }"') DO SET ROUTE_TEMPLATE_ID=%%I
IF "%ROUTE_TEMPLATE_ID%"=="" (
    echo Could not find the route template '%ROUTE_TEMPLATE_NAME%'. Run 08.RouteTemplates first.
    GOTO :fail
)

SET SUBSCRIPTION_ID=
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/subscriptions?account=%ACCOUNT%" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { ((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result | Where-Object { $_.folder -eq $env:SUBSCRIPTION_FOLDER } | Select-Object -First 1).id } catch { }"') DO SET SUBSCRIPTION_ID=%%I
IF "%SUBSCRIPTION_ID%"=="" (
    echo Could not find a subscription of '%ACCOUNT%' on '%SUBSCRIPTION_FOLDER%'. Run 07.Subscriptions first.
    GOTO :fail
)

SET SIMPLE_ROUTE_ID=
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/routes?fields=id&name=%SIMPLE_ROUTE_NAME%" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result[0].id } catch { }"') DO SET SIMPLE_ROUTE_ID=%%I
IF "%SIMPLE_ROUTE_ID%"=="" (
    echo Could not find the simple route '%SIMPLE_ROUTE_NAME%'. Run 03.routes_POST_simple_compress.bat first.
    GOTO :fail
)

echo Template %ROUTE_TEMPLATE_ID%, subscription %SUBSCRIPTION_ID%, simple route %SIMPLE_ROUTE_ID%

echo Creating the composite route '%ROUTE_NAME%'...
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%/routes" ^
  -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
  -w "\nHTTP %%{http_code}\n" ^
  -d "{\"type\":\"COMPOSITE\",\"account\":\"%ACCOUNT%\",\"name\":\"%ROUTE_NAME%\",\"conditionType\":\"MATCH_ALL\",\"routeTemplate\":\"%ROUTE_TEMPLATE_ID%\",\"subscriptions\":[\"%SUBSCRIPTION_ID%\"],\"steps\":[{\"type\":\"ExecuteRoute\",\"status\":\"ENABLED\",\"autostart\":false,\"executeRoute\":\"%SIMPLE_ROUTE_ID%\"}]}"

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0

:fail
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 1
