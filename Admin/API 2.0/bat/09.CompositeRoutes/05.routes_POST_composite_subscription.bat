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
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Run these first:
REM     08.RouteTemplates/02.routes_POST.bat               the template RouteFromPartner
REM     07.Subscriptions/02.subscriptions_POST.bat         john's subscription on /inbox
REM     09.CompositeRoutes/03.routes_POST_simple_compress.bat   SimpleRoute_Compress
REM - It uses a different template than 02.routes_POST.bat, so the two do not
REM   touch each other's routes.
REM - PowerShell is used to read the ids out of the responses and build the body, in place of jq.
REM - Every call is checked: the three lookups must answer 200, and the creation 201 (the status is printed); anything else prints
REM   the status and the server's answer and ends the script with exit 1.
REM - Exit codes: 0 when the route was created, 1 otherwise.
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
SET BODY_FILE=%TEMP%\composite_body_%RANDOM%.json

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B %RC%

:main
SET ROUTE_TEMPLATE_ID=
SET "URL=%MAIN_URL%/routes?fields=id&name=%ROUTE_TEMPLATE_NAME%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result[0].id } catch { }"') DO SET ROUTE_TEMPLATE_ID=%%I
IF "%ROUTE_TEMPLATE_ID%"=="" (
    echo Could not find the route template '%ROUTE_TEMPLATE_NAME%'. Run 08.RouteTemplates first.
    EXIT /B 1
)

SET SUBSCRIPTION_ID=
SET "URL=%MAIN_URL%/subscriptions?account=%ACCOUNT%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { ((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result | Where-Object { $_.folder -eq $env:SUBSCRIPTION_FOLDER } | Select-Object -First 1).id } catch { }"') DO SET SUBSCRIPTION_ID=%%I
IF "%SUBSCRIPTION_ID%"=="" (
    echo Could not find a subscription of '%ACCOUNT%' on '%SUBSCRIPTION_FOLDER%'. Run 07.Subscriptions first.
    EXIT /B 1
)

SET SIMPLE_ROUTE_ID=
SET "URL=%MAIN_URL%/routes?fields=id&name=%SIMPLE_ROUTE_NAME%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result[0].id } catch { }"') DO SET SIMPLE_ROUTE_ID=%%I
IF "%SIMPLE_ROUTE_ID%"=="" (
    echo Could not find the simple route '%SIMPLE_ROUTE_NAME%'. Run 03.routes_POST_simple_compress.bat first.
    EXIT /B 1
)

echo Template %ROUTE_TEMPLATE_ID%, subscription %SUBSCRIPTION_ID%, simple route %SIMPLE_ROUTE_ID%

powershell -NoProfile -Command "[IO.File]::WriteAllText($env:BODY_FILE, ([ordered]@{ type = 'COMPOSITE'; account = $env:ACCOUNT; name = $env:ROUTE_NAME; conditionType = 'MATCH_ALL'; routeTemplate = $env:ROUTE_TEMPLATE_ID; subscriptions = @($env:SUBSCRIPTION_ID); steps = @([ordered]@{ type = 'ExecuteRoute'; status = 'ENABLED'; autostart = $false; executeRoute = $env:SIMPLE_ROUTE_ID }) } | ConvertTo-Json -Compress -Depth 5))"

echo Creating the composite route '%ROUTE_NAME%'...
SET HTTP_CODE=
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%/routes" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF "%HTTP_CODE%"=="201" EXIT /B 0
IF EXIST "%RESPONSE_FILE%" powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
EXIT /B 1

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
