@echo off
REM ==============================================================================
REM Script Name: 02.routes_POST.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Composite Routes are a type of route that allows you to inherit a Route
REM Template and extend it with additional routes if needed.
REM
REM This script shows how to create a composite route using the `/routes`
REM endpoint. It demonstrates:
REM - Looking up the ID of an existing route template by name
REM - Creating a composite route that inherits a template without extending it
REM - Creating a simple route and reading its new ID from the Location header
REM - Creating a composite route that inherits a template and extends it with
REM   that simple route, through an ExecuteRoute step
REM
REM Usage:
REM 02.routes_POST.bat
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The route template must already exist. Run 08.RouteTemplates first.
REM - The account "john" must already exist.
REM - PowerShell is used to read the route template ID out of the response, in place of jq.
REM - Every call is checked: the template lookup must answer 200, each creation 201 (the status is printed); anything else prints
REM   the status and the server's answer and ends the script with exit 1. The bodies are built by jq.
REM - Exit codes: 0 when all three routes were created, 1 otherwise.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/routes
SET "ACCOUNT=%ST_EXAMPLE_ACCOUNT%"
IF "%ACCOUNT%"=="" SET "ACCOUNT=john"
SET RESPONSE_FILE=%TEMP%\route_response_%RANDOM%.json
SET BODY_FILE=%TEMP%\route_body_%RANDOM%.json
SET HEADERS_FILE=%TEMP%\route_headers_%RANDOM%.txt

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
EXIT /B %RC%

:main
REM ==============================================================================
REM First, get the ID of the Route Template we need
REM ==============================================================================
SET ROUTE_TEMPLATE_NAME=RouteFromAccountant
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?fields=id&name=%ROUTE_TEMPLATE_NAME%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo HTTP %HTTP_CODE%
    IF EXIST "%RESPONSE_FILE%" TYPE "%RESPONSE_FILE%"
    EXIT /B 1
)

SET ROUTE_TEMPLATE_ID=
FOR /F "tokens=*" %%I IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result[0].id } catch { }"') DO SET ROUTE_TEMPLATE_ID=%%I

IF "%ROUTE_TEMPLATE_ID%"=="" (
    echo Error: Could not retrieve Route Template ID for '%ROUTE_TEMPLATE_NAME%'. Please check if the route template exists.
    EXIT /B 1
)
echo Route Template ID for '%ROUTE_TEMPLATE_NAME%': %ROUTE_TEMPLATE_ID%
echo.

REM ==============================================================================
REM Example 1, without extension
REM Simple POST to create a package route in SecureTransport
REM ==============================================================================
echo Creating a composite route without extension...
powershell -NoProfile -Command "[IO.File]::WriteAllText($env:BODY_FILE, ([ordered]@{ account = $env:ACCOUNT; name = 'CompositeRoute_WithoutExtension'; type = 'COMPOSITE'; conditionType = 'MATCH_ALL'; routeTemplate = $env:ROUTE_TEMPLATE_ID } | ConvertTo-Json -Compress))"
CALL :post_route
IF ERRORLEVEL 1 EXIT /B 1
echo.

REM ==============================================================================
REM Example 2, with extension
REM To create a composite route with an extension, we will first create a simple
REM route that will be used as an extension.
REM ==============================================================================
echo Creating a simple route...
powershell -NoProfile -Command "$s = [ordered]@{ type = 'EncodingConversion'; status = 'ENABLED'; conditionType = 'ALWAYS'; usePrecedingStepFiles = $false; fileFilterExpression = 'string'; fileFilterExpressionType = 'GLOB'; inputCharset = 'UTF-8'; outputCharset = 'UTF-8'; postTransformationActionRenameAsExpression = 'string'; actionOnStepFailure = 'PROCEED' }; [IO.File]::WriteAllText($env:BODY_FILE, ([ordered]@{ name = 'SimpleRouteName'; type = 'SIMPLE'; conditionType = 'ALWAYS'; steps = @($s) } | ConvertTo-Json -Compress -Depth 5))"
CALL :post_route
IF ERRORLEVEL 1 EXIT /B 1

REM The new resource URL is returned in the Location header. The ID is its last segment.
SET LOCATION=
FOR /F "tokens=2" %%L IN ('findstr /B /I "Location:" "%HEADERS_FILE%"') DO SET LOCATION=%%L
IF "%LOCATION%"=="" (
    echo Error: Could not read the Location header of the new simple route.
    EXIT /B 1
)
echo Resource created at: %LOCATION%

FOR /F "tokens=*" %%S IN ('powershell -NoProfile -Command "[IO.Path]::GetFileName($env:LOCATION)"') DO SET SIMPLE_ROUTE_ID=%%S
echo New resource ID: %SIMPLE_ROUTE_ID%
echo.

echo Creating a composite route with extension...
powershell -NoProfile -Command "[IO.File]::WriteAllText($env:BODY_FILE, ([ordered]@{ account = $env:ACCOUNT; name = 'CompositeRoute_WithExtension'; type = 'COMPOSITE'; conditionType = 'MATCH_ALL'; routeTemplate = $env:ROUTE_TEMPLATE_ID; steps = @([ordered]@{ type = 'ExecuteRoute'; status = 'ENABLED'; executeRoute = $env:SIMPLE_ROUTE_ID; autostart = $false }) } | ConvertTo-Json -Compress -Depth 5))"
CALL :post_route
IF ERRORLEVEL 1 EXIT /B 1
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Posts the body in BODY_FILE to /routes: prints the status, and the server's answer unless it is 201 (then returns 1)
REM ------------------------------------------------------------------------------
:post_route
SET HTTP_CODE=
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -D "%HEADERS_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF "%HTTP_CODE%"=="201" EXIT /B 0
IF EXIST "%RESPONSE_FILE%" powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
EXIT /B 1
